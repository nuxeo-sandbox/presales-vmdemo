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
  default = "nuxeo-presales-apis"
}

variable "function_name" {
  type = string
  default = "scheduled-shutdown-gce"
}

provider "google" {
  project = var.gcp_project
  default_labels = {
    billing-category = "presales"
    billing-subcategory = "generic"
  }
}

data "google_project" "project" {}

data "archive_file" "zip" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  source {
    content  = file("./src/index.js")
    filename = "index.js"
  }
  source {
    content  = file("./src/package.json")
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
  display_name = "Service Account to periodically shutdown compute instance"
}

resource "google_project_iam_member" "compute_viewer_iam" {
  project      = data.google_project.project.project_id
  role         = "roles/compute.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloudfunctions2_function" "default" {
  name        = var.function_name
  location    = "us-central1"
  description = "A function to periodically shutdown compute instances"
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
    max_instance_count = 1
    available_memory   = "512M"
    timeout_seconds    = 60
    service_account_email = google_service_account.service_account.email
  }
}

resource "google_cloud_run_service_iam_member" "invoker_iam" {
  location = google_cloudfunctions2_function.default.location
  service  = google_cloudfunctions2_function.default.service_config[0].service
  role = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloud_scheduler_job" "job" {
  depends_on = [google_cloud_run_service_iam_member.invoker_iam]
  region      = "us-central1"
  name        = "daily-gce-instance-shutdown"
  description = "Job to stop instances depending on their nuxeo-keep-alive label."
  schedule    = "0 * * * *"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.default.url
    body        = base64encode("{\"jobName\":\"daily-gce-instance-shutdown\",\"projectId\":\"nuxeo-presales-apis\"}")
    headers = {
      "Content-Type" = "application/json"
    }
    oidc_token {
      service_account_email = google_service_account.service_account.email
    }
  }
}