#!/usr/bin/env bash

set -o nounset
set -o errexit

ONE_TIME_KEY_FILE_NAME=$1
ONE_TIME_PUB_FILE_NAME="${ONE_TIME_KEY_FILE_NAME}.pub"
USER=$2
HOSTNAME=$3

echo "Generating Ephemeral SSH key ..." >&2
ssh-keygen -t rsa -b 2048 -f "${ONE_TIME_KEY_FILE_NAME}" -N '' <<<y >/dev/null 2>&1

echo "Pushing SSH public key to EC2 instance  ..." >&2

aws ec2-instance-connect send-ssh-public-key \
  --instance-id "${HOSTNAME}" \
  --instance-os-user "${USER}" \
  --ssh-public-key "file://${ONE_TIME_PUB_FILE_NAME}"

echo "Connecting using tunnel ..." >&2