#!/bin/bash
set -euo pipefail

# Apache Superset installer for the existing Big Data laboratory
# Existing environment: Hadoop, NiFi, MySQL, phpMyAdmin, Sqoop
# Superset URL: http://localhost:8088

SUPERSET_VERSION="6.1.0"
SUPERSET_DIR="/opt/superset"
VENV_DIR="${SUPERSET_DIR}/venv"
CONFIG_FILE="${SUPERSET_DIR}/superset_config.py"
SERVICE_FILE="/etc/systemd/system/superset.service"

SUPERSET_ADMIN_USERNAME="admin"
SUPERSET_ADMIN_PASSWORD="Admin123456789"
SUPERSET_ADMIN_FIRSTNAME="Superset"
SUPERSET_ADMIN_LASTNAME="Admin"
SUPERSET_ADMIN_EMAIL="admin@localhost.local"

# Use the normal user even when the installer is executed with sudo.
INSTALL_USER="${SUDO_USER:-$USER}"
INSTALL_GROUP="$(id -gn "${INSTALL_USER}")"
INSTALL_HOME="$(getent passwd "${INSTALL_USER}" | cut -d: -f6)"

echo "Installing Apache Superset ${SUPERSET_VERSION}..."
echo "Installation user: ${INSTALL_USER}"

# Install required Ubuntu packages.
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
    curl

# Create the Superset installation directory.
sudo mkdir -p "${SUPERSET_DIR}"
sudo chown -R "${INSTALL_USER}:${INSTALL_GROUP}" "${SUPERSET_DIR}"

# Create a clean Python virtual environment.
if [ -d "${VENV_DIR}" ]; then
    echo "Removing the previous Superset virtual environment..."
    sudo rm -rf "${VENV_DIR}"
fi

sudo -u "${INSTALL_USER}" python3 -m venv "${VENV_DIR}"

# Upgrade the Python packaging tools.
sudo -u "${INSTALL_USER}" "${VENV_DIR}/bin/pip" install \
    --upgrade pip setuptools wheel

# Install Superset, Gunicorn, both MySQL drivers, and dependencies that
# Superset 6.1.0 may omit on Python 3.12/aarch64.
sudo -u "${INSTALL_USER}" "${VENV_DIR}/bin/pip" install \
    "apache_superset==${SUPERSET_VERSION}" \
    gunicorn \
    gevent \
    mysqlclient \
    pymysql \
    rich \
    cachetools

# Generate and preserve a secure secret key.
if [ -f "${CONFIG_FILE}" ] && grep -q "^SECRET_KEY" "${CONFIG_FILE}"; then
    SECRET_KEY="$(sed -n "s/^SECRET_KEY = ['\"]\(.*\)['\"]$/\1/p" "${CONFIG_FILE}" | head -n 1)"
fi

if [ -z "${SECRET_KEY:-}" ]; then
    SECRET_KEY="$(openssl rand -base64 42 | tr -d '\n')"
fi

# Create the Superset configuration.
cat > /tmp/superset_config.py <<EOF
import os

SECRET_KEY = "${SECRET_KEY}"

# Lab metadata database. This is separate from dbtest.
SQLALCHEMY_DATABASE_URI = "sqlite:///${SUPERSET_DIR}/superset.db"

# Allow CSV and Excel uploads in the laboratory.
CSV_EXTENSIONS = {"csv", "tsv", "txt"}
EXCEL_EXTENSIONS = {"xls", "xlsx"}

# Listen on all interfaces through Gunicorn.
SUPERSET_WEBSERVER_ADDRESS = "0.0.0.0"
SUPERSET_WEBSERVER_PORT = 8088

# Avoid CSRF errors caused by long lab sessions.
WTF_CSRF_ENABLED = True

# A simple local cache suitable for this single-machine laboratory.
CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
}
DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
}

# Enable database uploads from the Superset interface when supported.
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
}
EOF

sudo mv /tmp/superset_config.py "${CONFIG_FILE}"
sudo chown "${INSTALL_USER}:${INSTALL_GROUP}" "${CONFIG_FILE}"
sudo chmod 600 "${CONFIG_FILE}"

# Environment used for all initialization commands.
export SUPERSET_CONFIG_PATH="${CONFIG_FILE}"
export FLASK_APP="superset"

# Upgrade/create the Superset metadata database.
sudo -u "${INSTALL_USER}" \
    env SUPERSET_CONFIG_PATH="${CONFIG_FILE}" FLASK_APP="superset" \
    "${VENV_DIR}/bin/superset" db upgrade

# Create the administrator only if it does not already exist.
if ! sudo -u "${INSTALL_USER}" \
    env SUPERSET_CONFIG_PATH="${CONFIG_FILE}" FLASK_APP="superset" \
    "${VENV_DIR}/bin/superset" fab list-users 2>/dev/null |
    grep -q "${SUPERSET_ADMIN_USERNAME}"; then

    sudo -u "${INSTALL_USER}" \
        env SUPERSET_CONFIG_PATH="${CONFIG_FILE}" FLASK_APP="superset" \
        "${VENV_DIR}/bin/superset" fab create-admin \
        --username "${SUPERSET_ADMIN_USERNAME}" \
        --firstname "${SUPERSET_ADMIN_FIRSTNAME}" \
        --lastname "${SUPERSET_ADMIN_LASTNAME}" \
        --email "${SUPERSET_ADMIN_EMAIL}" \
        --password "${SUPERSET_ADMIN_PASSWORD}"
else
    echo "Superset administrator already exists."
fi

# Initialize roles and permissions.
sudo -u "${INSTALL_USER}" \
    env SUPERSET_CONFIG_PATH="${CONFIG_FILE}" FLASK_APP="superset" \
    "${VENV_DIR}/bin/superset" init

# Create a systemd service so Superset starts automatically.
sudo tee "${SERVICE_FILE}" > /dev/null <<EOF
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
ExecStart=${VENV_DIR}/bin/gunicorn \
    --workers 2 \
    --worker-class gevent \
    --worker-connections 1000 \
    --timeout 120 \
    --bind 0.0.0.0:8088 \
    "superset.app:create_app()"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable superset
sudo systemctl restart superset

# Wait for Superset to respond before reporting success.
echo "Waiting for Superset to start..."
SUPERSET_READY=false

for attempt in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://127.0.0.1:8088/login/"; then
        SUPERSET_READY=true
        break
    fi

    sleep 2
done

echo ""
echo "=============================================="

if [ "${SUPERSET_READY}" = true ]; then
    echo "Apache Superset installation completed."
    echo "Health check: PASSED"
else
    echo "Apache Superset was installed, but its health check FAILED."
    echo "Review the service log below:"
    sudo journalctl -u superset -n 100 --no-pager || true
    exit 1
fi

echo "=============================================="
echo ""
echo "Status:"
sudo systemctl --no-pager --full status superset || true

echo ""
echo "Open Superset:"
echo "  Local computer: http://localhost:8088"
echo "  Another computer: http://<Ubuntu-IP>:8088"
echo ""
echo "Superset login:"
echo "  Username: ${SUPERSET_ADMIN_USERNAME}"
echo "  Password: ${SUPERSET_ADMIN_PASSWORD}"
echo ""
echo "Add the existing MySQL database in Superset:"
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
echo ""
