#!/bin/bash

# Installation can take time.
# You can tail -F /var/log/nuxeo_install.log to see basic install progress
# You can tail -F /var/log/syslog to see the full startup and check for errors

# Instance Metadata

STACK_ID=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/stack-name -H "Metadata-Flavor: Google")
DNS_NAME=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/stack-name -H "Metadata-Flavor: Google")

# Variables for installation
INSTALL_LOG="/var/log/nuxeo_install.log"

COMPOSE_REPO="https://github.com/nuxeo-sandbox/nuxeo-presales-docker"
COMPOSE_DIR="/home/ubuntu/nuxeo-presales-docker"
CONF_DIR="${COMPOSE_DIR}/conf"

NUXEO_ENV="${COMPOSE_DIR}/.env"

STUDIO_USERNAME="nuxeo_presales"

TEMPLATES="default,mongodb"

MONGO_VERSION="6.0"

OPENSEARCH_VERSION="1.3.17"
OPENSEARCH_IMAGE="opensearchproject/opensearch:"${OPENSEARCH_VERSION}
OPENSEARCH_DASHBOARDS_IMAGE="opensearchproject/opensearch-dashboards:"${OPENSEARCH_VERSION}

LTS_IMAGE="docker-private.packages.nuxeo.com/nuxeo/nuxeo:2023"

TMP_DIR="/tmp/nuxeo"

# Start of installation script

echo "Nuxeo Presales Installation Script Starting [${STACK_ID}]" > ${INSTALL_LOG}

# set memory settings
# https://opensearch.org/docs/1.3/install-and-configure/install-opensearch/index/#important-settings
# https://www.mongodb.com/docs/manual/administration/production-checklist-operations/#linux
echo "vm.max_map_count=262144" >> /etc/sysctl.conf && sysctl -p

# Check configured image
FROM_IMAGE="${LTS_IMAGE}"

# Check DNS Name
if [ -z "${DNS_NAME}" ]; then
  DNS_NAME=${STACK_ID}
  echo "Warning: DNS Name is not set, using stack id: ${STACK_ID}" | tee -a ${INSTALL_LOG}
fi

# Fully qualified domain name
FQDN="${DNS_NAME}.gcp.cloud.nuxeo.com"

# TEMP: Install uuid
apt-get -q -y install uuid

# Set the hostname & domain
echo "${DNS_NAME}" > /etc/hostname
hostname ${DNS_NAME}
echo "Domains=gcp.cloud.nuxeo.com" >> /etc/systemd/resolved.conf

# Install Nuxeo
echo "Nuxeo Presales Installation Script: Install Nuxeo" | tee -a ${INSTALL_LOG}

# Make directories and clone compose stack
mkdir -p ${COMPOSE_DIR} ${NUXEO_DATA_DIR} ${NUXEO_LOG_DIR} ${TMP_DIR}
git clone ${COMPOSE_REPO} ${COMPOSE_DIR}
mkdir -p ${CONF_DIR}
echo "Nuxeo Presales Installation Script: Install Nuxeo => DONE" | tee -a ${INSTALL_LOG}

