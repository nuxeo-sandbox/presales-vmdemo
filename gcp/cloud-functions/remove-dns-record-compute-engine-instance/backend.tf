terraform {
  backend "gcs" {
    bucket  = "nuxeo-stacks-terraform-state-backend"
    prefix  = "terraform/functions/remove-dns-record-compute-engine-instance/state"
  }
}