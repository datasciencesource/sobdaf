#!/bin/bash
source ~/.bashrc
apt update -y
apt install unzip wget -y

cd /opt

rm -rf nifi nifi-1.28.1 nifi-1.28.1-bin.zip

wget https://archive.apache.org/dist/nifi/1.28.1/nifi-1.28.1-bin.zip

unzip nifi-1.28.1-bin.zip

mv nifi-1.28.1 nifi

chmod -R 755 /opt/nifi

cd /opt/nifi

./bin/nifi.sh set-single-user-credentials admin Admin123456789

source ~/.bashrc

./bin/nifi.sh start

./bin/nifi.sh status
