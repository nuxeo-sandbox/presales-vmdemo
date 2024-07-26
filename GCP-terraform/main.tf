# Create Nuxeo stack on GCP using Terraform.

variable "stack_name" {
  type        = string
  description = "Stack name (used for Compute Instance Name and DNS if not set)."
}

variable "dns_name" {
  type        = string
  description = "DNS name (i.e. dns_name.gcp.cloud.nuxeo.com)."
  default     = ""
}

# DNS name defaults to stack_name if nothing is set
locals {
  dns_name = var.dns_name == "" ? var.stack_name : var.dns_name
}

variable "nx_studio" {
  type        = string
  description = "Nuxeo Studio Poject ID."
}

variable "with_nev" {
  type        = bool
  description = "Deploy NEV? [true|false]"
  default     = false
}

variable "nev_version" {
  type        = string
  description = "Version of NEV to deploy."
  default     = "2.3.1"
}

variable "auto_start" {
  type        = bool
  description = "Automatically start Nuxeo?"
  default     = true
}

variable "nuxeo_keep_alive" {
  type        = string
  description = "Control auto shutdown."
  default     = "20h00m" # 8:00 PM relative to the zone
}

variable "nuxeo_zone" {
  type        = string
  description = "Deployment zone"
  default     = "us-central1-a"
}

variable "machine_type" {
  type        = string
  description = "Compute Engine instance type."
  default     = "e2-standard-2"
}

# Nuxeo Instance resources

resource "random_password" "nuxeo_secret" {
  length           = 64
  special          = true
  override_special = "-"
}

resource "google_service_account" "service_account" {
  project      = "nuxeo-presales-apis"
  account_id   = "${var.stack_name}-nuxeo-instance"
  display_name = "Service Account for the ${var.stack_name} nuxeo instance"
}

data "google_secret_manager_secret" "shared_credentials" {
  project      = "nuxeo-presales-apis"
  secret_id    = "nuxeo-presales-connect"
}

data "google_secret_manager_secret" "instance_credentials" {
  project      = "nuxeo-presales-apis"
  secret_id    = "instance-credentials"
}

resource "google_secret_manager_secret_iam_member" "shared_credentials_member" {
  project = "nuxeo-presales-apis"
  secret_id = data.google_secret_manager_secret.shared_credentials.id
  role = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "instance_credentials_member" {
  project = "nuxeo-presales-apis"
  secret_id = data.google_secret_manager_secret.instance_credentials.id
  role = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

data "google_storage_bucket" "content_bucket" {
  project = "nuxeo-presales-apis"
  name = "nuxeo-demo-shared-bucket-us"
}

resource "google_storage_bucket_iam_member" "member" {
  bucket = data.google_storage_bucket.content_bucket.name
  role = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_compute_instance" "nuxeo_instance" {
  depends_on = [
    google_secret_manager_secret_iam_member.shared_credentials_member,
    google_secret_manager_secret_iam_member.instance_credentials_member,
    google_storage_bucket_iam_member.member
  ]
  project      = "nuxeo-presales-apis"
  name         = var.stack_name
  machine_type = var.machine_type
  zone         = var.nuxeo_zone
  service_account {
    email = google_service_account.service_account.email
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
      "storage-full",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  metadata = {
    enable-oslogin : "TRUE"
    stack-name : var.stack_name
    dns-name: local.dns_name
    nx-studio: var.nx_studio
    with-nev: var.with_nev
    nuxeo-secret: random_password.nuxeo_secret.result
    auto-start: var.auto_start
    startup-script: file("./files/NuxeoInit.sh")
  }
  tags = ["http-server","https-server"]

  labels = {
    "nuxeo-keep-alive": var.nuxeo_keep_alive
  }

  boot_disk {
    initialize_params {
      image = "nuxeo-presales-ubuntu-24-04-20240717020314"
    }
  }

  network_interface {
    network = "nuxeo-demo-instances"
    access_config {}
  }
}

resource "google_dns_record_set" "nuxeo_instance_dns_record" {
  project      = "nuxeo-presales-apis"
  managed_zone = "gcp"
  name         = "${local.dns_name}.gcp.cloud.nuxeo.com."
  type         = "A"
  rrdatas      = ["${google_compute_instance.nuxeo_instance.network_interface.0.access_config.0.nat_ip}"]
  ttl          = 300
}

# Nuxeo Enhanced Viewer Resources
module "nev" {
  count = var.with_nev ? 1 : 0
  source = "./modules/nev"
  nev_version = "${var.nev_version}"
  stack_name = "${var.stack_name}-nev"
  dns_name = "${local.dns_name}-nev"
  nuxeo_url = "https://${local.dns_name}.gcp.cloud.nuxeo.com"
  nuxeo_secret= random_password.nuxeo_secret.result
  nuxeo_keep_alive = "${var.nuxeo_keep_alive}"
  nev_zone = "${var.nuxeo_zone}"
}