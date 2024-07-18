# Create a VM instance from the nuxeo image

variable "stack_name" {
  type        = string
  description = "The name of the demo stack"
}

variable "nx_studio" {
  type        = string
  description = "The nuxeo studio project to deploy"
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
    nx-studio: var.nx_studio
    auto-start: "true"
    startup-script: file("./NuxeoInit.sh")
  }
  tags = ["http-server","https-server"]

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
  name         = "${var.stack_name}.gcp.cloud.nuxeo.com."
  type         = "A"
  rrdatas      = ["${google_compute_instance.nuxeo_instance.network_interface.0.access_config.0.nat_ip}"]
  ttl          = 300
}
