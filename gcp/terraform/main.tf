# Create Nuxeo stack on GCP using Terraform.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.3"
    }
  }
}

variable "gcp_project" {
  type        = string
  description = "GCP project name"
  default     = "nuxeo-presales-apis"
}

variable "customer" {
  type        = string
  description = "Prospect company name or 'generic'"
}

variable "stack_name" {
  type        = string
  description = "Stack name (used for Compute Instance Name and DNS if not set)"
}

variable "dns_name" {
  type        = string
  description = "DNS name (i.e. dns_name.gcp.cloud.nuxeo.com)"
  default     = ""
}

locals {
  # DNS name defaults to stack_name if nothing is set
  dns_name = var.dns_name == "" ? var.stack_name : var.dns_name
  # Cloud SQL instances are regional: "us-central1-a" => "us-central1"
  region = join("-", slice(split("-", var.nuxeo_zone), 0, 2))
  # For the scheduled-shutdown Cloud Function, "true" means "never shut down".
  db_keep_alive = var.db_auto_shutdown ? var.nuxeo_keep_alive : "true"
}

variable "nuxeo_version" {
  type        = string
  description = "Version of Nuxeo to deploy"
  default     = "2025"
}

variable "nx_studio" {
  type        = string
  description = "Nuxeo Studio Poject ID"
}

variable "with_nev" {
  type        = bool
  description = "Deploy NEV?"
  default     = false
}

variable "nev_version" {
  type        = string
  description = "Version of NEV to deploy"
  default     = "2025.2.0"
}

variable "auto_start" {
  type        = bool
  description = "Automatically start Nuxeo?"
  default     = true
}

variable "nuxeo_keep_alive" {
  type        = string
  description = "Control auto shutdown"
  default     = "20h00m" # 8:00 PM relative to the zone
}

variable "nuxeo_zone" {
  type        = string
  description = "Deployment zone"
  default     = "us-central1-a"
}

variable "machine_type" {
  type        = string
  description = "Compute Engine instance type"
  default     = "e2-standard-2"
}

variable "npd_branch" {
  type        = string
  description = "Branch of nuxeo-presales-docker to use"
  default     = "master"
}

# Database (Google Cloud SQL for PostgreSQL) variables

variable "db_tier" {
  type        = string
  description = "Cloud SQL machine type"
  default     = "db-custom-1-3840" # 1 vCPU, 3.75 GB
}

variable "db_version" {
  type        = string
  description = "Cloud SQL database version. Nuxeo LTS 2025 supports PostgreSQL 16."
  default     = "POSTGRES_16"
}

variable "db_disk_size" {
  type        = number
  description = "Cloud SQL data disk size, in GB"
  default     = 10
}

variable "db_name" {
  type        = string
  description = "Name of the Nuxeo database"
  default     = "nuxeo"
}

variable "db_user" {
  type        = string
  description = "Name of the Nuxeo database role"
  default     = "nuxeo"
}

variable "db_auto_shutdown" {
  type        = bool
  description = "Let the scheduled-shutdown Cloud Function stop the Cloud SQL instance along with the VM"
  default     = false
}

provider "google" {
  project = var.gcp_project
  default_labels = {
    billing-category    = "presales"
    billing-subcategory = var.customer
  }
}

# Nuxeo Instance resources

resource "random_password" "nuxeo_secret" {
  length           = 64
  special          = true
  override_special = "-"
}

resource "google_service_account" "service_account" {
  account_id   = "nxp-${var.stack_name}"
  display_name = "Service Account for the ${var.stack_name} nuxeo instance"
}

data "google_secret_manager_secret" "shared_credentials" {
  secret_id = "nuxeo-presales-connect"
}

data "google_secret_manager_secret" "instance_credentials" {
  secret_id = "instance-credentials"
}

data "google_secret_manager_secret" "kibana_credentials" {
  secret_id = "kibana-password"
}

resource "google_secret_manager_secret_iam_member" "shared_credentials_member" {
  secret_id = data.google_secret_manager_secret.shared_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "instance_credentials_member" {
  secret_id = data.google_secret_manager_secret.instance_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "kibana_credentials_member" {
  secret_id = data.google_secret_manager_secret.kibana_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.service_account.email}"
}

data "google_storage_bucket" "content_bucket" {
  name = "nuxeo-demo-shared-bucket-us"
}

resource "google_storage_bucket_iam_member" "member" {
  bucket = data.google_storage_bucket.content_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

# Database resources (Google Cloud SQL for PostgreSQL)

resource "random_password" "db_password" {
  length = 32
  # Only alphanumerics and "-" so the value is safe in a Java .properties file,
  # in a JDBC URL and in a psql connection string.
  special          = true
  override_special = "-"
}

# A Cloud SQL instance name cannot be reused for about a week after deletion,
# so a random suffix is required to keep `destroy` then `apply` cycles working.
resource "random_id" "db_suffix" {
  byte_length = 4
  keepers = {
    stack_name = var.stack_name
  }
}

# The VM needs a stable external IP address: it is the only address allowed to
# reach Cloud SQL, and an ephemeral IP would change on every stop/start cycle.
resource "google_compute_address" "nuxeo_ip" {
  name   = "${var.stack_name}-ip"
  region = local.region
}

resource "google_sql_database_instance" "nuxeo_db" {
  name             = "${var.stack_name}-pg-${random_id.db_suffix.hex}"
  region           = local.region
  database_version = var.db_version
  # Demo stacks are disposable: never block `terraform destroy`.
  deletion_protection = false

  settings {
    tier                        = var.db_tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.db_disk_size
    disk_autoresize             = true
    deletion_protection_enabled = false

    # No backup: this is a throw-away demo database, and it makes deletion faster.
    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled = true
      # Reject any connection that is not encrypted.
      ssl_mode = "ENCRYPTED_ONLY"
      authorized_networks {
        name  = var.stack_name
        value = "${google_compute_address.nuxeo_ip.address}/32"
      }
    }

    # Nuxeo opens at most ~40 connections with the pool sizes set in setup-nuxeo.sh.
    database_flags {
      name  = "max_connections"
      value = "200"
    }

    # `default_labels` from the provider does not apply to Cloud SQL, set them here.
    user_labels = {
      "billing-category"    = "presales"
      "billing-subcategory" = var.customer
      "nuxeo-keep-alive"    = local.db_keep_alive
      "dns-name"            = local.dns_name
    }
  }
}

resource "google_sql_database" "nuxeo_db_schema" {
  name     = var.db_name
  instance = google_sql_database_instance.nuxeo_db.name
  # UTF8 is required by Nuxeo. It is the Cloud SQL default, we make it explicit.
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Users created through the Cloud SQL API are members of `cloudsqlsuperuser`,
# which owns the database, so this role can create the Nuxeo schema.
resource "google_sql_user" "nuxeo_db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.nuxeo_db.name
  password = random_password.db_password.result
}

resource "google_compute_instance" "nuxeo_instance" {
  depends_on = [
    google_secret_manager_secret_iam_member.shared_credentials_member,
    google_secret_manager_secret_iam_member.instance_credentials_member,
    google_storage_bucket_iam_member.member,
    google_secret_manager_secret_iam_member.kibana_credentials_member,
    # The startup script checks the database connection: the database and its
    # role must exist before the VM boots.
    google_sql_database.nuxeo_db_schema,
    google_sql_user.nuxeo_db_user
  ]
  name         = var.stack_name
  machine_type = var.machine_type
  zone         = var.nuxeo_zone
  service_account {
    email = google_service_account.service_account.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/cloud-platform",
      "storage-full"
    ]
  }
  metadata = {
    enable-oslogin : "TRUE"
    enable-osconfig : "TRUE"
    stack-name : var.stack_name
    dns-name : local.dns_name
    nuxeo-version : var.nuxeo_version
    nx-studio : var.nx_studio
    with-nev : var.with_nev
    nuxeo-secret : random_password.nuxeo_secret.result
    auto-start : var.auto_start
    npd-branch : var.npd_branch
    db-host : google_sql_database_instance.nuxeo_db.public_ip_address
    db-port : "5432"
    db-name : var.db_name
    db-user : var.db_user
    db-password : random_password.db_password.result
    startup-script : file("./files/setup-nuxeo.sh")
  }
  tags = ["http-server", "https-server"]

  labels = {
    "nuxeo-keep-alive" : var.nuxeo_keep_alive
    "dns-name" : local.dns_name
  }

  boot_disk {
    initialize_params {
      image = "nuxeo-presales-ubuntu-24-04-20240717020314"
    }
  }

  network_interface {
    network = "nuxeo-demo-instances"
    access_config {
      nat_ip = google_compute_address.nuxeo_ip.address
    }
  }
}

resource "google_dns_record_set" "nuxeo_instance_dns_record" {
  managed_zone = "gcp"
  name         = "${local.dns_name}.gcp.cloud.nuxeo.com."
  type         = "A"
  rrdatas      = [google_compute_address.nuxeo_ip.address]
  ttl          = 300
}

# Nuxeo Enhanced Viewer Resources
module "nev" {
  count            = var.with_nev ? 1 : 0
  source           = "./modules/nev"
  nev_version      = "${var.nev_version}"
  stack_name       = "${var.stack_name}-nev"
  dns_name         = "${local.dns_name}-nev"
  nuxeo_url        = "https://${local.dns_name}.gcp.cloud.nuxeo.com"
  nuxeo_secret     = random_password.nuxeo_secret.result
  nuxeo_keep_alive = "${var.nuxeo_keep_alive}"
  nev_zone         = "${var.nuxeo_zone}"
}

# Outputs

output "gcp_project" {
  description = "GCP project hosting the stack"
  value       = var.gcp_project
}

output "nuxeo_url" {
  description = "URL of the Nuxeo instance"
  value       = "https://${local.dns_name}.gcp.cloud.nuxeo.com/nuxeo"
}

output "nuxeo_instance_ip" {
  description = "Static external IP of the Compute Engine instance"
  value       = google_compute_address.nuxeo_ip.address
}

output "cloud_sql_instance" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.nuxeo_db.name
}

output "cloud_sql_public_ip" {
  description = "Public IP of the Cloud SQL instance"
  value       = google_sql_database_instance.nuxeo_db.public_ip_address
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name (project:region:instance)"
  value       = google_sql_database_instance.nuxeo_db.connection_name
}

output "cloud_sql_database" {
  description = "Name of the Nuxeo database"
  value       = google_sql_database.nuxeo_db_schema.name
}

output "cloud_sql_user" {
  description = "Name of the Nuxeo database role"
  value       = google_sql_user.nuxeo_db_user.name
}

output "cloud_sql_password" {
  description = "Password of the Nuxeo database role"
  value       = random_password.db_password.result
  sensitive   = true
}

output "cloud_sql_auto_shutdown" {
  description = "Whether the scheduled-shutdown Cloud Function may stop the Cloud SQL instance"
  value       = var.db_auto_shutdown
}
