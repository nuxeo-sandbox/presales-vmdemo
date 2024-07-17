# Create a VM instance from the nuxeo image

# [START compute_instances_create]
resource "google_compute_instance" "nuxeo-instance" {
  project      = "nuxeo-presales-apis"
  name         = "my-demo-instance"
  machine_type = "e2-standard-2"
  zone         = "us-central1-a"
  metadata = {
    enable-oslogin : "TRUE"
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
# [END compute_instances_create]