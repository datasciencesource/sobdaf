#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

MYSQL_DB="dbtest"
MYSQL_USER="usertest"
MYSQL_PASSWORD="Admin1111"
PHPMYADMIN_PASSWORD="Admin1111"

export DEBIAN_FRONTEND=noninteractive

echo "Installing MySQL, Apache, and PHP..."
apt-get update
apt-get install -y \
    mysql-server apache2 php libapache2-mod-php \
    php-mysql php-mbstring php-xml php-curl php-zip \
    debconf-utils

systemctl enable --now mysql

# This script expects Ubuntu's default local root authentication.
if ! mysql --protocol=socket -u root -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Cannot connect as MySQL root using local socket authentication."
    echo "An existing root password or authentication change needs attention."
    exit 1
fi

echo "Creating the database, application user, and table..."
mysql --protocol=socket -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;

CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost'
    IDENTIFIED BY '${MYSQL_PASSWORD}';

ALTER USER '${MYSQL_USER}'@'localhost'
    IDENTIFIED BY '${MYSQL_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.*
    TO '${MYSQL_USER}'@'localhost';

USE \`${MYSQL_DB}\`;

CREATE TABLE IF NOT EXISTS table_stock (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT,
    purchasing_price FLOAT,
    quantity DOUBLE,
    stock_date DATETIME
);
SQL

echo "Configuring phpMyAdmin installation..."
debconf-set-selections <<DEBCONF
phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2
phpmyadmin phpmyadmin/dbconfig-install boolean true
phpmyadmin phpmyadmin/mysql/admin-user string root
phpmyadmin phpmyadmin/mysql/admin-pass password
phpmyadmin phpmyadmin/mysql/app-pass password ${PHPMYADMIN_PASSWORD}
phpmyadmin phpmyadmin/app-password-confirm password ${PHPMYADMIN_PASSWORD}
DEBCONF

apt-get install -y phpmyadmin

# Ensure the packaged Apache configuration is enabled.
if [[ ! -e /etc/apache2/conf-available/phpmyadmin.conf ]]; then
    ln -s /etc/phpmyadmin/apache.conf \
        /etc/apache2/conf-available/phpmyadmin.conf
fi

a2enconf phpmyadmin
apache2ctl configtest
systemctl enable --now apache2
systemctl restart apache2

echo "Verifying the database table..."
mysql --protocol=socket -u root \
    -e "SHOW TABLES FROM \`${MYSQL_DB}\` LIKE 'table_stock';"

echo
echo "Setup complete."
echo "phpMyAdmin: http://localhost/phpmyadmin"
echo "From another computer: http://SERVER_IP/phpmyadmin"
echo "Login user: ${MYSQL_USER}"
echo "Database: ${MYSQL_DB}"
echo "Use the MYSQL_PASSWORD configured in this script."
echo "MySQL administrator access: sudo mysql"
