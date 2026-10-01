#!/bin/bash

# ==============================================================================
# Manage the Cloud SQL instance of the currently selected Terraform workspace.
#
#   ./cloud-sql.sh status   show the instance state, IP and tier
#   ./cloud-sql.sh start    start the instance (activation policy ALWAYS)
#   ./cloud-sql.sh stop     stop the instance  (activation policy NEVER)
#   ./cloud-sql.sh psql     open a psql session on the Nuxeo database
#
# A running Cloud SQL instance is billed 24/7, even while the Nuxeo VM is
# stopped. The nightly `scheduled-shutdown-gce` Cloud Function only stops the
# instance if it was created with `db_auto_shutdown=true`.
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/preflight.sh"

# `terraform output` below reads the state from GCS, so it needs the same
# identity as the rest of the tooling.
nx_check_google_application_credentials

action="${1:-status}"

# ==============================================================================
# Locate the instance through the Terraform outputs of the current workspace
# ==============================================================================
workspace=$(terraform workspace show 2>/dev/null)
if [[ -z "${workspace}" || "${workspace}" == "default" ]]
then
  echo "Error: no stack workspace selected."
  echo "Run 'terraform workspace list' then 'terraform workspace select <stack_name>'."
  exit 1
fi

db_instance=$(terraform output -raw cloud_sql_instance 2>/dev/null)
gcp_project=$(terraform output -raw gcp_project 2>/dev/null)

if [[ -z "${db_instance}" ]]
then
  echo "Error: could not read 'cloud_sql_instance' from the Terraform outputs of"
  echo "workspace '${workspace}'. Has the stack been applied?"
  exit 1
fi

# ==============================================================================
# Do the things
# ==============================================================================
case "${action}" in
  status)
    gcloud sql instances describe "${db_instance}" --project "${gcp_project}" \
      --format="table(name, state, settings.activationPolicy, databaseVersion, settings.tier, ipAddresses[0].ipAddress)"
    ;;

  start)
    echo "Starting Cloud SQL instance ${db_instance}... (this takes a couple of minutes)"
    gcloud sql instances patch "${db_instance}" --project "${gcp_project}" \
      --activation-policy ALWAYS --quiet
    ;;

  stop)
    echo "Stopping Cloud SQL instance ${db_instance}..."
    gcloud sql instances patch "${db_instance}" --project "${gcp_project}" \
      --activation-policy NEVER --quiet
    ;;

  psql)
    # Reads the credentials straight from the Terraform outputs, so there is no
    # need to copy the generated password around.
    db_host=$(terraform output -raw cloud_sql_public_ip 2>/dev/null)
    db_name=$(terraform output -raw cloud_sql_database 2>/dev/null)
    db_user=$(terraform output -raw cloud_sql_user 2>/dev/null)
    db_password=$(terraform output -raw cloud_sql_password 2>/dev/null)

    if [[ -z "${db_password}" ]]
    then
      echo "Error: could not read the database password from the Terraform state."
      exit 1
    fi

    echo "Connecting to ${db_name} on ${db_host} as ${db_user}..."
    echo "Note: your current public IP must be an authorized network, otherwise this"
    echo "      will time out. Only the Nuxeo VM is authorized by default."
    PGPASSWORD="${db_password}" psql "host=${db_host} port=5432 dbname=${db_name} user=${db_user} sslmode=require"
    ;;

  *)
    echo "Usage: $0 [status|start|stop|psql]"
    exit 1
    ;;
esac
