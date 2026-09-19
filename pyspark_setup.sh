#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Run this script as your normal user, without sudo."
    exit 1
fi

 echo "Installing Python..."
sudo apt update
sudo apt install -y python3 python3-pip python3-venv

echo "Creating the PySpark virtual environment..."
python3 -m venv "$HOME/pyspark-env"

echo "Installing PySpark..."
"$HOME/pyspark-env/bin/python" -m pip install --upgrade pip
"$HOME/pyspark-env/bin/python" -m pip install "pyspark>=3.5,<3.6"

echo "Checking installed versions..."
"$HOME/pyspark-env/bin/python" --version
"$HOME/pyspark-env/bin/python" -c \
    "import pyspark; print('PySpark:', pyspark.__version__)"

echo
echo "Setup complete."
