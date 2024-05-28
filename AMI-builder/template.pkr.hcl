packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "profile" {
  type = string
  default = "default"
}

data "amazon-ami" "ubuntu" {
  profile = var.profile
  filters = {
    architecture        = "x86_64"
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-east-1"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "amazon-ebs" "nuxeo" {
  profile = var.profile
  ami_name      = "nuxeo-presales-ubuntu-22-04-${local.timestamp}"
  ami_regions   = ["us-west-1", "us-west-2", "eu-west-1", "ap-northeast-1", "sa-east-1"]
  instance_type = "t3.large"
  region        = "us-east-1"
  source_ami    = "${data.amazon-ami.ubuntu.id}"
  ssh_username  = "ubuntu"
  subnet_id     = "subnet-0d192be7ed6d2faa2"
  tags = {
    Name                = "nuxeo-presales-ubuntu-22-04"
    billing-category    = "presales"
    billing-subcategory = "generic"
  }
  vpc_id = "vpc-01311a6a321841d60"
}

build {
  sources = ["source.amazon-ebs.nuxeo"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
    script          = "./setup.sh"
  }

}
