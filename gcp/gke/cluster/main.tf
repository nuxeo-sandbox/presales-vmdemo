# Create Nuxeo stack on GCP using Terraform.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}

variable "gcp_project" {
  type        = string
  description = "The"
  default     = "nuxeo-presales-apis"
}

variable "customer" {
  type        = string
  description = "Prospect company name or 'generic'"
  default     = "generic"
}

variable "cluster_name" {
  type        = string
  description = "cluster name"
}

variable "nuxeo_zone" {
  type        = string
  description = "Deployment zone"
  default     = "us-central1"
}

variable "ksa_name" {
  type        = string
  description = "Name of the Kubernetes service account that will be accessing the DNS Zones"
  default     = "external-dns"
}

variable "kns_name" {
  type        = string
  description = "Name of the Kubernetes Namespace"
  default     = "external-dns"
}

provider "google" {
  project = var.gcp_project
  region  = var.nuxeo_zone
  default_labels = {
    billing-category    = "presales"
    billing-subcategory = var.customer
  }
}

data "google_project" "project" {
}

data "google_compute_network" "nuxeo_vpc" {
  name = "nuxeo-demo-instances"
}

data "google_compute_subnetwork" "nuxeo_subnet" {
  name = "nuxeo-demo-instances"
}

resource "google_service_account" "service_account" {
  account_id   = "gke-${var.cluster_name}-sa"
  display_name = "Service Account for the ${var.cluster_name} gke cluster"
}

locals {
  member = "principal://iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${var.gcp_project}.svc.id.goog/subject/ns/${var.kns_name}/sa/${var.ksa_name}"
}

resource "google_project_iam_member" "external_dns_as_project_member" {
  member  = local.member
  project = var.gcp_project
  role    = "roles/dns.reader"
}

resource "google_dns_managed_zone_iam_member" "workload_identity_as_dns_admin" {
  managed_zone = "gcp"
  role         = "roles/dns.admin"
  member       = local.member
}

# WARNING: This will grant access to modify the Cloud DNS zone records for all containers running on cluster, not just ExternalDNS, so use this option with caution. This is not recommended for production environments.
# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/gke.md#worker-node-service-account-method
resource "google_dns_managed_zone_iam_member" "gke_sa_as_dns_admin" {
  managed_zone = "gcp"
  role         = "roles/dns.admin"
  member       = google_service_account.service_account.email
}

# GKE cluster
resource "google_container_cluster" "gke-cluster" {
  name       = var.cluster_name
  network    = data.google_compute_network.nuxeo_vpc.name
  subnetwork = data.google_compute_subnetwork.nuxeo_subnet.name

  deletion_protection = false

  # Enabling Autopilot for this cluster
  enable_autopilot = true

  workload_identity_config {
    workload_pool = "${var.gcp_project}.svc.id.goog"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
      service_account = google_service_account.service_account.email
      oauth_scopes = [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring",
        "https://www.googleapis.com/auth/service.management.readonly",
        "https://www.googleapis.com/auth/servicecontrol",
        "https://www.googleapis.com/auth/trace.append",
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }
}
