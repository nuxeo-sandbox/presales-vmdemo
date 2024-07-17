#!/bin/bash

# Installation can take time.
# You can tail -F /var/log/nuxeo_install.log to see basic install progress
# You can tail -F /var/log/syslog to see the full startup and check for errors
INSTALL_LOG="/var/log/nuxeo_install.log"
INSTALL_LOG_PREFIX="NXP Install Script:"

# In GCP the `startup-script` runs every time the instance starts; we only want
# it to run the first time, so we set a "flag" to stop subsequent executions
MARKER_FILE="/var/log/first-run-done"
if [ -f "$MARKER_FILE" ]; then
  exit 1
fi

# Instance Metadata
STACK_ID=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/stack-name -H "Metadata-Flavor: Google")
DNS_NAME=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/stack-name -H "Metadata-Flavor: Google")

# Variables for installation
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

echo "${INSTALL_LOG_PREFIX} Starting [${STACK_ID}]" > ${INSTALL_LOG}

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
echo "${INSTALL_LOG_PREFIX} Install Nuxeo" | tee -a ${INSTALL_LOG}

# Make directories and clone compose stack
mkdir -p ${COMPOSE_DIR} ${NUXEO_DATA_DIR} ${NUXEO_LOG_DIR} ${TMP_DIR}
git clone ${COMPOSE_REPO} ${COMPOSE_DIR}
mkdir -p ${CONF_DIR}
echo "${INSTALL_LOG_PREFIX} Install Nuxeo => DONE" | tee -a ${INSTALL_LOG}

echo "${INSTALL_LOG_PREFIX} Configure Nuxeo" | tee -a ${INSTALL_LOG}

# Copy default conf.d files
cp ${COMPOSE_DIR}/conf.d/* ${CONF_DIR}

BUCKET="nuxeo-demo-shared-bucket-us"
BUCKET_PREFIX="/${STACK_ID}/"

# Make sure we always have a UI installed
AUTO_PACKAGES="nuxeo-web-ui gcp-storage platform-explorer"

# Write system configuration

# This is required for WOPI
JWT_SECRET=`uuid`

cat << EOF > ${CONF_DIR}/system.conf
# Host Configuration
session.timeout=600
nuxeo.url=https://${FQDN}/nuxeo

# Templates
nuxeo.append.templates.system=${TEMPLATES}

# CORS Configuration (used with AI, Salesforce, others)
#nuxeo.cors.urls=
#nuxeo.server.coookies.sameSite=none

# Webui
nuxeo.selection.selectAllEnabled=true
nuxeo.analytics.documentDistribution.disableThreshold=10000

# Mail Configuration
mail.transport.password=${MAIL_PASS}
mail.transport.host=smtp.mail.us-east-1.awsapps.com
mail.transport.port=465
mail.transport.user=no-reply@nuxeo-demo.awsapps.com
mail.transport.auth=true
mail.from=no-reply@nuxeo-demo.awsapps.com
mail.smtp.ssl.enable=true
mail.transport.protocol=smtps
mail.transport.ssl.protocol=TLSv1.2
nuxeo.notification.eMailSubjectPrefix=[Nuxeo]

# BLOB Configuration
nuxeo.gcp.storage.bucket=${BUCKET}
nuxeo.gcp.storage.bucket_prefix=${BUCKET_PREFIX}
nuxeo.gcp.project=nuxeo-presales-apis

# WOPI Configuration
nuxeo.wopi.discoveryURL=https://onenote.officeapps.live.com/hosting/discovery
nuxeo.wopi.baseURL=https://wopi.nuxeocloud.com/${FQDN}/nuxeo/
# JWT token is required for WOPI
nuxeo.jwt.secret=${JWT_SECRET}

EOF

# Register the nuxeo instance
echo "$(date) Configure Studio Project [${NX_STUDIO}]" | tee -a ${INSTALL_LOG}

# Home required by 'docker'
export HOME="/home/ubuntu"

# Get credentials for Studio & Repository
gcloud secrets versions access latest --secret nuxeo-presales-connect --project nuxeo-presales-apis > /root/creds.json

# Log in to docker
DOCKER_USER=$(jq -r '.docker_presales_user' < /root/creds.json)
DOCKER_PASS=$(jq -r '.docker_presales_pwd' < /root/creds.json)
echo ${DOCKER_PASS} | docker login -u ${DOCKER_USER} --password-stdin docker-private.packages.nuxeo.com 2>&1 | tee -a ${INSTALL_LOG}

STUDIO_PACKAGE=""
if [ -z "${NX_STUDIO_VER}" ]; then
  NX_STUDIO_VER="0.0.0-SNAPSHOT"
fi
if [ -n "${NX_STUDIO}" ]; then
  STUDIO_PACKAGE="${NX_STUDIO}-${NX_STUDIO_VER}"
fi
PROJECT_NAME=$(echo "${NX_STUDIO}" | awk '{print tolower($0)}')

# Set working environment
CREDENTIALS=$(jq -r '.connect_presales_pwd' < /root/creds.json)
cat << EOF > ${NUXEO_ENV}
APPLICATION_NAME=${NX_STUDIO}
PROJECT_NAME=${PROJECT_NAME}

NUXEO_IMAGE=${FROM_IMAGE}

JAVA_OPTS=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:8787

CONNECT_URL=https://connect.nuxeo.com/nuxeo/site/

NUXEO_DEV=true
NUXEO_PORT=8080
NUXEO_PACKAGES=${STUDIO_PACKAGE} ${AUTO_PACKAGES} ${NUXEO_PACKAGES}

INSTALL_RPM=${INSTALL_RPM}

MONGO_VERSION=${MONGO_VERSION}
OPENSEARCH_IMAGE=${OPENSEARCH_IMAGE}
OPENSEARCH_DASHBOARDS_IMAGE=${OPENSEARCH_DASHBOARDS_IMAGE}

FQDN=${FQDN}
STUDIO_USERNAME=${STUDIO_USERNAME}
STUDIO_CREDENTIALS=${CREDENTIALS}
EOF
# Make env not as hidden
ln -s ${NUXEO_ENV} ${COMPOSE_DIR}/env

# Fix up permissions
rm -f /root/creds.json
chown -R nuxeo:ubuntu ${TMP_DIR}
chown -R ubuntu:ubuntu ${COMPOSE_DIR} ${HOME}/.docker

# Use the source image to register the project
docker pull --quiet ${FROM_IMAGE} 2>&1 | tee -a ${INSTALL_LOG}

# Auto-start if Studio project defined
if [ -n "${NX_STUDIO}" ]; then
  echo "Registering Nuxeo..." | tee -a ${INSTALL_LOG}
  sh -c "cd ${COMPOSE_DIR} && ./generate_clid.sh"

  # Build / Pull images
  echo "Pulling other images..." | tee -a ${INSTALL_LOG}
  docker compose --project-directory ${COMPOSE_DIR} --no-ansi pull | tee -a ${INSTALL_LOG}

  if [[ "${AUTO_START}" == "true" ]]; then
    echo "Building images..." | tee -a ${INSTALL_LOG}
    docker compose --project-directory ${COMPOSE_DIR} --no-ansi build --progress plain 2>&1 | tee -a ${INSTALL_LOG}

    echo "Starting Nuxeo stack" | tee -a ${INSTALL_LOG}
    docker compose --project-directory ${COMPOSE_DIR} --no-ansi up --detach --no-color 2>&1 | tee -a ${INSTALL_LOG}
  fi

  # Fix up permissions
  chown -R ubuntu:ubuntu ${HOME}/.docker

fi
echo "${INSTALL_LOG_PREFIX} Configure Nuxeo => DONE" | tee -a ${INSTALL_LOG}

echo "${INSTALL_LOG_PREFIX} Install Misc." | tee -a ${INSTALL_LOG}
# Update some defaults
update-alternatives --set editor /usr/bin/vim.basic
echo "${INSTALL_LOG_PREFIX} Install Misc. => DONE" | tee -a ${INSTALL_LOG}

# Configure reverse-proxy
cat << EOF > /etc/apache2/sites-available/nuxeo.conf
<VirtualHost _default_:80>
    ServerName  ${FQDN}
    CustomLog /var/log/apache2/nuxeo_access.log combined
    ErrorLog /var/log/apache2/nuxeo_error.log
    Redirect permanent / https://${FQDN}/
</VirtualHost>

<VirtualHost _default_:443 >

    ServerName  ${FQDN}

    CustomLog /var/log/apache2/nuxeo_access.log combined
    ErrorLog /var/log/apache2/nuxeo_error.log

    DocumentRoot /var/www

    ProxyRequests   Off
     <Proxy * >
        Order allow,deny
        Allow from all
     </Proxy>

    <Location /dashboards>
      AuthUserFile /etc/apache2/passwords
      AuthName authorization
      AuthType Basic
      require valid-user
    </Location>

    RewriteEngine   On
    RewriteRule ^/$ /nuxeo/ [R,L]
    RewriteRule ^/nuxeo$ /nuxeo/ [R,L]
    RewriteRule ^/dashboards$ /dashboards/ [R,L]

    ProxyPass           /nuxeo/         http://localhost:8080/nuxeo/
    ProxyPass           /dashboards/        http://localhost:5601/dashboards/
    ProxyPassReverse    /nuxeo/         http://localhost:8080/nuxeo/
    ProxyPassReverse    /dashboards/        http://localhost:5601/dashboards/
    ProxyPreserveHost   On

    # WSS
    ProxyPass         /_vti_bin/     http://localhost:8080/_vti_bin/
    ProxyPass         /_vti_inf.html http://localhost:8080/_vti_inf.html
    ProxyPassReverse  /_vti_bin/     http://localhost:8080/_vti_bin/
    ProxyPassReverse  /_vti_inf.html http://localhost:8080/_vti_inf.html

    RequestHeader   append nuxeo-virtual-host "https://${FQDN}/"

    # Retain TLS1.1 for backwards compatibility until Jan 2020
    # These must be *after* the Certbot entry
    #XXX SSLProtocol all -SSLv2 -SSLv3 -TLSv1
    # SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    # Enable high ciphers for 3rd party security scanners
    #XXX SSLCipherSuite HIGH:!aNULL:!MD5:!3DES

    ## BEGIN SUPINT-655 ##
    <Location "/nuxeo/incl">
      RewriteRule .* - [R=404,L,NC]
    </Location>
    ## END SUPINT-655 ##

    Header edit Set-Cookie ^(.*)$ \$1;SameSite=None;Secure

</VirtualHost>
EOF

# Add gzip compression for the REST API
cat > /etc/apache2/mods-available/deflate.conf <<EOF
<IfModule mod_deflate.c>
        <IfModule mod_filter.c>
                # these are known to be safe with MSIE 6
                AddOutputFilterByType DEFLATE text/html text/plain text/xml

                # everything else may cause problems with MSIE 6
                AddOutputFilterByType DEFLATE text/css
                AddOutputFilterByType DEFLATE application/x-javascript application/javascript application/ecmascript
                AddOutputFilterByType DEFLATE application/rss+xml
                AddOutputFilterByType DEFLATE application/xml
                AddOutputFilterByType DEFLATE application/json
        </IfModule>
</IfModule>
EOF

a2enmod proxy proxy_http rewrite ssl headers
a2dissite 000-default
a2ensite nuxeo

#KIBANA_PASS=$(aws secretsmanager get-secret-value --secret-id kibana_default_password --region us-west-2 | jq -r '.SecretString|fromjson|.kibana_default_password')
#htpasswd -b -c /etc/apache2/passwords kibana "${KIBANA_PASS}"
#apache2ctl -k graceful

# Restart apache
echo "Restarting Apache"
systemctl restart apache2

# Enable SSL certs
echo "${INSTALL_LOG_PREFIX} Enable Certbot Certificate" | tee -a ${INSTALL_LOG}
certbot -q --apache --redirect --hsts --uir --agree-tos -m wwpresalesdemos@hyland.com -d ${FQDN} | tee -a ${INSTALL_LOG}

echo "${INSTALL_LOG_PREFIX} Setup profile, ubuntu, etc." | tee -a ${INSTALL_LOG}

#set up ubuntu user
cat << EOF >> /home/ubuntu/.profile
export TERM="xterm-color"
export PS1='\[\e[0;33m\]\u\[\e[0m\]@\[\e[0;32m\]\h\[\e[0m\]:\[\e[0;34m\]\w\[\e[0m\]\$ '
export COMPOSE_DIR=${COMPOSE_DIR}
alias dir='ls -alFGh'
alias hs='history'
alias mytail='nxl'
alias vilog='stack vilog'
alias mydu='du -sh */'

# Add stack management and QOL aliases
source ${COMPOSE_DIR}/aliases.sh

# Override some of the above for CLOUD usage
alias stack='make -e -f ${COMPOSE_DIR}/Makefile'

# Extras for CLOUD usage
alias nxenv='vim ${COMPOSE_DIR}/.env'
alias nxconf='vim ${CONF_DIR}/system.conf'

figlet $FQDN
EOF

# Set up vim for ubuntu user
cat << EOF > /home/ubuntu/.vimrc
" Set the filetype based on the file's extension, but only if
" 'filetype' has not already been set
au BufRead,BufNewFile *.conf setfiletype conf
EOF
echo "${INSTALL_LOG_PREFIX} Setup profile, ubuntu, etc. => DONE" | tee -a ${INSTALL_LOG}

echo "${INSTALL_LOG_PREFIX} Complete" | tee -a ${INSTALL_LOG}

# Set a flag so we know the script already ran.
touch "$MARKER_FILE"

