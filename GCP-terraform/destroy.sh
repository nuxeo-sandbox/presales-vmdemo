#!/bin/bash

# ==============================================================================
# Wrapper script to destroy a Nuxeo stack in GCP using Terraform
# ==============================================================================

# ==============================================================================
# Inputs
# ==============================================================================

# Get the workspace name (it's also the stack name)
nx_stack_name=`terraform workspace show`

# This value doesn't matter, it's not used, but the terraform config requires it.
nx_studio_project="foo"

# ==============================================================================
# Other params
# ==============================================================================
workspace_name=${nx_stack_name}

# params are printed to the screen and passed to Terraform; best to store in an array
params=(
  -var="stack_name=${nx_stack_name}"
  -var="nx_studio=${nx_studio_project}"
)

# ==============================================================================
# Summarize
# ==============================================================================
echo
echo "Stack name:       ${nx_stack_name}"
echo "Workspace name:   ${workspace_name}"

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
