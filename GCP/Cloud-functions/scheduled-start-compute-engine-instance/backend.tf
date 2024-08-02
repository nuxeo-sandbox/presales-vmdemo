terraform {
  backend "gcs" {
    bucket  = "nuxeo-stacks-terraform-state-backend"
    prefix  = "terraform/functions/scheduled-start-compute-engine-instance/state"
  }
}