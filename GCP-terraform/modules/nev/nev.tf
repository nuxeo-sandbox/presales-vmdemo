variable "stack_name" {
  type        = string
  description = "The name of the nev demo stack"
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

variable "nev_version" {
  type        = string
  description = "Version of NEV to deploy."
  default     = "2023.2.1"
}

variable "nuxeo_url" {
  type        = string
  description = "The url of the nuxeo application"
}

variable "nuxeo_secret" {
  type        = string
  description = "The shared secret between nuxeo and nev"
}

variable "nuxeo_keep_alive" {
  type        = string
  description = "Control auto shutdown"
  default     = "20h00m" # 8:00 PM relative to the zone
}

variable "nev_zone" {
  type        = string
  description = "Deployment zone"
  default     = "us-central1-a"
}

resource "google_service_account" "service_account" {
  project      = "nuxeo-presales-apis"
  account_id   = "nxp-${var.stack_name}"
  display_name = "Service Account for the ${var.stack_name} nev instance"
}

data "google_secret_manager_secret" "shared_credentials" {
  project      = "nuxeo-presales-apis"
  secret_id    = "nuxeo-presales-connect"
}

resource "google_secret_manager_secret_iam_member" "shared_credentials_member" {
  project = "nuxeo-presales-apis"
  secret_id = data.google_secret_manager_secret.shared_credentials.id
  role = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_compute_instance" "nev_instance" {
  depends_on = [
    google_secret_manager_secret_iam_member.shared_credentials_member
  ]
  project      = "nuxeo-presales-apis"
  name         = var.stack_name
  machine_type = "e2-standard-2"
  zone         = var.nev_zone
  service_account {
    email = google_service_account.service_account.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  metadata = {
    enable-oslogin : "TRUE"
    stack-name : var.stack_name
    dns-name: local.dns_name
    auto-start: "true"
    nev-version: var.nev_version
    startup-script: file("./files/NevInit.sh")
    nuxeo-url: var.nuxeo_url
    nuxeo-secret: var.nuxeo_secret
  }
  tags = ["http-server","https-server"]

  labels = {
    "nuxeo-keep-alive": var.nuxeo_keep_alive
    "dns-name": local.dns_name
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

resource "google_dns_record_set" "nev_instance_dns_record" {
  project      = "nuxeo-presales-apis"
  managed_zone = "gcp"
  name         = "${local.dns_name}.gcp.cloud.nuxeo.com."
  type         = "A"
  rrdatas      = ["${google_compute_instance.nev_instance.network_interface.0.access_config.0.nat_ip}"]
  ttl          = 300
}