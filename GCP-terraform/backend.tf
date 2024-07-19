terraform {
  backend "gcs" {
    bucket  = "nuxeo-stacks-terraform-state-backend"
    prefix  = "terraform/state"
  }
}