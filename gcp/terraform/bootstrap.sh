#!/bin/bash

# ==============================================================================
# Bootstrap script to deploy a Nuxeo stack in GCP using Terraform
# ==============================================================================

# ==============================================================================
# User inputs
# ==============================================================================

# Stack name
# ==========
nx_stack_name="${NX_STACK_NAME:-}" # NB: this syntax allows the value to be read from an environment variable.
# Required, loop until we get a value.
while [ -z "${nx_stack_name}" ]
do
  read -p "Stack name: " nx_stack_name
done

# Studio Project
# ==============
nx_studio_project="${NX_STUDIO_PROJECT:-}"
# Required, loop until we get a value.
while [ -z "${nx_studio_project}" ]
do
  read -p "Studio Project ID: " nx_studio_project
done

# Customer
# ========
nx_customer="${NX_CUSTOMER:-}"
# Required, loop until we get a value.
while [ -z "${nx_customer}" ]
do
  read -p "Customer name or 'generic': " nx_customer
done

# Deployment zone
# ===============
NX_ZONE_DEFAULT="us-central1-a"
nx_zone="${NX_ZONE:-}"
if [ -z "${nx_zone}" ]
then
  read -p "Deployment zone [${NX_ZONE_DEFAULT}]: " nx_zone
  nx_zone=${nx_zone:-${NX_ZONE_DEFAULT}}
fi

# Nuxeo version
# =============
# Default is "2023" which pulls the latest release of 2023.
NX_NUXEO_VERSION_DEFAULT="2023"
nx_nuxeo_version="${NX_NUXEO_VERSION:-}"
if [ -z "${nx_nuxeo_version}" ]
then
  read -p "Nuxeo version [${NX_NUXEO_VERSION_DEFAULT}]: " nx_nuxeo_version
  nx_nuxeo_version=${nx_nuxeo_version:-${NX_NUXEO_VERSION_DEFAULT}}
fi

# Machine Type
# ============
NX_MACHINE_TYPE_DEFAULT_SELECTION=1
nx_machine_type="${NX_MACHINE_TYPE:-}"
if [ -z "${nx_machine_type}" ]
then
  # Hourly rates are just to give and idea of the scale, not guaranteed to be accurate.
  # You can add new machine types here and the script will automatically support them as long as you follow the same format.
  MACHINE_TYPES_MENU=(
    "e2-standard-2  2cpu   8GB  \$0.07/hr"
    "e2-standard-4  4cpu  16GB  \$0.13/hr"
    "e2-standard-8  8cpu  32GB  \$0.27/hr"
  )
  NUM_MACHINE_TYPES_MENU=${#MACHINE_TYPES_MENU[@]}
  i=0

  # Print numbered menu items, based on the arguments passed.
  for machine in "${MACHINE_TYPES_MENU[@]}"
  do
    printf '%s\n' "$((++i))) $machine"
  done

  read -r -p "Machine type? (you can enter a custom type too) [1]: " selected

  # Allow empty input, in that case the default value is used.
  if [ -z "${selected}" ]
  then
    selected=${NX_MACHINE_TYPE_DEFAULT_SELECTION}
  fi

  # Process the selected item.
  case $selected in
    1 | 2 | 3)
      # QOL: extract machine type from the menu string so we only have to update one place to add new/edit existing types.
      nx_machine_type=$( echo ${MACHINE_TYPES_MENU[(selected-1)]} | cut -d' ' -f 1)
      ;;
    *)
      nx_machine_type=${selected}
      ;;
  esac
fi

# Automatically start Nuxeo?
# ==========================
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
# ========
# If not specified, use nx_stack_name
NX_DNS_NAME_DEFAULT=${nx_stack_name}
nx_dns_name="${NX_DNS_NAME:-}"
if [ -z "${nx_dns_name}" ]
then
  read -p "DNS name [${NX_DNS_NAME_DEFAULT}]: " nx_dns_name
  nx_dns_name=${nx_dns_name:-${NX_DNS_NAME_DEFAULT}}
fi

# NPD Branch
# =====================
NX_NPD_BRANCH_DEFAULT="master"
nx_npd_branch="${NX_NPD_BRANCH:-}"
if [ -z "${nx_npd_branch}" ]
then
  read -p "Which nuxeo-presales-docker (NPD) branch? [${NX_NPD_BRANCH_DEFAULT}]: " nx_npd_branch
  nx_npd_branch=${nx_npd_branch:-${NX_NPD_BRANCH_DEFAULT}}
fi

# Use NEV?
# ========
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
# ===========
if ${nx_use_nev}
then
  # Default is 2023.2.1
  NEV_DEFAULT=2023.2.1
  nev_version="${NX_NEV_VERSION:-}"
  if [ -z "${nev_version}" ]
  then
    read -p "NEV Version: [${NEV_DEFAULT}]: " nev_version
    nev_version=${nev_version:-${NEV_DEFAULT}}
  fi
fi

# Control auto shutdown
# =====================
NX_KEEP_ALIVE_DEFAULT="20h00m"
nx_keep_alive="${NX_KEEP_ALIVE:-}"
if [ -z "${nx_keep_alive}" ]
then
  read -p "Keep alive until (true|YYYY-MM-DDtHHhMMm|HHhMMm) [${NX_KEEP_ALIVE_DEFAULT}]: " nx_keep_alive
  nx_keep_alive=${nx_keep_alive:-${NX_KEEP_ALIVE_DEFAULT}}
fi

# ==============================================================================
# Other params
# ==============================================================================
workspace_name=${nx_stack_name}

# params are printed to the screen and passed to Terraform; best to store in an array
params=(
  -var="stack_name=${nx_stack_name}"
  -var="nx_studio=${nx_studio_project}"
  -var="nuxeo_version=${nx_nuxeo_version}"
  -var="nuxeo_zone=${nx_zone}"
  -var="machine_type=${nx_machine_type}"
  -var="with_nev=${nx_use_nev}"
  -var="dns_name=${nx_dns_name}"
  -var="nuxeo_keep_alive=${nx_keep_alive}"
  -var="customer=${nx_customer}"
  -var="npd_branch=${nx_npd_branch}"
)
if ${nx_use_nev}
then
  params+=( -var="nev_version=${nev_version}" )
fi

# ==============================================================================
# Summarize
# ==============================================================================
echo
echo "Stack name:       ${nx_stack_name}"
echo "Studio project:   ${nx_studio_project}"
echo "Customer:         ${nx_customer}"
echo "Nuxeo version:    ${nx_nuxeo_version}"
echo "Deployment zone:  ${nx_zone}"
echo "Machine type:     ${nx_machine_type}"
echo "DNS name:         ${nx_dns_name}"
echo "NPD branch:       ${nx_npd_branch}"
echo "Deploy NEV?       ${nx_use_nev}"
if ${nx_use_nev}
then
  echo "NEV version:      ${nev_version}"
fi
echo "Keep alive until: ${nx_keep_alive}"
echo "Workspace name:   ${workspace_name}"

echo
echo "Here's what will be executed:"
echo
echo "> terraform init"
echo "> terraform workspace new ${workspace_name}"
echo "> terraform apply ${params[@]}"

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
terraform init
# Create workspace
# Doesn't check for existing because Terraform doesn't care, it won't fail, and
# makes the script simpler.
terraform workspace new ${workspace_name}
# Apply config
terraform apply ${params[@]}
