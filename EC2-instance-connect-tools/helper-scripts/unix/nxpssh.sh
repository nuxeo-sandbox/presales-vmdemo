#!/bin/bash

scriptName=$(basename "$0")

function usage {
  echo
  echo "Usage: $scriptName [-p profile] [-r region] <instance_identifier>"
  echo ""
  echo "Arguments:"
  echo "  instance_identifier   The EC2 instance to find; can be Name, dnsName, or host."
  echo ""
  echo "Options:"
  echo "  -p string   AWS CLI profile to use; default is 'default'."
  echo "  -r string   AWS region. If not specified, will use \$AWS_REGION or region of selected profile. AWS_REGION takes precedence."
  echo ""
  echo "Examples:"
  echo "  $scriptName my-demo                     Connect to EC2 instance with Name or dnsName \"mydemo\" using default AWS CLI profile and automatically selected region."
  echo "  $scriptName my-demo.cloud.nuxeo.com     Same as above."
  echo "  $scriptName -r eu-east-1 my-demo        Connect to EC2 instance with Name \"mydemo\" in region \"eu-east-1\"."
  echo "  $scriptName -p custom-profile my-demo   Connect to EC2 instance with Name \"mydemo\" using custom AWS CLI profile."
}

instance_identifier=""
region=""
profile="default"

# ==================================================
# Handle options.
# ==================================================
while getopts ":r:p:" opt;
do
  case ${opt} in
    r)
      region=$OPTARG
      ;;
    p)
      profile=$OPTARG
      ;;
    \?)
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

# ==================================================
# Handle instance identifier.
# ==================================================
# TODO: allow Instance ID; e.g. use a regex to check if it's already an Instance ID
instance_identifier=$1

# Cleanup if needed (remove cloud.nuxeo.com)
if [[ $instance_identifier == *".cloud.nuxeo.com" ]]; then
  instance_identifier=${instance_identifier%.cloud.nuxeo.com}
fi

# Make sure we have something to search with
if [ -z "$instance_identifier" ]
then
  usage
  echo
  echo -e "$scriptName: error: the following arguments are required: instance_identifier"
  echo
  exit 2
fi

# ==================================================
# Handle region.
# ==================================================
# If no region passed, use AWS_REGION
if [ -z "$region" ]
then
  region=$AWS_REGION
fi

# If no AWS_REGION, use profile
if [ -z "$region" ]
then
  region=$(aws configure get region --profile $profile)
fi

# If that didn't work, we're screwed...
if [ -z "$region" ]
then
  usage
  echo
  echo "$scriptName: error: unable to determine AWS region"
  echo
  exit 2
fi

# ==================================================
# Confirm arguments.
# ==================================================
echo
echo "Instance: $instance_identifier"
echo "Region: $region"
echo "Profile: $profile"

# ==================================================
# Find instance Id
# ==================================================
# Try dnsName
instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:dnsName,Values=$instance_identifier" \
    --query 'Reservations[].Instances[].[InstanceId]' \
    --region $region \
    --output text)

# Try instance Name
if [ -z "$instance_id" ]
then
  instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$instance_identifier" \
    --query 'Reservations[].Instances[].[InstanceId]' \
    --region $region \
    --output text)
fi

if [ -z "$instance_id" ]
then
  echo
  echo "$scriptName: error: Instance ID not found for \"$instance_identifier\""
  echo
  exit 3
fi

echo "Instance ID: $instance_id"

# ==================================================
# Connect
# ==================================================
echo
echo "Executing:"
echo "aws ec2-instance-connect ssh --instance-id $instance_id --os-user ubuntu --connection-type eice --region $region --profile $profile"
echo
aws ec2-instance-connect ssh --instance-id $instance_id --os-user ubuntu --connection-type eice --region $region --profile $profile
