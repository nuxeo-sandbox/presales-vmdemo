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
  default = "add-dns-record-gce"
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
  display_name = "Service Account to add compute instance DNS records"
}

resource "google_project_iam_member" "event_receiver_iam" {
  project      = "nuxeo-presales-apis"
  role         = "roles/eventarc.eventReceiver"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "compute_viewer_iam" {
  project      = "nuxeo-presales-apis"
  role         = "roles/compute.viewer"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_dns_managed_zone_iam_member" "dns_admin_iam" {
  project      = "nuxeo-presales-apis"
  managed_zone = "gcp"
  role = "roles/dns.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloudfunctions2_function" "default" {
  name        = var.function_name
  project      = "nuxeo-presales-apis"
  location    = "us-central1"
  description = "A function to remove DNS records for compute instances that are going offline"
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

resource "google_cloud_run_service_iam_member" "member" {
  project      = "nuxeo-presales-apis"
  location = google_cloudfunctions2_function.default.location
  service  = google_cloudfunctions2_function.default.service_config[0].service
  role = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_eventarc_trigger" "trigger" {
  depends_on = [google_project_iam_member.event_receiver_iam]
  project      = "nuxeo-presales-apis"
  name = "${var.function_name}-trigger"
  service_account = google_service_account.service_account.email
  location = "us-central1"
  matching_criteria {
    attribute = "type"
    value = "google.cloud.audit.log.v1.written"
  }
  matching_criteria {
    attribute = "serviceName"
    value = "compute.googleapis.com"
  }
  matching_criteria {
    attribute = "methodName"
    value = "v1.compute.instances.start"
  }
  destination {
    cloud_run_service {
      path = "/"
      region = "us-central1"
      service = google_cloudfunctions2_function.default.service_config[0].service
    }
  }
}