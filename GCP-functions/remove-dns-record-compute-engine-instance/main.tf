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
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.5.0"
    }
  }
}

variable "gcp_project" {
  type        = string
  description = "GCP project name"
  default     = "nuxeo-presales-apis"
}

variable "function_name" {
  type    = string
  default = "remove-dns-record-gce"
}

provider "google" {
  project = var.gcp_project
  default_labels = {
    billing-category    = "presales"
    billing-subcategory = "generic"
  }
}

data "google_project" "project" {}

data "archive_file" "zip" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  source {
    content = file("./src/index.js")
    filename = "index.js"
  }
  source {
    content = file("./src/package.json")
    filename = "package.json"
  }
}

resource "google_storage_bucket_object" "object" {
  name   = "${var.function_name}/source-${data.archive_file.zip.output_md5}.zip"
  bucket = "gcf-v2-uploads-1007087250969-us-central1"
  source = data.archive_file.zip.output_path # Add path to the zipped function source code
}


resource "google_service_account" "service_account" {
  account_id   = "fn-${var.function_name}-sa"
  display_name = "Service Account to add compute instance DNS records"
}

resource "google_project_iam_member" "event_receiver_iam" {
  project = data.google_project.project.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "compute_viewer_iam" {
  project = data.google_project.project.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_dns_managed_zone_iam_member" "dns_admin_iam" {
  managed_zone = "gcp"
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloudfunctions2_function" "default" {
  name        = var.function_name
  location    = "us-central1"
  description = "A function to add DNS records for compute instances that go online"
  build_config {
    runtime     = "nodejs20"
    entry_point = "handlerHttp" # Set the entry point
    source {
      storage_source {
        bucket = google_storage_bucket_object.object.bucket
        object = google_storage_bucket_object.object.name
      }
    }
  }
  service_config {
    max_instance_count    = 1
    available_memory      = "512M"
    timeout_seconds       = 60
    service_account_email = google_service_account.service_account.email
  }
}

resource "google_cloud_run_service_iam_member" "member" {
  location = google_cloudfunctions2_function.default.location
  service  = google_cloudfunctions2_function.default.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_eventarc_trigger" "trigger" {
  depends_on = [google_project_iam_member.event_receiver_iam]
  name            = "${var.function_name}-trigger"
  service_account = google_service_account.service_account.email
  location        = "us-central1"
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }
  matching_criteria {
    attribute = "serviceName"
    value     = "compute.googleapis.com"
  }
  matching_criteria {
    attribute = "methodName"
    value     = "v1.compute.instances.stop"
  }
  destination {
    cloud_run_service {
      path    = "/"
      region  = "us-central1"
      service = google_cloudfunctions2_function.default.service_config[0].service
    }
  }
}