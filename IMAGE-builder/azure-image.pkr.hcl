packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 1"
    }
  }
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "azure-arm" "nuxeo" {
  azure_tags = {
    dept = "Engineering"
    task = "Image deployment"
  }
#  client_id                         = ""
#  client_secret                     = ""
  image_offer                       = "ubuntu-24_04-lts"
  image_publisher                   = "Canonical"
  image_sku                         = "24.04.202407160"
  location                          = "East US"
  managed_image_name                = "nuxeo-presales-ubuntu-24-04-${local.timestamp}"
  managed_image_resource_group_name = "hyl-rg-nuxeo-presales-usea"
  os_type                           = "Linux"
#  subscription_id                   = ""
#  tenant_id                         = ""
  vm_size                           = "Standard_DS2_v2"
}

build {
  sources = ["sources.azure-arm.nuxeo"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts          = ["./scripts/common.sh"]
  }

}