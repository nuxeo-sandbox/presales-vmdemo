#!/bin/bash

# ==============================================================================
# Wrapper script to destroy a Nuxeo stack in GCP using Terraform
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/preflight.sh"

# Reading the Terraform state and destroying the resources both need the right
# identity, so run the check before anything else.
nx_check_google_application_credentials

# ==============================================================================
# Inputs
# ==============================================================================

# Get the workspace name (it's also the stack name)
nx_stack_name=`terraform workspace show`

if [[ "$nx_stack_name" == "default" ]]; then
    echo "Error: selected workspace should not be 'default'."
    echo "Make sure to select the correct Workspace for the resources that you want to destroy. You can run..."
    echo "    terraform workspace list"
    echo "...to find the Workspace name, then run this to select it:"
    echo "    terraform workspace select <stack_name>"
    exit 1
fi

# These values don't matter, they're not used, but the terraform config requires
# them when they don't have a default value set.
nx_studio_project="foo"
nx_customer="bar"

# ==============================================================================
# Other params
# ==============================================================================

# Reassign just for readability and clarity.
workspace_name=${nx_stack_name}

# params are printed to the screen and passed to Terraform; best to store in an array
params=(
  -var="stack_name=${nx_stack_name}"
  -var="nx_studio=${nx_studio_project}"
  -var="customer=${nx_customer}"
)

# ==============================================================================
# Summarize
# ==============================================================================
echo
echo "Stack name:       ${nx_stack_name}"
echo "Workspace name:   ${workspace_name}"

# The Cloud SQL instance holds the whole repository: make it obvious that it,
# and its data, are about to be deleted.
db_instance=$(terraform output -raw cloud_sql_instance 2>/dev/null)
if [ -n "${db_instance}" ]
then
  echo "Cloud SQL:        ${db_instance}  <-- THIS DATABASE AND ALL ITS DATA WILL BE DELETED"
fi

echo
echo "Here's what will be executed:"
echo
echo "> terraform apply --destroy ${params[@]}"
echo "> terraform workspace select default"
echo "> terraform workspace delete ${workspace_name}"

echo
read -p "Ready? (y|n) [y]: " response
response=${response:-y}
if [[ "$response" != "y" ]]
then
  exit 0
fi

echo

# ==============================================================================
# Do the things
# ==============================================================================
terraform apply --destroy ${params[@]}
terraform workspace select default
terraform workspace delete ${workspace_name}
