#!/bin/bash

add-apt-repository universe
add-apt-repository multiverse

# Increase open files limit
echo '*       soft    nofile      4096' >> /etc/security/limits.conf
echo '*       hard    nofile      8192' >> /etc/security/limits.conf

# Create nuxeo user - UID 900 comes from the docker image
groupadd -g 900 nuxeo
useradd -m -g 900 -G ubuntu -u 900 nuxeo

# Upgrade packages and install apache, ssh, ...
export DEBIAN_FRONTEND=noninteractive
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
apt-get update
apt-get -q -y upgrade
apt-get -q -y install apache2 apt-transport-https openssh-server openssh-client vim jq git \
                      ca-certificates curl software-properties-common figlet \
                      atop htop make uuid

#Additional modules and config for apache                      
a2enmod proxy proxy_http rewrite ssl headers
systemctl restart apache2
echo "Please wait a few minutes for you instance installation to complete" > /var/www/html/index.html

# Install latest aws cli using snap
snap install aws-cli --classic

# Install docker
# Add Docker's official GPG key:
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get -q -y update
apt-get -q -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu

# Install Certbot
snap install core; snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

apt-get -y clean
