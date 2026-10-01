#!/bin/bash

# ==============================================================================
# Shared pre-flight checks for the Terraform wrapper scripts of this folder.
#
# This file is meant to be *sourced*, not executed:
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/preflight.sh"
#
# The checks exist because the two failure modes below produce opaque HTTP 403
# errors, sometimes in the middle of a 15 minute `terraform apply`.
# ==============================================================================

# ------------------------------------------------------------------------------
# GOOGLE_APPLICATION_CREDENTIALS takes priority over the credentials created by
# `gcloud auth application-default login`, both for Terraform and for the Google
# client libraries. When it points at a service account that is not allowed to
# manage Compute Engine, Cloud SQL and DNS, everything fails with a 403 even
# though `gcloud auth application-default login` succeeded.
#
# Set NX_IGNORE_GAC=true to always ignore the variable without being asked,
# or NX_IGNORE_GAC=false to always keep it.
# ------------------------------------------------------------------------------
nx_check_google_application_credentials() {
  if [ -z "${GOOGLE_APPLICATION_CREDENTIALS}" ]
  then
    return 0
  fi

  # Only the service account e-mail is read, never the private key.
  local sa_email="unknown"
  if [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]
  then
    sa_email=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('client_email','unknown'))" \
                 "${GOOGLE_APPLICATION_CREDENTIALS}" 2>/dev/null) || sa_email="unknown"
  else
    sa_email="<file not found>"
  fi

  echo
  echo "--------------------------------------------------------------------------------"
  echo " WARNING: GOOGLE_APPLICATION_CREDENTIALS is set"
  echo "--------------------------------------------------------------------------------"
  echo "  File:            ${GOOGLE_APPLICATION_CREDENTIALS}"
  echo "  Service account: ${sa_email}"
  echo
  echo "Terraform gives this variable priority over the credentials set up by"
  echo "'gcloud auth application-default login'. If that service account is not allowed"
  echo "to manage Compute Engine, Cloud SQL and DNS, Terraform fails with 403 errors."
  echo

  local answer="${NX_IGNORE_GAC:-}"
  if [ -z "${answer}" ]
  then
    if [ -t 0 ]
    then
      read -p "Ignore it for this run and use your gcloud credentials? (y|n) [y]: " answer
      answer=${answer:-y}
      [ "${answer}" == "y" ] && answer="true" || answer="false"
    else
      # Non-interactive: do not silently change the identity someone may rely on.
      echo "Non-interactive run: the variable is KEPT. Set NX_IGNORE_GAC=true to ignore it."
      echo
      return 0
    fi
  fi

  if [ "${answer}" == "true" ]
  then
    unset GOOGLE_APPLICATION_CREDENTIALS
    echo "=> Ignored for this run. Your shell environment is NOT modified."
  else
    echo "=> Kept. Terraform will authenticate as ${sa_email}."
  fi
  echo
}

# ------------------------------------------------------------------------------
# Fail in two seconds rather than after a 15 minute apply: check that the
# current credentials can actually reach the Cloud SQL Admin API.
#
# Call this *after* nx_check_google_application_credentials, so the identity
# being tested is the one Terraform will use.
#
# Returns 0 when the API answers, 1 otherwise.
# ------------------------------------------------------------------------------
nx_check_cloud_sql_access() {
  local project="${1:-nuxeo-presales-apis}"

  echo "Checking access to the Cloud SQL Admin API in project '${project}'..."

  local token
  token=$(gcloud auth application-default print-access-token 2>/dev/null)
  if [ -z "${token}" ]
  then
    echo "  FAILED: no application default credentials available."
    echo "  Run: gcloud auth application-default login"
    return 1
  fi

  local response http_code body
  response=$(curl -s -w $'\n%{http_code}' -H "Authorization: Bearer ${token}" \
               "https://sqladmin.googleapis.com/v1/projects/${project}/instances" 2>/dev/null)
  http_code=$(printf '%s' "${response}" | tail -n 1)
  body=$(printf '%s' "${response}" | sed '$d')

  case "${http_code}" in
    200)
      echo "  OK: the Cloud SQL Admin API is enabled and your credentials are accepted."
      return 0
      ;;
    403)
      echo "  FAILED (HTTP 403)."
      printf '%s\n' "${body}" | head -12
      echo
      echo "  Two possible causes:"
      echo "    1. The Cloud SQL Admin API is not enabled on '${project}':"
      echo "         gcloud services enable sqladmin.googleapis.com --project ${project}"
      echo "       (note: 'Cloud SQL' and 'Cloud SQL Admin' are two different APIs)"
      echo "    2. Your credentials lack roles/cloudsql.admin on '${project}'."
      return 1
      ;;
    401)
      echo "  FAILED (HTTP 401): credentials rejected or expired."
      echo "  Run: gcloud auth application-default login"
      return 1
      ;;
    *)
      echo "  Unexpected answer (HTTP ${http_code}):"
      printf '%s\n' "${body}" | head -8
      return 1
      ;;
  esac
}

# ------------------------------------------------------------------------------
# The Cloud SQL instance has no public IP, because of the organization policies
# constraints/sql.restrictPublicIp and constraints/sql.restrictAuthorizedNetworks.
# It is reached over the private services access peering of the VPC, which needs
# an allocated IP range to exist.
#
# That range is a one-time project prerequisite, deliberately kept out of the
# Terraform configuration so that destroying a stack cannot remove it. The
# peering can be ACTIVE while its range has been deleted, in which case the
# instance creation fails several minutes into the apply.
#
# Returns 0 when a usable range is found, 1 otherwise.
# ------------------------------------------------------------------------------
nx_check_private_services_access() {
  local project="${1:-nuxeo-presales-apis}"
  local network="${2:-nuxeo-demo-instances}"

  echo "Checking private services access on VPC '${network}'..."

  local ranges
  ranges=$(gcloud services vpc-peerings list --network="${network}" --project="${project}" \
             --format="value(reservedPeeringRanges)" 2>/dev/null)

  if [ -z "${ranges}" ]
  then
    echo "  FAILED: no private services access peering on '${network}'."
    echo "  Cloud SQL cannot be reached without it. See the README, section"
    echo "  'Private connectivity'."
    return 1
  fi

  # The peering lists range *names*; each must still exist as a global address.
  local missing=""
  local range
  for range in ${ranges//,/ }
  do
    if ! gcloud compute addresses describe "${range}" --global --project "${project}" \
           --format="value(name)" > /dev/null 2>&1
    then
      missing="${missing} ${range}"
    fi
  done

  if [ -n "${missing}" ]
  then
    echo "  FAILED: the peering references range(s) that no longer exist:${missing}"
    echo
    echo "  The peering is ACTIVE but orphaned. Recreate the range once, for the"
    echo "  whole project (10.0.0.0/9 is free, the VPC only uses 10.128.0.0/9):"
    echo "    gcloud compute addresses create${missing} \\"
    echo "      --global --purpose=VPC_PEERING --addresses=10.60.0.0 --prefix-length=16 \\"
    echo "      --network=${network} --project=${project}"
    echo "    gcloud services vpc-peerings update \\"
    echo "      --service=servicenetworking.googleapis.com --network=${network} \\"
    echo "      --ranges=${missing# } --project=${project}"
    return 1
  fi

  echo "  OK: peering active with range(s): ${ranges}"
  return 0
}
