#!/bin/bash
set -e

# Sqoop 1.4.7 installer for the existing Hadoop 2.10.2 environment
SQOOP_VERSION="1.4.7"
SQOOP_ARCHIVE="sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0.tar.gz"
SQOOP_URL="https://archive.apache.org/dist/sqoop/${SQOOP_VERSION}/${SQOOP_ARCHIVE}"

HADOOP_HOME="/usr/local/hadoop"
SQOOP_HOME="/usr/local/sqoop"
MYSQL_CONNECTOR_SOURCE="/opt/nifi/mysql-connector-j-8.4.0/mysql-connector-j-8.4.0.jar"

echo "Installing Apache Sqoop ${SQOOP_VERSION}..."

# Check the existing Hadoop installation
if [ ! -d "${HADOOP_HOME}" ]; then
    echo "Error: Hadoop was not found at ${HADOOP_HOME}."
    echo "Run the Hadoop installation script first."
    exit 1
fi

sudo apt-get update -y
sudo apt-get install -y wget tar

cd /opt || exit 1

# Download Sqoop from the official Apache archive
sudo rm -f "${SQOOP_ARCHIVE}"
sudo wget -O "${SQOOP_ARCHIVE}" "${SQOOP_URL}"

# Remove an earlier Sqoop installation, if present
sudo rm -rf "/opt/sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0"
sudo rm -rf "${SQOOP_HOME}"

# Extract and install
sudo tar -xzf "${SQOOP_ARCHIVE}"
sudo mv "/opt/sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0" "${SQOOP_HOME}"
sudo rm -f "${SQOOP_ARCHIVE}"

# Detect Java 11 already installed by the Hadoop script
JAVA_HOME_PATH=$(ls -d /usr/lib/jvm/java-11-openjdk-* 2>/dev/null | head -n 1)

if [ -z "${JAVA_HOME_PATH}" ]; then
    echo "Error: Java 11 was not found."
    exit 1
fi

# Configure Sqoop
sudo cp "${SQOOP_HOME}/conf/sqoop-env-template.sh" \
        "${SQOOP_HOME}/conf/sqoop-env.sh"

sudo tee "${SQOOP_HOME}/conf/sqoop-env.sh" > /dev/null <<EOF
export JAVA_HOME=${JAVA_HOME_PATH}
export HADOOP_COMMON_HOME=${HADOOP_HOME}
export HADOOP_MAPRED_HOME=${HADOOP_HOME}
export HADOOP_HDFS_HOME=${HADOOP_HOME}
export YARN_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
EOF

# Copy the MySQL JDBC driver already installed for NiFi
if [ -f "${MYSQL_CONNECTOR_SOURCE}" ]; then
    sudo cp "${MYSQL_CONNECTOR_SOURCE}" "${SQOOP_HOME}/lib/"
    sudo chmod 644 "${SQOOP_HOME}/lib/mysql-connector-j-8.4.0.jar"
else
    echo "MySQL Connector/J was not found in the NiFi directory."
    echo "Downloading MySQL Connector/J 8.4.0..."

    cd /opt || exit 1
    sudo wget -O mysql-connector-j-8.4.0.tar.gz \
      https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-8.4.0.tar.gz
    sudo tar -xzf mysql-connector-j-8.4.0.tar.gz
    sudo cp mysql-connector-j-8.4.0/mysql-connector-j-8.4.0.jar \
      "${SQOOP_HOME}/lib/"
    sudo rm -rf mysql-connector-j-8.4.0 mysql-connector-j-8.4.0.tar.gz
fi

# Add persistent environment variables
sed -i '/# SQOOP_ENV_START/,/# SQOOP_ENV_END/d' "$HOME/.bashrc"

cat <<EOF >> "$HOME/.bashrc"

# SQOOP_ENV_START
export SQOOP_HOME=${SQOOP_HOME}
export PATH=\$PATH:\$SQOOP_HOME/bin
export HADOOP_COMMON_HOME=${HADOOP_HOME}
export HADOOP_MAPRED_HOME=${HADOOP_HOME}
export HADOOP_HDFS_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
# SQOOP_ENV_END
EOF

sudo tee /etc/profile.d/sqoop.sh > /dev/null <<EOF
export SQOOP_HOME=${SQOOP_HOME}
export PATH=\$PATH:\$SQOOP_HOME/bin
export HADOOP_COMMON_HOME=${HADOOP_HOME}
export HADOOP_MAPRED_HOME=${HADOOP_HOME}
export HADOOP_HDFS_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
EOF

sudo chmod +x /etc/profile.d/sqoop.sh

# Create a command wrapper so Sqoop works without running source ~/.bashrc
sudo tee /usr/local/bin/sqoop > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=${JAVA_HOME_PATH}
export SQOOP_HOME=${SQOOP_HOME}
export HADOOP_COMMON_HOME=${HADOOP_HOME}
export HADOOP_MAPRED_HOME=${HADOOP_HOME}
export HADOOP_HDFS_HOME=${HADOOP_HOME}
export YARN_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export PATH=${SQOOP_HOME}/bin:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:\$PATH
exec ${SQOOP_HOME}/bin/sqoop "\$@"
EOF

sudo chmod +x /usr/local/bin/sqoop
sudo chown -R root:root "${SQOOP_HOME}"
sudo chmod -R 755 "${SQOOP_HOME}"

echo ""
echo "Sqoop installation completed."
echo ""
sqoop version

