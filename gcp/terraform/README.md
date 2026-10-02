# TL;DR

Feasibility test: a Nuxeo demo VM on GCP whose repository is a **Google Cloud SQL
for PostgreSQL 16** instance instead of the usual MongoDB container.<br/>
Branch `gcp-with-cloud-sql`, not meant to be merged into `master`.

## Run it

```bash
gcloud auth application-default login
cd presales-vmdemo/gcp/terraform
./create-nuxeo-gcp.sh
```

* The script prompts for everything (stack name, Studio project, customer, zone,
machine type, NEV, keep-alive, Cloud SQL tier...) and the defaults are fine. Only
stack name, Studio project and customer have no default.

* It also pre-checks, in a couple of seconds, the four things that would otherwise
blow up ten minutes into the apply:
  * the `GOOGLE_APPLICATION_CREDENTIALS` trap,
  * the Cloud SQL Admin API availability,
  * your Cloud SQL permissions
  * and the VPC private services access range.

If a check fails, the message tells you the command to run. Budget
~15 minutes for the apply, the database alone takes ~5.

## Then check that Nuxeo really started

A successful `terraform apply` does **not** mean Nuxeo is running. `setup-nuxeo.sh`
has no `set -e`, so a failed Docker build still writes a "successful install" log.

```bash
gcloud compute ssh <stack_name> --zone <zone> --project nuxeo-presales-apis
docker ps
```

If empty => the build failed, whatever the reason (ffmpeg build failed, issue with
MongoDB version and Linux Kernel, …). **This is not related to this deployment**,
it's a Nuxeo Presales Docker issue.

Fix the issue (see example below) then

```bash
stack build
stack up
```

Issue example: Failed ffmpeg build. If you don't need ffmpeg at all in your test, then
edit the `$COMPOSE_DIR/build_nuxeo/Dockerfile` and comment our all the
RUN dnf -y install ffmpeg block

Details: [Known issues](#known-issues).

## Three things that will cost you money or time

1. **The Cloud SQL instance is billed 24/7, even while the VM is stopped**
   (~60 USD/month on the default tier). Keep the auto-shutdown answer at `true`,
   and run `./destroy-nuxeo-gcp.sh` as soon as the test is over.
   See [Cost: read this](#cost-read-this).
2. **Nothing starts the database back up.** After a nightly shutdown, run
   `./cloud-sql.sh start` *before* starting the VM, or Nuxeo will not boot.
3. **Never destroy in a panic** on a `503` while uploading the Terraform state.
   It is a transient GCS fault and the resources are usually created. Check with
   `terraform state list` and `terraform plan` first.
   See [Terraform state upload fails with a GCS 503](#terraform-state-upload-fails-with-a-gcs-503).

## Noise you can ignore

The `mongo` container restarts in a loop (kernel incompatibility) and is unused on
this branch. `docker compose stop mongo` silences it.

<br/>
<hr>
<br/>

# Description

Tooling to automate the creation of a Nuxeo demo instance on GCP via [Terraform](https://developer.hashicorp.com/terraform).

> Feasibility branch, see the [TL;DR](#tldr) above. The Nuxeo repository is
> [Google Cloud SQL for PostgreSQL](#database-google-cloud-sql-for-postgresql),
> and the Docker build may need a manual fix, see [Known issues](#known-issues).

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
* The instance has **no public IP**. Two organization policies are enforced on
  `nuxeo-presales-apis` and forbid it:
  `constraints/sql.restrictPublicIp` and `constraints/sql.restrictAuthorizedNetworks`.
  The database is therefore reached over the **private services access** peering
  of the `nuxeo-demo-instances` VPC. See [Private connectivity](#private-connectivity).
* The Docker containers reach that private IP transparently: Docker masquerades
  their traffic behind the VM's internal address, which routes over the peering.
* The connection is TLS-only (`ssl_mode = ENCRYPTED_ONLY` on Cloud SQL,
  `sslmode=require` in the JDBC URL).
* The VM also gets a static external IP. It is not needed by the database, it
  just keeps the DNS record stable across stop/start cycles.
* OpenSearch, the OpenSearch dashboards and the Google Cloud Storage blob provider
  are unchanged. The `mongo` container is still started by the compose stack but
  it is **not used** by Nuxeo (this branch is a feasibility test).

## Private connectivity

The VPC `nuxeo-demo-instances` needs an active private services access peering
**with an existing allocated IP range**. Beware: the peering can be `ACTIVE`
while its range has been deleted. Nothing warns you, and the instance creation
then fails several minutes into the apply with
`Invalid request: Incorrect Service Networking config`.

This range is a **one-time, project-level prerequisite** and is deliberately
*not* managed by this Terraform configuration, so that destroying a stack can
never remove it and break every other stack.

Check it:

```bash
gcloud services vpc-peerings list --network=nuxeo-demo-instances --project=nuxeo-presales-apis
gcloud compute addresses list --global --project=nuxeo-presales-apis
```

The names listed under `reservedPeeringRanges` must all appear in the second
command. If one is missing, create it once. `10.0.0.0/9` is free: the VPC is in
auto mode and only uses `10.128.0.0/9`.

```bash
gcloud compute addresses create nuxeo-demo-instances-ip-range \
  --global --purpose=VPC_PEERING --addresses=10.60.0.0 --prefix-length=16 \
  --network=nuxeo-demo-instances --project=nuxeo-presales-apis

gcloud services vpc-peerings update \
  --service=servicenetworking.googleapis.com \
  --network=nuxeo-demo-instances \
  --ranges=nuxeo-demo-instances-ip-range \
  --project=nuxeo-presales-apis
```

`create-nuxeo-gcp.sh` runs this check before prompting for anything.

## Prerequisites

Before the first `apply`, on the `nuxeo-presales-apis` project:

1. The **Cloud SQL Admin API** (`sqladmin.googleapis.com`) must be enabled. Beware:
   in the GCP Console, "Cloud SQL" and "Cloud SQL Admin API" are two different
   entries, and only the second one matters here.<br/>
   Go to the [GCP console](https://console.cloud.google.com/home/dashboard?project=nuxeo-presales-apis),
   APIs & Services > Enabled APIs & Services. Check you see "Cloud SQL Admin API",
   and if not, enable it.<br/>
   You can also do it with the command line:
   ```bash
   gcloud services enable sqladmin.googleapis.com --project nuxeo-presales-apis
   ```
2. Your Terraform identity needs `roles/cloudsql.admin` (or at least
   `cloudsql.instances.create`, `cloudsql.databases.create` and
   `cloudsql.users.create`) plus `compute.addresses.create`.
3. The private services access range must exist, see
   [Private connectivity](#private-connectivity).
4. Cloud SQL quota must be available in the deployment region.

`create-nuxeo-gcp.sh` checks points 1 to 3 before prompting for anything, so a
missing API, a wrong identity or a broken peering fails in two seconds instead
of mid-apply. To check by hand:

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
./cloud-sql.sh psql     # psql session on the Nuxeo database, run from the VM
```

...or with `gcloud`:

```bash
gcloud sql instances patch <instance> --project nuxeo-presales-apis --activation-policy NEVER
gcloud sql instances patch <instance> --project nuxeo-presales-apis --activation-policy ALWAYS
```

...or in the GCP Console: **SQL > `<instance>` > Stop / Start**.

**When the test is over, run `./destroy-nuxeo-gcp.sh`.** This deletes the database.

## Things to know

* Creating the Cloud SQL instance can take several minutes, it is slower than on `master`.
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

The VM has the `psql` client installed. Since the database has no public IP, it
can only be queried from inside the VPC, so run this **on the VM** (or use
`./cloud-sql.sh psql`, which does the SSH for you). The VCS tables (`hierarchy`,
`fulltext`, `acls`, `versions`, `kv`, `users`, `groups`, ...) must be present:

```bash
psql "host=$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-host) \
  dbname=nuxeo user=nuxeo sslmode=require" -c '\dt'
```

# Known issues

**Read this before deploying.** The Terraform part runs in a single pass, but the
Docker build may fail, so the deployment does not go all the way to a
running Nuxeo without a manual step.

## Example: The Docker build fails on ffmpeg

> [!NOTE]
> When there is an issue because of ffmpeg deployment, it should be fixed in
> Nuxeo Presales docker tooling. What is describe here is ofr quick testing.

**Symptom.** `terraform apply` succeeds, `/var/log/nuxeo_install.log` ends with a
success message, but `docker ps` returns nothing and Nuxeo never answers.

**Typical cause.** Broken dependencies in the RPM Fusion EL9 repository:

```
nothing provides libgpac.so.12()(64bit) needed by x264-...el9
nothing provides libSvtAv1Enc.so.2()(64bit) needed by ffmpeg-libs-7.1.5-1.el9
```

This comes from `build_nuxeo/Dockerfile` in
[nuxeo-presales-docker](https://github.com/nuxeo-sandbox/nuxeo-presales-docker)
`master`, which this branch does not modify. It is **not specific to PostgreSQL**:
it breaks MongoDB stacks too, on AWS as well as GCP. Pinning an older commit does
not help, the failure comes from the current state of the upstream repository.

**Workaround** when the ffmpeg build fails:

```bash
sudo su - ubuntu
vi $COMPOSE_DIR/build_nuxeo/Dockerfile
```
* In this feasibility test we did not need ffmpeg at all, so: Comment out the whole
`RUN dnf -y install ffmpeg ...` block (around line 44)

ffmpeg is only needed for video conversions. Everything else, including the
PostgreSQL repository, works without it.

* Else, well. Fix it. Adding `--skip-broken` may solve the issue

After changing `Dockerfile`, then:

```bash
stack build
stack up
```

## The install script hides build failures

`setup-nuxeo.sh` has no `set -e` and does not check any exit code. When
`docker compose build` fails, the script carries on, writes the
`/var/log/first-run-done` marker and reports a successful installation.

Two consequences:

* the install log looks complete while no container exists;
* restarting the VM will **not** replay the script, since the marker is there.

So when `docker ps` is empty, do not trust the log. Look for the real error:

```bash
sudo grep -nE 'did not complete successfully|ERROR' /var/log/nuxeo_install.log
```

## MongoDB cannot start on the current GCP image

The image runs kernel `7.0.0-1013-gcp`. MongoDB 8.0 refuses to start on kernel
6.19 and newer ([SERVER-121912](https://jira.mongodb.org/browse/SERVER-121912)),
so the `mongo` container restarts in a loop forever:

```
MongoDB cannot start: Linux kernel versions 6.19 and newer has a known
incompatibility with this version of MongoDB.
```

**Harmless on this branch**, since Nuxeo uses Cloud SQL and ignores that
container, but it is noisy. To silence it: `docker compose stop mongo`.

It does mean the GCP image is **unusable for MongoDB stacks**.
`_common/vm-image-builder/scripts/pin-lts-kernel.sh` addresses exactly this, but
it is only wired into `aws-ami.pkr.hcl`, and its content is AWS-specific
(it pins `linux-aws-lts-24.04`, which has no `linux-gcp` equivalent in it).

## Terraform state upload fails with a GCS 503

```
Error: Failed to upload state to gs://nuxeo-stacks-terraform-state-backend/...:
googleapi: Error 503: We encountered an internal error. Please try again.
```

A known transient fault of this backend. The resources are usually created and
the state usually persisted by a retry. **Check before acting, and never destroy
in a panic:**

```bash
terraform state list          # are the resources tracked?
gsutil ls -l gs://nuxeo-stacks-terraform-state-backend/terraform/state/<stack>.tfstate
terraform plan ...            # "No changes" means the state is in sync
```

If the state really was lost, Terraform writes an `errored.tfstate` next to the
configuration; push it back with `terraform state push errored.tfstate`.

# Not done yet

Deliberately left out to keep this branch focused on proving feasibility. Rough
order of value:

* **Fix ffmpeg in `nuxeo-presales-docker`.** This is the only thing standing
  between here and a true one-pass deployment. A good opportunity to also create
  a branch without the `mongo` container, usable through `NX_NPD_BRANCH`.
* **Make `setup-nuxeo.sh` fail loudly.** Check the exit codes of
  `docker compose build` and `up`, do not write the marker on failure, and add a
  final check that the containers are actually running.
* **Validate `nuxeo_keep_alive` in `create-nuxeo-gcp.sh`.** A date in the past is
  currently accepted; it got a VM stopped 48 minutes after creation by the
  nightly shutdown function.
* **Pin the kernel in the GCP packer image**, the way `aws-ami.pkr.hcl` does.
* **Add a `db_engine` variable** (`mongodb` | `postgresql`) so this work can be
  merged into `master` instead of living on a branch.
* **Redeploy `scheduled-shutdown` with Cloud SQL support**, and deal with the
  restart side: nothing starts the database back up, so a stack restarted in the
  morning will not boot until `./cloud-sql.sh start` is run.
* **Decide who owns the DNS record.** Terraform and the `add-dns-record` /
  `remove-dns-record` Cloud Functions both manage it today, which is why the
  record must be recreated by Terraform *before* starting a stopped VM,
  otherwise the next apply fails with a 409.

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

NB: `db_auto_shutdown` defaults to `false` here, whereas `NX_DB_AUTO_SHUTDOWN` in
`create-nuxeo-gcp.sh` defaults to `true`. The script always passes the value
explicitly, so this Terraform default only applies when you run `terraform apply`
by hand — in which case the database is never stopped automatically and keeps
billing.

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

## If the destroy fails on the database or the role

Symptom:

```
Error: failed to delete user nuxeo in instance ...:
  role "nuxeo" cannot be dropped because some objects depend on it
  Details: owner of database nuxeo
Error: failed to delete database "nuxeo". Detail: pq: must be owner of database nuxeo.
```

Cause: something ran `ALTER DATABASE nuxeo OWNER TO nuxeo`. The Cloud SQL API
drops databases as `cloudsqlsuperuser`, which is then no longer the owner, and a
role cannot be dropped while it owns a database. `setup-nuxeo.sh` no longer does
this, but stacks created before the fix are affected.

**If the VM is still running**, fix it properly, then destroy as usual:

```bash
gcloud compute ssh <stack_name> --zone <zone> --project nuxeo-presales-apis
```

```bash
DB_HOST=$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-host)
DB_PWD=$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-password)
PGPASSWORD="$DB_PWD" psql "host=$DB_HOST dbname=nuxeo user=nuxeo sslmode=require" \
  -c 'ALTER DATABASE nuxeo OWNER TO cloudsqlsuperuser;'
```

The Nuxeo role is a member of `cloudsqlsuperuser`, so it is allowed to hand the
database back. Do this **before** stopping the VM: the database has no public IP,
so without the VM there is no network path to it.

**If the VM is already gone**, drop the two resources from the state and destroy
the instance, which deletes everything it contains:

```bash
terraform workspace select <stack_name>
terraform state rm google_sql_database.nuxeo_db_schema google_sql_user.nuxeo_db_user
./destroy-nuxeo-gcp.sh
```

`terraform state rm` changes nothing in GCP, it only makes Terraform forget those
objects.

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


