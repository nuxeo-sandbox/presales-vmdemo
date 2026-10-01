# Description

Tooling to automate the creation of a Nuxeo demo instance on GCP via [Terraform](https://developer.hashicorp.com/terraform).

> **This branch (`gcp-with-cloud-sql`) uses Google Cloud SQL for PostgreSQL as the
> Nuxeo repository database, instead of the MongoDB container.** See
> [Database: Google Cloud SQL for PostgreSQL](#database-google-cloud-sql-for-postgresql).
> It is a feasibility test, it is not meant to be merged into `master`.

# Installation

Install [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer.

Install tooling:

```bash
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/gcp/terraform
```

## Credentials gotcha: `GOOGLE_APPLICATION_CREDENTIALS`

If the `GOOGLE_APPLICATION_CREDENTIALS` environment variable is set, Terraform
uses **that** service account key and **ignores** the credentials created by
`gcloud auth application-default login`. When the service account is not allowed
to manage Compute Engine, Cloud SQL and DNS, every API call fails with an opaque
HTTP 403 — sometimes in the middle of a 15 minute apply.

This is a common trap, because a leftover `export GOOGLE_APPLICATION_CREDENTIALS=...`
in a shell profile usually points at a per-stack service account key, which has
almost no permissions.

The three scripts of this folder detect it and offer to ignore the variable for
the run (your shell is never modified). You can also decide up front:

```bash
NX_IGNORE_GAC=true  ./create-nuxeo-gcp.sh   # always ignore the variable
NX_IGNORE_GAC=false ./create-nuxeo-gcp.sh   # always keep it
```

In a non-interactive run the variable is kept, so existing automation that
relies on a deployment service account is not silently re-pointed.

To check which identity a key file belongs to:

```bash
python3 -c "import json;print(json.load(open('$GOOGLE_APPLICATION_CREDENTIALS'))['client_email'])"
```

# Database: Google Cloud SQL for PostgreSQL

## What changes

Instead of the local MongoDB container, the stack creates a dedicated Cloud SQL
instance and Nuxeo runs on VCS (the SQL storage engine):

* Nuxeo is configured with the `postgresql` configuration template instead of
  `default,mongodb`. This template brings in the datasource, the VCS repository,
  the SQL key/value store and the SQL directories, and it ships the PostgreSQL
  JDBC driver.
* **PostgreSQL 16** is used: this is the version supported by Nuxeo LTS 2025, see
  the [Nuxeo PostgreSQL documentation](https://doc.nuxeo.com/nxdoc/postgresql/).
* The VM gets a **static external IP** (`google_compute_address`). That address is
  the only `authorized_network` of the Cloud SQL instance. A static IP is required
  here: an ephemeral one changes on every stop/start and would break the database
  connection after each nightly shutdown.
* The connection is TLS-only (`ssl_mode = ENCRYPTED_ONLY` on Cloud SQL,
  `sslmode=require` in the JDBC URL).
* OpenSearch, the OpenSearch dashboards and the Google Cloud Storage blob provider
  are unchanged. The `mongo` container is still started by the compose stack but
  it is **not used** by Nuxeo.

## Prerequisites

Before the first `apply`, on the `nuxeo-presales-apis` project:

1. The **Cloud SQL Admin API** (`sqladmin.googleapis.com`) must be enabled. Beware:
   in the GCP Console, "Cloud SQL" and "Cloud SQL Admin API" are two different
   entries, and only the second one matters here.
   ```bash
   gcloud services enable sqladmin.googleapis.com --project nuxeo-presales-apis
   ```
2. Your Terraform identity needs `roles/cloudsql.admin` (or at least
   `cloudsql.instances.create`, `cloudsql.databases.create` and
   `cloudsql.users.create`) plus `compute.addresses.create`.
3. Cloud SQL quota must be available in the deployment region.

`create-nuxeo-gcp.sh` checks points 1 and 2 before prompting for anything, so a
missing API or a wrong identity fails in two seconds instead of mid-apply. To
check by hand:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://sqladmin.googleapis.com/v1/projects/nuxeo-presales-apis/instances"
# 200 = all good | 403 = API disabled or missing role | 401 = stale credentials
```

To list the permissions your Terraform identity actually holds (this resolves
roles inherited from groups, folders and the organization):

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{"permissions":["cloudsql.instances.create","cloudsql.databases.create",
       "cloudsql.users.create","compute.addresses.create","compute.instances.create"]}' \
  "https://cloudresourcemanager.googleapis.com/v1/projects/nuxeo-presales-apis:testIamPermissions"
```

Only the permissions you hold are returned. If `compute.instances.create` is
missing from the answer, your credentials are wrong (see
[the `GOOGLE_APPLICATION_CREDENTIALS` gotcha](#credentials-gotcha-google_application_credentials))
rather than your roles.

## Cost: read this

**A running Cloud SQL instance is billed 24/7, even while the Nuxeo VM is stopped.**
A `db-custom-1-3840` instance is roughly 60 USD/month.

`create-nuxeo-gcp.sh` asks whether the Cloud SQL instance should be stopped
together with the VM:

* **yes** (default): the instance is labelled `nuxeo-keep-alive=<your value>` and
  the `scheduled-shutdown-gce` Cloud Function stops it at the same time as the VM.
  This requires that Cloud Function to have been
  [redeployed with Cloud SQL support](../cloud-functions/scheduled-shutdown-compute-engine-instance/README.md).
  Nothing restarts it automatically.
* **no**: the instance is labelled `nuxeo-keep-alive=true` (never stopped) and you
  must stop it yourself.

Either way, manage it with the helper script:

```bash
terraform workspace select <stack_name>
./cloud-sql.sh status   # state, IP, tier
./cloud-sql.sh stop     # stop (activation policy NEVER)
./cloud-sql.sh start    # start (activation policy ALWAYS)
./cloud-sql.sh psql     # open a psql session on the Nuxeo database
```

...or with `gcloud`:

```bash
gcloud sql instances patch <instance> --project nuxeo-presales-apis --activation-policy NEVER
gcloud sql instances patch <instance> --project nuxeo-presales-apis --activation-policy ALWAYS
```

...or in the GCP Console: **SQL > `<instance>` > Stop / Start**.

**When the test is over, run `./destroy-nuxeo-gcp.sh`.** This deletes the database.

## Things to know

* Creating the Cloud SQL instance takes 10 to 15 minutes, so `terraform apply` is
  much slower than on `master`.
* The Cloud SQL instance name carries a random suffix on purpose: a Cloud SQL
  instance name cannot be reused for about a week after deletion, and without the
  suffix a `destroy` followed by an `apply` would fail.
* Deletion protection is disabled on purpose, so `destroy-nuxeo-gcp.sh` works.
* The database password is generated by Terraform and passed to the VM through
  instance metadata, like the existing `nuxeo-secret`. Read it back with
  `terraform output -raw cloud_sql_password`.

## Checking the deployment

On the VM:

```bash
tail -F /var/log/nuxeo_install.log      # look for "Check Cloud SQL database => OK"
nxlogs                                  # look for "Testing URL: jdbc:postgresql://..."
nxbash                                  # then, inside the container:
  nuxeoctl showconf | grep -E 'nuxeo\.(db|templates)'
  ls /opt/nuxeo/server/lib/postgresql-*.jar
```

The VM has the `psql` client installed. The VCS tables (`hierarchy`, `fulltext`,
`acls`, `versions`, `kv`, `users`, `groups`, ...) must be present:

```bash
psql "host=<db-host> dbname=nuxeo user=nuxeo sslmode=require" -c '\dt'
```

# Create Resources

You can use the bootstrap script to automate resource creation, or handle it manually using the Terraform CLI. Note that in either case we use [Workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces) to separate our instances.

## Bootstrap Script

Use the included script to automate the setup:

```bash
./create-nuxeo-gcp.sh
```

The script will prompt for all needed values, but you may also supply param values via environment vars, e.g.:

```bash
NX_STACK_NAME=my-stack NX_STUDIO_PROJECT=my-studio-project NX_USE_NEV=false NX_DNS_NAME=my-dns-name NX_NEV_VERSION=2025.2.0 ./create-nuxeo-gcp.sh
```

Available variables:

Var | Purpose | Default
--- | --- | ---
`NX_STACK_NAME` | Used for Compute Instance ID | n/a
`NX_STUDIO_PROJECT` | Nuxeo Studio Project ID | n/a
`NX_CUSTOMER` | Prospect company name or 'generic' | n/a
`NX_ZONE` | Deployment zone | `us-central1-a`
`NX_NUXEO_VERSION` | Nuxeo Docker image version | `2025`
`NX_MACHINE_TYPE` | Compute Engine instance type | `e2-standard-2`
`NX_AUTO_START` | Start Nuxeo stack after instance creation | `true`
`NX_DNS_NAME` | URL i.e. `NX_DNS_NAME.gcp.cloud.nuxeo.com` | `$NX_STACK_NAME`
`NX_NPD_BRANCH` | Branch of `nuxeo-presales-docker` to use | `master`
`NX_USE_NEV` | Deploy NEV? | `false`
`NX_NEV_VERSION` | Version of NEV to deploy | `2025.2.0`
`NX_KEEP_ALIVE` | Control auto shutdown | `20h00m`
`NX_DB_TIER` | Cloud SQL machine type | `db-custom-1-3840`
`NX_DB_VERSION` | Cloud SQL database version | `POSTGRES_16`
`NX_DB_AUTO_SHUTDOWN` | Stop the Cloud SQL instance with the VM | `true`
`NX_IGNORE_GAC` | Ignore `GOOGLE_APPLICATION_CREDENTIALS` | prompted

Don't forget to make the script executable if needed:

```bash
chmod u+x create-nuxeo-gcp.sh
```

## Terraform CLI

Deploy using Terraform CLI directly:

```bash
terraform workspace new <stack_name>
terraform apply <params>
```

Possible params are:

Param | Purpose | Default
--- | --- | ---
stack_name | Used for Compute Instance ID | n/a
dns_name | URL e.g. "dns_name.gcp.cloud.nuxeo.com" | stack_name
nuxeo_version | Nuxeo Docker image version |
nx_studio | Nuxeo Studio Project ID | n/a
nuxeo_zone | Deployment zone | us-central1-a
machine_type | Compute Engine instance type | e2-standard-2
auto_start | Start Nuxeo stack after instance creation | true
with_nev | Deploy NEV? | false
nev_version | Version of NEV to deploy | 2025.2.0
nuxeo_keep_alive | Control auto shutdown | 20h00m
customer | Prospect company name or 'generic' | n/a
npd_branch | Branch of `nuxeo-presales-docker` to use | `master`
db_tier | Cloud SQL machine type | `db-custom-1-3840`
db_version | Cloud SQL database version | `POSTGRES_16`
db_disk_size | Cloud SQL data disk size, in GB | 10
db_name | Name of the Nuxeo database | `nuxeo`
db_user | Name of the Nuxeo database role | `nuxeo`
db_auto_shutdown | Stop the Cloud SQL instance with the VM | false

NB: params are not required. Terraform will prompt you to enter values as needed, but if you want to override any default values you must pass the new value, Terraform won't prompt for values that have a default.

Example:

```bash
terraform apply -var="stack_name=my-stack-name" -var="nx_studio=my-studio-project" -var="with_nev=false"
```

# Destroy Resources

Make sure to select the correct Workspace for the resources that you want to destroy. You can run `terraform workspace list` to find the Workspace name.

```bash
terraform workspace select <stack_name>
```

This destroys the Cloud SQL instance and its data as well. Do it as soon as the
test is over, the database is the expensive part of the stack.

## Script

Use the included script to automate the deletion:

```bash
./destroy-nuxeo-gcp.sh
```

Don't forget to make the script executable if needed:

```bash
chmod u+x destroy-nuxeo-gcp.sh
```

## Terraform CLI

You can do it manually as well. You *must* specify the stack name when running `terraform apply --destroy`. You can parameterize it like so:

```bash
terraform apply --destroy -var="stack_name=my-stack-name"
```

Note: `terraform apply --destroy` will prompt for any variable values that don't have a default. Other than the stack name, you can just press enter or, if the value can't be null, you can enter junk. Cf. https://github.com/hashicorp/terraform/issues/23552 and https://github.com/hashicorp/terraform/pull/29291

If you're done with this project, delete the Workspace:

```bash
terraform workspace select default # You have to switch to a different Workspace before you delete
terraform workspace delete <stack_name>
```

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).


