#!/bin/bash

cd /tmp
wget -q https://dl.google.com/go/go1.10.1.linux-amd64.tar.gz
tar -xvzf go1.10.1.linux-amd64.tar.gz -C /usr/local
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
