# Create a VM instance from the nuxeo image

variable "stack_name" {
  type        = string
  description = "The name of the demo stack"
}

resource "google_compute_instance" "nuxeo_instance" {
  project      = "nuxeo-presales-apis"
  name         = "${var.stack_name}-instance"
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
    startup-script: file("./NuxeoInit.sh")
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
