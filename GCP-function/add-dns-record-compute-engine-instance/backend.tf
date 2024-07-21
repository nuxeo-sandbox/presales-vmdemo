terraform {
  backend "gcs" {
    bucket  = "nuxeo-stacks-terraform-state-backend"
    prefix  = "terraform/functions/add-dns-record-compute-engine-instance/state"
  }
}