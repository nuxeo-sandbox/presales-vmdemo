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
  description = "Nuxeo Studio Poject ID"
}

variable "with_nev" {
  type        = bool
  description = "Deploy NEV? [true|false]"
  default     = false
}

variable "auto_start" {
  type        = bool
  description = "Automatically start Nuxeo?"
  default     = true
}

# Nuxeo Instance resources

resource "random_password" "nuxeo_secret" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}


resource "google_compute_instance" "nuxeo_instance" {
  project      = "nuxeo-presales-apis"
  name         = var.stack_name
  machine_type = "e2-standard-2"
  zone         = "us-central1-a"
  service_account {
    email = "1007087250969-compute@developer.gserviceaccount.com"
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
    "nuxeo-keep-alive": "20h00m"
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
  stack_name = "${var.stack_name}-nev"
  dns_name = "${local.dns_name}-nev"
  nuxeo_url = "https://${local.dns_name}.gcp.cloud.nuxeo.com"
  nuxeo_secret= random_password.nuxeo_secret.result
}