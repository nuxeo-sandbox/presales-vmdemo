terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  skip_provider_registration = true # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}

data "azurerm_subscription" "current" {
}

data "azurerm_resource_group" "nuxeo_rg" {
  name     = "hyl-rg-nuxeo-presales-usea"
}

data "azurerm_virtual_network" "nuxeo_vnet" {
  name                = "hyl-vnet-nuxeo-presales-usea"
  resource_group_name = data.azurerm_resource_group.nuxeo_rg.name
}

#permission issue
#data "azurerm_subnet" "nxueo_subnet" {
#  name                 = data.azurerm_virtual_network.nuxeo_vnet.subnets[0]
#  virtual_network_name = data.azurerm_virtual_network.nuxeo_vnet.name
#  resource_group_name  = data.azurerm_resource_group.nuxeo_rg.name
#}

resource "azurerm_public_ip" "instance_ip" {
  name                = "instance_ip"
  resource_group_name = data.azurerm_resource_group.nuxeo_rg.name
  location            = data.azurerm_resource_group.nuxeo_rg.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "instance" {
  name                = "test-tf-nuxeo"
  resource_group_name = data.azurerm_resource_group.nuxeo_rg.name
  location            = data.azurerm_resource_group.nuxeo_rg.location

  ip_configuration {
    #permission issue
    #subnet_id = data.azurerm_subnet.nxueo_subnet.id
    #workaround => build the id manually
    subnet_id = "${data.azurerm_subscription.current.id}/resourceGroups/${data.azurerm_resource_group.nuxeo_rg.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.nuxeo_vnet.name}/subnets/${data.azurerm_virtual_network.nuxeo_vnet.subnets[0]}"
    name                          = "internal"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.instance_ip.id
  }
}

data "azurerm_ssh_public_key" "sshkey" {
  name                = ""
  resource_group_name = data.azurerm_resource_group.nuxeo_rg.name
}

resource "azurerm_linux_virtual_machine" "example" {
  name                = "example-machine"
  resource_group_name = data.azurerm_resource_group.nuxeo_rg.name
  location            = data.azurerm_resource_group.nuxeo_rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.instance.id
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = data.azurerm_ssh_public_key.sshkey.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}