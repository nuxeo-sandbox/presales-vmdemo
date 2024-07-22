terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.34.0"
    }
  }
}

variable "function_name" {
  type = string
  default = "scheduled-shutdown-gce"
}


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
  project      = "nuxeo-presales-apis"
  account_id   = "fn-${var.function_name}-sa"
  display_name = "Service Account to periodically shutdown compute instance"
}

resource "google_project_iam_member" "compute_viewer_iam" {
  project      = "nuxeo-presales-apis"
  role         = "roles/compute.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloudfunctions2_function" "default" {
  name        = var.function_name
  project      = "nuxeo-presales-apis"
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
  project      = "nuxeo-presales-apis"
  location = google_cloudfunctions2_function.default.location
  service  = google_cloudfunctions2_function.default.service_config[0].service
  role = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloud_scheduler_job" "job" {
  depends_on = [google_cloud_run_service_iam_member.invoker_iam]
  project      = "nuxeo-presales-apis"
  region      = "us-central1"
  name        = "daily-gce-instance-shutdown"
  description = "test job"
  schedule    = "0 9 * * *"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.default.url
    body        = base64encode("{\"jobName\":\"daily-gce-instance-shutdown\"}")
    headers = {
      "Content-Type" = "application/json"
    }
    oidc_token {
      service_account_email = google_service_account.service_account.email
    }
  }
}