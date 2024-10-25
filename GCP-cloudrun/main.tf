terraform {
  required_version = ">= 1.9"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {
  registry_auth {
    address = "us-central1-docker.pkg.dev"
    config_file = pathexpand("~/.docker/config.json")
  }
}

data "google_artifact_registry_repository" "nuxeo_artifacts" {
  project       = "nuxeo-presales-apis"
  location      = "us-central1"
  repository_id = "nuxeo-artifacts"
}

resource "docker_image" "nuxeo_custom" {
  name = "us-central1-docker.pkg.dev/nuxeo-presales-apis/${data.google_artifact_registry_repository.nuxeo_artifacts.repository_id}/nuxeo-custom:latest"
  build {
    platform   = "linux/amd64"
    context    = "testbuild"
    dockerfile = "Dockerfile"
  }
}

resource "docker_registry_image" "nuxeo_custom_remote" {
  name = docker_image.nuxeo_custom.name
}

resource "google_cloud_run_v2_service" "nuxeo_test" {
  project  = "nuxeo-presales-apis"
  name     = "nuxeo-test"
  location = "us-central1"
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = docker_registry_image.nuxeo_custom_remote.name
      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }
    }
  }
}

resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
  project               = "nuxeo-presales-apis"
  name                  = "nuxeo-test-neg"
  network_endpoint_type = "SERVERLESS"
  region                = "us-central1"
  cloud_run {
    service = google_cloud_run_v2_service.nuxeo_test.name
  }
}

module "lb-http" {
  source            = "GoogleCloudPlatform/lb-http/google//modules/serverless_negs"
  version           = "~> 9.0"

  project = "nuxeo-presales-apis"
  name    = "nuxeo-test"

  ssl                             = false
  managed_ssl_certificate_domains = []
  https_redirect                  = false
  backends = {
    default = {
      description            = null
      enable_cdn             = false
      custom_request_headers = null

      log_config = {
        enable      = true
        sample_rate = 1.0
      }

      groups = [
        {
          group = google_compute_region_network_endpoint_group.cloudrun_neg.id
        }
      ]

      iap_config = {
        enable               = false
        oauth2_client_id     = null
        oauth2_client_secret = null
      }
      security_policy = null
    }
  }
}

output "url" {
  value = "http://${module.lb-http.external_ip}"
}