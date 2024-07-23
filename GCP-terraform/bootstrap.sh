#!/bin/bash

# ==============================================================================
# Bootstrap script to deploy a Nuxeo stack in GCP using Terraform
# ==============================================================================

# ==============================================================================
# User inputs
# ==============================================================================

# Stack name
nx_stack_name="${NX_STACK_NAME:-}" # NB: this allows the value to be read from an environment variable.
# Required, loop until we get a value.
while [ -z "${nx_stack_name}" ]
do
  read -p "Stack name: " nx_stack_name
done

# Studio Project
nx_studio_project="${NX_STUDIO_PROJECT:-}"
# Required, loop until we get a value.
while [ -z "${nx_studio_project}" ]
do
  read -p "Studio Project ID: " nx_studio_project
done

# Automatically start Nuxeo?
NX_AUTO_START_DEFAULT=true
nx_auto_start="${NX_AUTO_START:-}"
if [ -z "${nx_auto_start}" ]
then
  while true
  do
    read -p "Auto start Nuxeo? [${NX_AUTO_START_DEFAULT}]: " nx_auto_start
    # If not specified, use default
    if [ -z "${nx_auto_start}" ]; then
        nx_auto_start=${NX_AUTO_START_DEFAULT}
    fi

    # Restrict input to 'true' or 'false'
    case "${nx_auto_start}" in
      true|false)
        break
        ;;
      *)
        echo "Invalid input. Please enter 'false' or you can press Enter to accept the default (${NX_AUTO_START_DEFAULT})."
        ;;
    esac
  done
fi

# DNS Name
# If not specified, use nx_stack_name
NX_DNS_NAME_DEFAULT=${nx_stack_name}
nx_dns_name="${NX_DNS_NAME:-}"
if [ -z "${nx_dns_name}" ]
then
  read -p "DNS name [${NX_DNS_NAME_DEFAULT}]: " nx_dns_name
  nx_dns_name=${nx_dns_name:-${NX_DNS_NAME_DEFAULT}}
fi

# Use NEV?
NX_USE_NEV_DEFAULT=false
nx_use_nev="${NX_USE_NEV:-}"
if [ -z "${nx_use_nev}" ]
then
  while true
  do
    read -p "Deploy NEV? [${NX_USE_NEV_DEFAULT}]: " nx_use_nev
    # If not specified, use default
    if [ -z "${nx_use_nev}" ]; then
        nx_use_nev=${NX_USE_NEV_DEFAULT}
    fi

    # Restrict input to 'true' or 'false'
    case "${nx_use_nev}" in
      true|false)
        break
        ;;
      *)
        echo "Invalid input. Please enter 'true' or you can press Enter to accept the default (${NX_USE_NEV_DEFAULT})."
        ;;
    esac
  done
fi

# NEV Version
if ${nx_use_nev}
then
  # Default is 2.3.1
  NEV_DEFAULT=2.3.1
  nev_version="${NX_NEV_VERSION:-}"
  if [ -z "${nev_version}" ]
  then
    read -p "NEV Version: [${NEV_DEFAULT}]: " nev_version
    nev_version=${nev_version:-${NEV_DEFAULT}}
  fi
fi

# ==============================================================================
# Other params
# ==============================================================================
workspace_name=${nx_stack_name}

# ==============================================================================
# Summarize inputs and parameters
# ==============================================================================
echo
echo "Stack name:      ${nx_stack_name}"
echo "Studio project:  ${nx_studio_project}"
echo "DNS name:        ${nx_dns_name}"
echo "Deploy NEV?      ${nx_use_nev}"
if ${nx_use_nev}
then
  echo "NEV version:     ${nev_version}"
fi
echo "Workspace name:  ${workspace_name}"
echo

read -p "Deploy this stack? (yes/no) [yes]: " response
response=${response:-yes}
if [[ "$response" != "yes" ]]
then
  exit 0
fi

echo

# ==============================================================================
# Do the things
# ==============================================================================
terraform init
# Create workspace
terraform workspace new ${workspace_name}
# Apply config
terraform apply -var="stack_name=${nx_stack_name}" -var="nx_studio=${nx_studio_project}" -var="with_nev=${nx_use_nev}" -var="dns_name=${nx_dns_name}"
