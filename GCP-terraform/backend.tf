terraform {
  backend "gcs" {
    bucket  = "nuxeo-demo-shared-bucket-us"
    prefix  = "terraform/state"
  }
}