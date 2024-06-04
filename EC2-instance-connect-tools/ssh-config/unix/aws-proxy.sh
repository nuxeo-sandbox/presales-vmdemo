#!/usr/bin/env bash

scriptName=$(basename "$0")

set -o nounset
set -o errexit

# /tmp/aws-proxy.cm-fraud.cloud.nuxeo.com.ubuntu
USER=$1
HOST=$2
# This is hard-coded in the SSH config becuase the ability to use vars is
# restricted.
EPHEMERAL_SSH_KEY=$3

EPHEMERAL_SSH_KEY_PUB=$EPHEMERAL_SSH_KEY.pub

#===============================================================================
# Handle host. We allow `dnsName` (this is a tag from the Nuxeo Presales
# CloudFormation template), a DNS host, or EC2 instance ID
#===============================================================================
# If Host is not an EC2 Instance ID, we need to get the EC2 Instance ID; this
# will be the most common use case to we handle it first.
if [[ $HOST != "i-"* ]]; then

  ec2TagValue=$HOST

  # If Host is a DNS host, strip it to just the dnsName value
  if [[ $ec2TagValue == *".cloud.nuxeo.com" ]]; then
    ec2TagValue=${ec2TagValue%.cloud.nuxeo.com}
  fi
  # Search for the EC2 Instance ID
  INSTANCE_ID=$(aws ec2 describe-instances \
      --filters "Name=tag:dnsName,Values=$ec2TagValue" \
      --query 'Reservations[].Instances[].[InstanceId]' \
      --output text)

  else
  INSTANCE_ID=$HOST
fi

# Sanity check
if [ -z "$INSTANCE_ID" ]
then
  echo  >&2
  echo "$scriptName: error: Instance ID not found for \"$HOST\""  >&2
  echo  >&2
  exit 1
fi

# Write instance ID file
# This value is used by the SSH config entry...
EPHEMERAL_EC2_INSTANCE_ID_FILE=~/.ssh/nxp_ec2_id.txt
cat << EOF > $EPHEMERAL_EC2_INSTANCE_ID_FILE
${INSTANCE_ID}
EOF

echo "EC2 Instance ID: $INSTANCE_ID" >&2

#===============================================================================
# Handle ephemeral SSH key.
#===============================================================================
echo "Generating Ephemeral SSH key ..." >&2
ssh-keygen -t rsa -b 2048 -f "${EPHEMERAL_SSH_KEY}" -N '' <<<y >/dev/null 2>&1

echo "Pushing SSH public key to EC2 instance  ..." >&2

aws ec2-instance-connect send-ssh-public-key \
  --instance-id "${INSTANCE_ID}" \
  --instance-os-user "${USER}" \
  --ssh-public-key "file://${EPHEMERAL_SSH_KEY_PUB}"

echo "Connecting using tunnel ..." >&2