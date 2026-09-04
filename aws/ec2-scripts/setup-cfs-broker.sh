#!/bin/bash

# Runs on first boot of a CFS Broker instance (launched via aws/cf-templates/CFS-Broker.template).
#
# This script only prepares the HOST so it is ready to run the Hyland Content
# Federation Services (CFS) broker OCI container. It deliberately does NOT:
#   - download the broker image (that is a manual tarball from Hyland Community), or
#   - enter CIC credentials, or
#   - start the container.
# Those steps are done by hand for now (see "NEXT STEPS" printed at the end).
#
# Progress is logged to /var/log/cfs_broker_install.log
# Environment variables are passed via the CloudFormation template UserData.

source /etc/profile.d/load_env.sh

INSTALL_LOG="/var/log/cfs_broker_install.log"
LOG_PREFIX="CFS Broker Setup:"
BROKER_DIR="/home/ubuntu/cfs-broker"

echo "${LOG_PREFIX} Starting [${STACK_ID}]" > ${INSTALL_LOG}

# Check DNS Name
if [ -z "${DNS_NAME}" ]; then
  DNS_NAME=${STACK_ID}
  echo "${LOG_PREFIX} Warning: DNS Name is not set, using stack id: ${STACK_ID}" | tee -a ${INSTALL_LOG}
fi

# Set the hostname & domain (consistency with the Nuxeo demo hosts; the broker
# only makes outbound calls, so no public FQDN/cert is required).
FQDN="${DNS_NAME}.cloud.nuxeo.com"
echo "${DNS_NAME}" > /etc/hostname
hostname ${DNS_NAME}
echo "Domains=cloud.nuxeo.com" >> /etc/systemd/resolved.conf

# --- Enable the containerd image store (snapshotter) ---
# Docker + containerd.io are baked into the presales AMI, but the broker OCI
# image requires Docker to use the containerd snapshotter, which is NOT the
# default. Enable it and restart the engine.
echo "${LOG_PREFIX} Enabling containerd snapshotter" | tee -a ${INSTALL_LOG}
mkdir -p /etc/docker
if [ -f /etc/docker/daemon.json ]; then
  TMP_DAEMON=$(mktemp)
  jq '.features."containerd-snapshotter" = true' /etc/docker/daemon.json > "${TMP_DAEMON}" \
    && mv "${TMP_DAEMON}" /etc/docker/daemon.json
else
  echo '{ "features": { "containerd-snapshotter": true } }' > /etc/docker/daemon.json
fi
systemctl restart docker
echo "${LOG_PREFIX} containerd snapshotter enabled => DONE" | tee -a ${INSTALL_LOG}

# --- Create the broker working directory and persistent volume mounts ---
# Mount points follow the Hyland "Container Mount Points" table.
echo "${LOG_PREFIX} Creating broker directory structure at ${BROKER_DIR}" | tee -a ${INSTALL_LOG}
mkdir -p \
  ${BROKER_DIR}/keys/data-protection \
  ${BROKER_DIR}/logs \
  ${BROKER_DIR}/certificates \
  ${BROKER_DIR}/plugins/nuxeo \
  ${BROKER_DIR}/keyperfile

# --- Lay down compose + env skeletons (quoted heredocs keep ${...} literal) ---
cat << 'EOF' > ${BROKER_DIR}/docker-compose.yml
services:
  hyland.contentfederation.broker:
    # Set BROKER_IMAGE in .env to the sha256 id printed by
    #   docker load -i <broker-oci-image.tar.gz>
    # (run `docker images --no-trunc` to read it back), or a registry ref if you
    # later stage the image in ECR/S3.
    image: ${BROKER_IMAGE}
    container_name: cfs-broker
    restart: unless-stopped
    env_file:
      - .env
EOF

cat << 'EOF' > ${BROKER_DIR}/docker-compose.override.yml
services:
  hyland.contentfederation.broker:
    volumes:
      - ${BROKER_KEYS_HOST_PATH:-./keys}:/app/keys:rw
      - ${BROKER_DATAPROTECTIONKEYS_HOST_PATH:-./keys/data-protection}:/app/keys/data-protection:rw
      - ${BROKER_LOGS_HOST_PATH:-./logs}:/app/logs:rw
      - ${NUXEO_PLUGIN_HOST_PATH:-./plugins/nuxeo}:/app/plugins/nuxeo:ro
      - ${CERTIFICATE_MOUNT_HOST_DIR_PATH:-./certificates}:/app/certificates:ro
      - ${BROKER_KEYPERFILE_DIR_PATH:-./keyperfile}:/run/secrets:rw
EOF

# CIC_REGION and BROKER_NAME are prefilled from the template; everything else is
# filled in by hand. Unquoted heredoc so those two variables expand.
cat << EOF > ${BROKER_DIR}/.env
# ---- Image ----
# After: docker load -i <broker-oci-image.tar.gz>
# then:  docker images --no-trunc   (copy the sha256:... id)
BROKER_IMAGE=

# ---- Host volume paths (created by setup-cfs-broker.sh; relative to this dir) ----
BROKER_KEYS_HOST_PATH=./keys
BROKER_DATAPROTECTIONKEYS_HOST_PATH=./keys/data-protection
BROKER_LOGS_HOST_PATH=./logs
NUXEO_PLUGIN_HOST_PATH=./plugins/nuxeo
CERTIFICATE_MOUNT_HOST_DIR_PATH=./certificates
BROKER_KEYPERFILE_DIR_PATH=./keyperfile

# ---- CF Broker -> CIC (GatewayConfiguration) ----
FCC_CFBROKER_GatewayConfiguration__Region=${CIC_REGION}
FCC_CFBROKER_GatewayConfiguration__BrokerName=${BROKER_NAME}
FCC_CFBROKER_GatewayConfiguration__ProtectedKeyFilePath=/app/keys/keys.json
# From the CFS external application you register in the SA CIC environment
# ("Registering the CF Broker in the Content Innovation Cloud"):
FCC_CFBROKER_GatewayConfiguration__Credentials__ClientId=
FCC_CFBROKER_GatewayConfiguration__Credentials__ClientSecret=

# ---- Nuxeo CF Plugin (index 0) ----
# NOTE: verify the exact plugin env var names / {PluginEnvPrefix} against the
# "Configuration Values" page for your broker version before relying on these.
FCC_CFBROKER_PluginConfiguration__Plugins__0__PluginId=nuxeo
FCC_CFBROKER_PluginConfiguration__Plugins__0__PluginPath=/app/plugins/nuxeo
# Integration ID from the CIC Admin Portal "System Integration" for this Nuxeo instance:
PluginConfiguration__0__IntegrationId=
# e.g. https://<demo>.cloud.nuxeo.com/nuxeo/api/v1
PluginConfiguration__0__NuxeoServerApiUrl=
PluginConfiguration__0__IdentityProviderOptions__ClientId=
PluginConfiguration__0__IdentityProviderOptions__ClientSecret=
PluginConfiguration__0__IdentityProviderOptions__JwtSecretSigningKey=
EOF

chown -R ubuntu:ubuntu ${BROKER_DIR}
echo "${LOG_PREFIX} Broker directory ready => DONE" | tee -a ${INSTALL_LOG}

cat << EOF | tee -a ${INSTALL_LOG}
${LOG_PREFIX} HOST PREP COMPLETE.

NEXT STEPS (manual, run as the 'ubuntu' user):
  1. Copy the CF Broker OCI image tarball (from Hyland Community) to ${BROKER_DIR}
     from your laptop using nxpssh.sh.
  2. cd ${BROKER_DIR} && docker load -i <broker-oci-image.tar.gz>
  3. docker images --no-trunc   # copy the sha256:... id
  4. Edit ${BROKER_DIR}/.env :
       - set BROKER_IMAGE to the sha256 id
       - set the CIC ClientId / ClientSecret (dedicated CFS test service user)
       - set the Nuxeo plugin IntegrationId / NuxeoServerApiUrl / IdP options
  5. Drop the Nuxeo CF Plugin files into ${BROKER_DIR}/plugins/nuxeo
  6. docker compose up -d   (then: docker compose logs -f)
EOF
