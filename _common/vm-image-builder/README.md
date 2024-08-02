## Description

[packer](https://developer.hashicorp.com/packer) template to automate the creation of AMI images with all the required packages pre-installed

## How to build

[install packer](https://developer.hashicorp.com/packer/install)

### AWS

For Hyland team members, use `aws sso login --profile <AWS_PROFILE>` to set/refresh the AWS credentials on your computer

```
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/_common/vm-image-builder
packer init .\aws-ami.pkr.hcl
packer build -var 'profile=<AWS_PROFILE>' .\aws-ami.pkr.hcl
```

- update `AWS-CF-templates/Nuxeo.template` with the new AMI ID for each region

### GCP

For Hyland team members, use ` gcloud auth application-default login` to set/refresh the GCP credentials on your computer

```
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/_common/vm-image-builder
packer init .\gcp-image.pkr.hcl
packer build .\gcp-image.pkr.hcl
```

- update `GCP-terraform/main.tf` with the new image name

## About Nuxeo
[Nuxeo](www.hyland.com/en/products/nuxeo-platform), developer of the leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business. Founded in 2008, the company is based in New York with offices across the United States, Europe, and Asia.

Learn more at www.hyland.com/en/products/nuxeo-platform.
