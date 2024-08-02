terraform {
  backend "gcs" {
    bucket  = "nuxeo-stacks-terraform-state-backend"
    prefix  = "terraform/functions/scheduled-shutdown-compute-engine-instance/state"
  }
}