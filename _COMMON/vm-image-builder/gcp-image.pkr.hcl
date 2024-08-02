packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1"
    }
  }
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "googlecompute" "nuxeo" {
  project_id = "nuxeo-presales-apis"
  source_image = "ubuntu-2404-noble-amd64-v20240711"
  zone = "us-central1-a"
  network = "nuxeo-demo-instances"
  use_internal_ip = true
  omit_external_ip = true
  use_iap = true
  use_os_login = true
  ssh_username = "root"
  image_name= "nuxeo-presales-ubuntu-24-04-${local.timestamp}"
}

build {
  sources = ["sources.googlecompute.nuxeo"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts          = ["./scripts/common.sh", "./scripts/gcp.sh"]
  }

}
