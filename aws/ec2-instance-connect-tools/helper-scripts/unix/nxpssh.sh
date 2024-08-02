#!/bin/bash

scriptName=$(basename "$0")

function usage {
  echo
  echo "Usage: $scriptName [-p profile] [-r region] <instance_identifier> [src] [dest]"
  echo
  echo "Arguments:"
  echo "  instance_identifier   The EC2 instance; can be ID, Name, dnsName, or host."
  echo "  src                   Path of file to copy."
  echo "  dest                  Destination; if not specified, will use source file name."
  echo
  echo "Options:"
  echo "  -p string   AWS CLI profile to use; default is 'default'."
  echo "  -r string   AWS region. If not specified, will use \$AWS_REGION, region of selected profile, or 'us-east-1' (in that order)."
  echo "  -u user     The user for the host OS; default is 'ubuntu'"
  echo
  echo "Examples:"
  echo "  $scriptName my-demo                           SSH to EC2 instance with Name or dnsName \"mydemo\" using default AWS CLI profile and automatically selected region."
  echo "  $scriptName my-demo.cloud.nuxeo.com           Same as above."
  echo "  $scriptName -r eu-east-1 my-demo              SSH to EC2 instance with Name \"mydemo\" in region \"eu-east-1\"."
  echo "  $scriptName -p custom-profile my-demo         SSH to EC2 instance with Name \"mydemo\" using custom AWS CLI profile."
  echo "  $scriptName my-demo foo.txt                   SCP "foo.txt" to EC2 instance with Name or dnsName \"mydemo\" using default AWS CLI profile and automatically selected region."
  echo "  $scriptName my-demo.cloud.nuxeo.com foo.txt   Same as above."
}

profile=""
region=""
user=""
instance_identifier=""
src=""
dest=""
instance_id=""

DEFAULT_REGION="us-east-1"
DEFAULT_PROFILE="default"
DEFAULT_USER="ubuntu"

#===============================================================================
# Handle options.
#===============================================================================
while getopts ":r:p:" opt;
do
  case ${opt} in
    r)
      region=$OPTARG
      ;;
    p)
      profile=$OPTARG
      ;;
    u)
      user=$OPTARG
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

#===============================================================================
# Handle instance identifier.
#===============================================================================
instance_identifier=$1

# Make sure we have something to use
if [ -z "$instance_identifier" ]
then
  usage
  echo
  echo -e "$scriptName: error: the following arguments are required: instance_identifier"
  echo
  exit 2
fi

# Cleanup if needed (remove cloud.nuxeo.com)
if [[ $instance_identifier == *".cloud.nuxeo.com" ]]; then
  instance_identifier=${instance_identifier%.cloud.nuxeo.com}
fi

#===============================================================================
# Handle source.
#===============================================================================
src=$2


#===============================================================================
# Handle dest.
#===============================================================================
dest=$2

if [ "$src" ]
then
  if [ -z "$dest" ]
  then
    dest=$(basename "$src")
  fi

  # This should not really even be possible...
  if [ -z "$dest" ]
  then
    usage
    echo
    echo -e "$scriptName: error: dest is blank"
    echo
    exit 2
  fi
fi

#===============================================================================
# Handle profile.
#===============================================================================
if [ -z "$profile" ]
then
  profile=$DEFAULT_PROFILE
fi

#===============================================================================
# Handle region. NB: depends on $profile.
#===============================================================================
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

# If we still have nothing, use default; this is purely QOL, handles the most
# common use case of US users.
if [ -z "$region" ]
then
  region=$DEFAULT_REGION
  export AWS_REGION=$region
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

export AWS_REGION=$region

#===============================================================================
# Handle user.
#===============================================================================
if [ -z "$user" ]
then
  user=$DEFAULT_USER
fi

#===============================================================================
# Find instance Id
#===============================================================================
# If it's already an instance ID, just use it...
if [[ $instance_identifier == "i-"* ]]; then
  instance_id=$instance_identifier
fi

# Try dnsName
if [ -z "$instance_id" ]
then
  instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:dnsName,Values=$instance_identifier" \
    --query 'Reservations[].Instances[].[InstanceId]' \
    --region $region \
    --output text)
fi

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

#===============================================================================
# Confirm arguments.
#===============================================================================
echo
echo "Profile: $profile"
echo "Region: $region"
echo "Instance: $instance_identifier"
if [ "$src" ]
then
  echo "src: $src"
  echo "dest: $dest"
fi
echo "Instance ID: $instance_id"

#===============================================================================
# Connect
#===============================================================================
echo
echo "Executing:"

if [ "$src" ]
then
  echo "scp $src $user@$instance_id:$dest"
  echo
  scp $src $user@$instance_id:$dest
else
  echo "ssh $user@$instance_id"
  echo
  ssh $user@$instance_id
fi

echo

#===============================================================================
# Cleanup
#===============================================================================
# NB: this is hard-coded in aws-proxy.sh and the SSH config
EPHEMERAL_PRIVATE_SSH_KEY=~/.ssh/aws-proxy.$instance_id.$user
if [[ -e ${EPHEMERAL_PRIVATE_SSH_KEY} ]]
then
  rm $EPHEMERAL_PRIVATE_SSH_KEY*
fi