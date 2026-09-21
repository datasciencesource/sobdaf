#!/bin/bash
set -euo pipefail

# Apache Superset installer for an Ubuntu Big Data laboratory.
# Existing environment: Hadoop, NiFi, MySQL, phpMyAdmin, Sqoop.
# Run with: sudo bash install_superset.sh

SUPERSET_VERSION="6.1.0"
SUPERSET_DIR="/opt/superset"
VENV_DIR="${SUPERSET_DIR}/venv"
CONFIG_FILE="${SUPERSET_DIR}/superset_config.py"
SERVICE_FILE="/etc/systemd/system/superset.service"
METADATA_DB="${SUPERSET_DIR}/superset.db"

SUPERSET_ADMIN_USERNAME="admin"
SUPERSET_ADMIN_PASSWORD="Admin123456789"
SUPERSET_ADMIN_FIRSTNAME="Superset"
SUPERSET_ADMIN_LASTNAME="Admin"
SUPERSET_ADMIN_EMAIL="admin@localhost.local"

# Require root for package installation and service management.
if [ "${EUID}" -ne 0 ]; then
    echo "Run this script using: sudo bash $0"
    exit 1
fi

INSTALL_USER="${SUDO_USER:-$(id -un)}"
INSTALL_GROUP="$(id -gn "${INSTALL_USER}")"

trap 'echo "Installation failed at line ${LINENO}. Review the error above." >&2' ERR

echo "Installing Apache Superset ${SUPERSET_VERSION}..."
echo "Installation user: ${INSTALL_USER}"

# --------------------------------------------------
# 1. Install Ubuntu packages
# --------------------------------------------------
apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-venv \
    python3-dev \
    build-essential \
    libssl-dev \
    libffi-dev \
    libsasl2-dev \
    libldap2-dev \
    default-libmysqlclient-dev \
    pkg-config \
    openssl \
    curl \
    sudo

# Stop an existing service before modifying its environment.
if systemctl is-active --quiet superset.service; then
    echo "Stopping the existing Superset service..."
    systemctl stop superset.service
fi

# --------------------------------------------------
# 2. Prepare directories and back up existing metadata
# --------------------------------------------------
install -d \
    -o "${INSTALL_USER}" \
    -g "${INSTALL_GROUP}" \
    -m 750 \
    "${SUPERSET_DIR}"

BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"

if [ -f "${CONFIG_FILE}" ]; then
    cp -p "${CONFIG_FILE}" "${CONFIG_FILE}.backup_${BACKUP_STAMP}"
fi

if [ -f "${METADATA_DB}" ]; then
    # SQLite's backup API also handles committed WAL contents.
    python3 - "${METADATA_DB}" "${BACKUP_STAMP}" <<'PY'
import sqlite3
import sys

source_path, stamp = sys.argv[1:]
backup_path = f"{source_path}.backup_{stamp}"

with sqlite3.connect(source_path) as source:
    with sqlite3.connect(backup_path) as target:
        source.backup(target)

print(f"Metadata backup: {backup_path}")
PY
fi

chown -R "${INSTALL_USER}:${INSTALL_GROUP}" "${SUPERSET_DIR}"
chmod 750 "${SUPERSET_DIR}"

# --------------------------------------------------
# 3. Create or reuse the Python virtual environment
# --------------------------------------------------
if [ ! -x "${VENV_DIR}/bin/python" ]; then
    sudo -H -u "${INSTALL_USER}" \
        python3 -m venv "${VENV_DIR}"
else
    echo "Reusing the existing Python virtual environment."
fi

sudo -H -u "${INSTALL_USER}" \
    "${VENV_DIR}/bin/python" -m pip install \
    --upgrade pip setuptools wheel

# Pin the cache packages to avoid the
# SupersetMetastoreCache ignore_delete_many_errors error.
sudo -H -u "${INSTALL_USER}" \
    "${VENV_DIR}/bin/python" -m pip install \
    "apache_superset==${SUPERSET_VERSION}" \
    "Flask-Caching==2.3.1" \
    "cachelib==0.13.0" \
    gunicorn \
    gevent \
    mysqlclient \
    pymysql \
    rich \
    cachetools

sudo -H -u "${INSTALL_USER}" \
    "${VENV_DIR}/bin/python" -m pip check

# --------------------------------------------------
# 4. Preserve the existing secret key
# --------------------------------------------------
SECRET_KEY=""

if [ -f "${CONFIG_FILE}" ]; then
    # Read a literal SECRET_KEY assignment without executing the config.
    SECRET_KEY="$(python3 - "${CONFIG_FILE}" <<'PY'
import ast
import sys
from pathlib import Path

tree = ast.parse(Path(sys.argv[1]).read_text())
secret = None

for node in tree.body:
    if isinstance(node, ast.Assign):
        if any(
            isinstance(target, ast.Name) and target.id == "SECRET_KEY"
            for target in node.targets
        ):
            try:
                secret = ast.literal_eval(node.value)
            except (ValueError, TypeError):
                raise SystemExit(
                    "Cannot safely read the existing SECRET_KEY. "
                    "Preserve it manually before continuing."
                )

if not isinstance(secret, str) or not secret:
    raise SystemExit(
        "Existing configuration has no readable SECRET_KEY. "
        "Installation stopped to avoid replacing an existing key."
    )

print(secret)
PY
)"
elif [ -f "${METADATA_DB}" ]; then
    echo "Existing metadata database found without a configuration file."
    echo "Restore the original SECRET_KEY before continuing."
    exit 1
else
    SECRET_KEY="$(openssl rand -base64 42 | tr -d '\n')"
fi

# Encode the key as a valid Python string.
SECRET_KEY_LITERAL="$(
    printf '%s' "${SECRET_KEY}" |
        python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))'
)"

# --------------------------------------------------
# 5. Write Superset configuration
# --------------------------------------------------
# The previous configuration, when present, was backed up above.
(
    umask 077

    cat > "${CONFIG_FILE}" <<EOF
SECRET_KEY = ${SECRET_KEY_LITERAL}

# Superset metadata is separate from the MySQL analytics database.
# SQLite is used here for this laboratory installation.
SQLALCHEMY_DATABASE_URI = "sqlite:///${METADATA_DB}"

SUPERSET_WEBSERVER_ADDRESS = "0.0.0.0"
SUPERSET_WEBSERVER_PORT = 8088

# Keep CSRF protection enabled.
WTF_CSRF_ENABLED = True

# Local, process-specific caches for this laboratory.
CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
}

DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
}

# Allowed upload extensions.
# Upload permissions must also be enabled for the target database.
CSV_EXTENSIONS = {"csv", "tsv", "txt"}
EXCEL_EXTENSIONS = {"xls", "xlsx"}

# Enable Jinja templating in SQL.
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
}
EOF
)

chown "${INSTALL_USER}:${INSTALL_GROUP}" "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"
unset SECRET_KEY SECRET_KEY_LITERAL

# Helper for running commands with the correct user and environment.
run_superset() {
    sudo -H -u "${INSTALL_USER}" \
        env \
        SUPERSET_CONFIG_PATH="${CONFIG_FILE}" \
        FLASK_APP="superset" \
        "${VENV_DIR}/bin/superset" "$@"
}

# --------------------------------------------------
# 6. Initialize Superset metadata
# --------------------------------------------------
run_superset db upgrade

# Check the exact username in the laboratory metadata database.
ADMIN_EXISTS="$(
    sudo -H -u "${INSTALL_USER}" \
        "${VENV_DIR}/bin/python" - \
        "${METADATA_DB}" "${SUPERSET_ADMIN_USERNAME}" <<'PY'
import sqlite3
import sys

database, username = sys.argv[1:]

with sqlite3.connect(database) as connection:
    user = connection.execute(
        "SELECT 1 FROM ab_user WHERE username = ? LIMIT 1",
        (username,),
    ).fetchone()

print("yes" if user else "no")
PY
)"

if [ "${ADMIN_EXISTS}" = "no" ]; then
    run_superset fab create-admin \
        --username "${SUPERSET_ADMIN_USERNAME}" \
        --firstname "${SUPERSET_ADMIN_FIRSTNAME}" \
        --lastname "${SUPERSET_ADMIN_LASTNAME}" \
        --email "${SUPERSET_ADMIN_EMAIL}" \
        --password "${SUPERSET_ADMIN_PASSWORD}"
else
    echo "Administrator already exists; its password is unchanged."
fi

run_superset init

# --------------------------------------------------
# 7. Configure automatic startup
# --------------------------------------------------
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Apache Superset
After=network.target mysql.service
Wants=network.target

[Service]
Type=simple
User=${INSTALL_USER}
Group=${INSTALL_GROUP}
WorkingDirectory=${SUPERSET_DIR}
Environment="SUPERSET_CONFIG_PATH=${CONFIG_FILE}"
Environment="FLASK_APP=superset"
Environment="PATH=${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=${VENV_DIR}/bin/gunicorn --workers 2 --worker-class gevent --worker-connections 1000 --timeout 120 --bind 0.0.0.0:8088 --access-logfile - --error-logfile - "superset.app:create_app()"
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${SERVICE_FILE}"

systemctl daemon-reload
systemctl enable superset.service
systemctl restart superset.service

# --------------------------------------------------
# 8. Verify startup
# --------------------------------------------------
echo "Waiting for Superset to start..."
SUPERSET_READY=false

for attempt in $(seq 1 30); do
    if systemctl is-active --quiet superset.service &&
        curl --fail --silent \
            --connect-timeout 2 \
            --max-time 5 \
            --output /dev/null \
            "http://127.0.0.1:8088/health"; then
        SUPERSET_READY=true
        break
    fi

    sleep 2
done

if [ "${SUPERSET_READY}" != "true" ]; then
    echo "Superset startup check FAILED."
    journalctl -u superset.service -n 100 --no-pager || true
    exit 1
fi

echo ""
echo "=============================================="
echo "Apache Superset installation completed."
echo "Health check: PASSED"
echo "=============================================="

systemctl --no-pager --full status superset.service || true

echo ""
echo "Open Superset:"
echo "  Local computer: http://localhost:8088"
echo "  Another computer: http://<Ubuntu-IP>:8088"

echo ""
echo "Superset login:"
echo "  Username: ${SUPERSET_ADMIN_USERNAME}"

if [ "${ADMIN_EXISTS}" = "no" ]; then
    echo "  Password: ${SUPERSET_ADMIN_PASSWORD}"
else
    echo "  Password: Use your existing administrator password."
fi

echo ""
echo "Add the existing MySQL database:"
echo "  Settings -> Database Connections -> + Database"
echo ""
echo "SQLAlchemy URI:"
echo "  mysql+pymysql://usertest:Admin1111@127.0.0.1:3306/dbtest"

echo ""
echo "Useful commands:"
echo "  sudo systemctl status superset"
echo "  sudo systemctl restart superset"
echo "  sudo systemctl stop superset"
echo "  sudo journalctl -u superset -n 100 --no-pager"
