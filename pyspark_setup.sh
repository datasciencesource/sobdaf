#!/usr/bin/env bash
set -euo pipefail

# Under sudo, install the environment for the original user.
setup_user="$(id -un)"
if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    setup_user="$SUDO_USER"
fi
setup_home="$(getent passwd "$setup_user" | cut -d: -f6)"
if [[ -z "$setup_home" || ! -d "$setup_home" ]]; then
    echo "Cannot find an existing home directory for $setup_user." >&2
    exit 1
fi
venv_path="$setup_home/pyspark-env"

as_setup_user() {
    if [[ "$EUID" -eq 0 && "$setup_user" != root ]]; then
        runuser -u "$setup_user" -- env HOME="$setup_home" "$@"
    else
        "$@"
    fi
}

missing_packages=()
for package in python3 python3-pip python3-venv; do
    if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" != 'install ok installed' ]]; then
        missing_packages+=("$package")
    fi
done

if (( ${#missing_packages[@]} > 0 )); then
    echo "Installing missing Python packages..."
    if [[ "$EUID" -eq 0 ]]; then
        apt update
        apt install -y "${missing_packages[@]}"
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y "${missing_packages[@]}"
    else
        echo "Ask an administrator to install: ${missing_packages[*]}" >&2
        exit 1
    fi
fi

echo "Creating the PySpark environment for $setup_user..."
as_setup_user python3 -m venv "$venv_path"

echo "Installing PySpark..."
as_setup_user "$venv_path/bin/python" -m pip install --upgrade pip
as_setup_user "$venv_path/bin/python" -m pip install 'pyspark>=3.5,<3.6'

echo "Checking installed versions..."
as_setup_user "$venv_path/bin/python" --version
as_setup_user "$venv_path/bin/python" -c \
    "import pyspark; print('PySpark:', pyspark.__version__)"

echo
echo "Setup complete for $setup_user."
printf 'Activate the environment: source %q\n' "$venv_path/bin/activate"
echo "A compatible Java installation is required to run PySpark."
