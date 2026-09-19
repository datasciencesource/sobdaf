#!/bin/bash

sudo apt-get update -y
sudo apt install openjdk-11-jdk openssh-server wget -y

JAVA_HOME_PATH=$(ls -d /usr/lib/jvm/java-11-openjdk-* 2>/dev/null | head -n 1)

echo "JAVA_HOME=\"$JAVA_HOME_PATH\"" | sudo tee /etc/environment

export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export PATH=$PATH:$HADOOP_INSTALL/bin:$HADOOP_INSTALL/sbin
export HADOOP_MAPRED_HOME=$HADOOP_INSTALL
export HADOOP_COMMON_HOME=$HADOOP_INSTALL
export HADOOP_HDFS_HOME=$HADOOP_INSTALL
export YARN_HOME=$HADOOP_INSTALL
export HADOOP_COMMON_LIB_NATIVE_DIR=$HADOOP_INSTALL/lib/native
export HADOOP_OPTS="-Djava.library.path=$HADOOP_INSTALL/lib"
export HADOOP_PREFIX=$HADOOP_INSTALL
export HADOOP_CONF_DIR=$HADOOP_PREFIX/etc/hadoop
export SSH_OPTS="-o StrictHostKeyChecking=no"

if [ ! -f "$HOME/.ssh/id_rsa" ]; then
  yes "" | ssh-keygen -t rsa -P ""
fi

cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys"
ssh-keyscan -H localhost >> "$HOME/.ssh/known_hosts"
ssh-keyscan -H 0.0.0.0 >> "$HOME/.ssh/known_hosts"

sudo systemctl restart ssh

cd /opt || exit

sudo wget -O hadoop-2.10.2.tar.gz https://archive.apache.org/dist/hadoop/common/hadoop-2.10.2/hadoop-2.10.2.tar.gz

sudo tar -zxvf hadoop-2.10.2.tar.gz
sudo rm -rf hadoop-2.10.2.tar.gz

sudo rm -rf /usr/local/hadoop
sudo mkdir -p /usr/local/hadoop
sudo mv hadoop-2.10.2/* /usr/local/hadoop/
sudo rm -rf hadoop-2.10.2

sed -i '/# HADOOP_ENV_START/,/# HADOOP_ENV_END/d' ~/.bashrc

cat <<EOF >> ~/.bashrc

# HADOOP_ENV_START
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export PATH=\$PATH:\$HADOOP_INSTALL/bin:\$HADOOP_INSTALL/sbin
export HADOOP_MAPRED_HOME=\$HADOOP_INSTALL
export HADOOP_COMMON_HOME=\$HADOOP_INSTALL
export HADOOP_HDFS_HOME=\$HADOOP_INSTALL
export YARN_HOME=\$HADOOP_INSTALL
export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_INSTALL/lib/native
export HADOOP_OPTS="-Djava.library.path=\$HADOOP_INSTALL/lib"
export HADOOP_PREFIX=\$HADOOP_INSTALL
export HADOOP_CONF_DIR=\$HADOOP_PREFIX/etc/hadoop
# HADOOP_ENV_END
EOF

sudo tee /etc/profile.d/hadoop.sh > /dev/null <<EOF
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export PATH=\$PATH:\$HADOOP_INSTALL/bin:\$HADOOP_INSTALL/sbin
export HADOOP_MAPRED_HOME=\$HADOOP_INSTALL
export HADOOP_COMMON_HOME=\$HADOOP_INSTALL
export HADOOP_HDFS_HOME=\$HADOOP_INSTALL
export YARN_HOME=\$HADOOP_INSTALL
export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_INSTALL/lib/native
export HADOOP_OPTS="-Djava.library.path=\$HADOOP_INSTALL/lib"
export HADOOP_PREFIX=\$HADOOP_INSTALL
export HADOOP_CONF_DIR=\$HADOOP_PREFIX/etc/hadoop
EOF

sudo chmod +x /etc/profile.d/hadoop.sh

sudo rm -f /usr/local/bin/hadoop
sudo rm -f /usr/local/bin/hdfs
sudo rm -f /usr/local/bin/yarn
sudo rm -f /usr/local/bin/start-all.sh
sudo rm -f /usr/local/bin/stop-all.sh
sudo rm -f /usr/local/bin/start-dfs.sh
sudo rm -f /usr/local/bin/stop-dfs.sh
sudo rm -f /usr/local/bin/start-yarn.sh
sudo rm -f /usr/local/bin/stop-yarn.sh

sudo tee /usr/local/bin/hadoop > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/bin/hadoop "\$@"
EOF

sudo tee /usr/local/bin/hdfs > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/bin/hdfs "\$@"
EOF

sudo tee /usr/local/bin/yarn > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/bin/yarn "\$@"
EOF

sudo tee /usr/local/bin/start-all.sh > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/sbin/start-all.sh "\$@"
EOF

sudo tee /usr/local/bin/stop-all.sh > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/sbin/stop-all.sh "\$@"
EOF

sudo tee /usr/local/bin/start-dfs.sh > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/sbin/start-dfs.sh "\$@"
EOF

sudo tee /usr/local/bin/stop-dfs.sh > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/sbin/stop-dfs.sh "\$@"
EOF

sudo tee /usr/local/bin/start-yarn.sh > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/sbin/start-yarn.sh "\$@"
EOF

sudo tee /usr/local/bin/stop-yarn.sh > /dev/null <<EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_INSTALL=/usr/local/hadoop
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_PREFIX=/usr/local/hadoop
export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
export HADOOP_MAPRED_HOME=/usr/local/hadoop
export HADOOP_COMMON_HOME=/usr/local/hadoop
export HADOOP_HDFS_HOME=/usr/local/hadoop
export YARN_HOME=/usr/local/hadoop
export PATH=/usr/local/hadoop/bin:/usr/local/hadoop/sbin:\$PATH
exec /usr/local/hadoop/sbin/stop-yarn.sh "\$@"
EOF

sudo chmod +x /usr/local/bin/hadoop
sudo chmod +x /usr/local/bin/hdfs
sudo chmod +x /usr/local/bin/yarn
sudo chmod +x /usr/local/bin/start-all.sh
sudo chmod +x /usr/local/bin/stop-all.sh
sudo chmod +x /usr/local/bin/start-dfs.sh
sudo chmod +x /usr/local/bin/stop-dfs.sh
sudo chmod +x /usr/local/bin/start-yarn.sh
sudo chmod +x /usr/local/bin/stop-yarn.sh

sudo mkdir -p /usr/local/hadoop_store/hdfs/namenode
sudo mkdir -p /usr/local/hadoop_store/hdfs/datanode
sudo mkdir -p /app/hadoop/tmp

sudo tee /usr/local/hadoop/etc/hadoop/hadoop-env.sh > /dev/null <<EOF
export JAVA_HOME=$JAVA_HOME_PATH
EOF

sudo tee /usr/local/hadoop/etc/hadoop/hdfs-site.xml > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property>
<name>dfs.replication</name>
<value>1</value>
</property>
<property>
<name>dfs.permissions</name>
<value>false</value>
</property>
<property>
<name>dfs.namenode.name.dir</name>
<value>file:/usr/local/hadoop_store/hdfs/namenode</value>
</property>
<property>
<name>dfs.datanode.data.dir</name>
<value>file:/usr/local/hadoop_store/hdfs/datanode</value>
</property>
</configuration>
EOF

sudo tee /usr/local/hadoop/etc/hadoop/core-site.xml > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property>
<name>hadoop.tmp.dir</name>
<value>/app/hadoop/tmp</value>
</property>
<property>
<name>fs.defaultFS</name>
<value>hdfs://localhost:54310</value>
</property>
</configuration>
EOF

sudo cp /usr/local/hadoop/etc/hadoop/mapred-site.xml.template /usr/local/hadoop/etc/hadoop/mapred-site.xml

sudo tee /usr/local/hadoop/etc/hadoop/mapred-site.xml > /dev/null <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property>
<name>mapreduce.framework.name</name>
<value>yarn</value>
</property>
</configuration>
EOF

sudo tee /usr/local/hadoop/etc/hadoop/yarn-site.xml > /dev/null <<EOF
<?xml version="1.0"?>
<configuration>
<property>
<name>yarn.nodemanager.aux-services</name>
<value>mapreduce_shuffle</value>
</property>
<property>
<name>yarn.nodemanager.auxservices.mapreduce.shuffle.class</name>
<value>org.apache.hadoop.mapred.ShuffleHandler</value>
</property>
</configuration>
EOF

hadoop namenode -format -force

start-all.sh

jps
hadoop version

echo ""
echo "Hadoop installation completed."
echo "You do NOT need to run source ~/.bashrc."
echo ""
echo "Test commands:"
echo "hadoop version"
echo "hdfs dfs -ls /"
echo "start-all.sh"
echo "stop-all.sh"
