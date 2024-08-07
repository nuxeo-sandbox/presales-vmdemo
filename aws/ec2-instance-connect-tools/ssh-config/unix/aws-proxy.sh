#!/usr/bin/env bash

set -o nounset
set -o errexit

scriptName=$(basename "$0")

USER=$1
EC2_INSTANCE_ID=$2
# NB: This is hard-coded in the SSH config because the ability to use env vars
# is restricted.
EPHEMERAL_SSH_KEY=$3

# if region is not passed, get the default one with the aws cli
REGION=${4-$(aws configure get region)}

EPHEMERAL_SSH_KEY_PUB=$EPHEMERAL_SSH_KEY.pub

#===============================================================================
# Sanity check
#===============================================================================

if [ -z "$USER" ]
then
  echo  >&2
  echo "$scriptName: error: the following arguments are required: USER"  >&2
  echo  >&2
  exit 1
fi

if [ -z "$EC2_INSTANCE_ID" ]
then
  echo  >&2
  echo "$scriptName: error: the following arguments are required: EC2_INSTANCE_ID"  >&2
  echo  >&2
  exit 1
fi

if [ -z "$EPHEMERAL_SSH_KEY" ]
then
  echo  >&2
  echo "$scriptName: error: the following arguments are required: EPHEMERAL_SSH_KEY"  >&2
  echo  >&2
  exit 1
fi

#===============================================================================
# Handle ephemeral SSH key.
#===============================================================================
# Generate ssh key. NB: it is automatically deleted by the wrapper scripts.
ssh-keygen -t rsa -b 2048 -f "${EPHEMERAL_SSH_KEY}" -N '' <<<y >/dev/null 2>&1

# Push SSH public key to EC2 instance. NB: only valid for 60 seconds on the
# server.
aws ec2-instance-connect send-ssh-public-key \
  --instance-id "${EC2_INSTANCE_ID}" \
  --instance-os-user "${USER}" \
  --ssh-public-key "file://${EPHEMERAL_SSH_KEY_PUB}" \
  --region "${REGION}"