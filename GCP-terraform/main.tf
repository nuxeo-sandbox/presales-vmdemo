# Create a VM instance from the nuxeo image

variable "stack_name" {
  type        = string
  description = "The name of the demo stack"
}

resource "google_compute_instance" "nuxeoinstance" {
  project      = "nuxeo-presales-apis"
  name         = "${var.stack_name}-instance"
  machine_type = "e2-standard-2"
  zone         = "us-central1-a"
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
