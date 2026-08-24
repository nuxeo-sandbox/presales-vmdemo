## Description

[packer](https://developer.hashicorp.com/packer) template to automate the creation of AMI images with all the required packages pre-installed

## How to build

[install packer](https://developer.hashicorp.com/packer/install)

### AWS

For Hyland team members, make sure to set/refresh your AWS credentials e.g. `aws sso login`.

```
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/_common/vm-image-builder
packer init aws-ami.pkr.hcl
packer build aws-ami.pkr.hcl
```

- update `aws/cf-templates/Nuxeo.template` with the new AMI ID for each region
- update `aws/cf-templates/NEV.template` with the new AMI ID for each region

### GCP

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer

```
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/_common/vm-image-builder
packer init gcp-image.pkr.hcl
packer build gcp-image.pkr.hcl
```

- update `GCP-terraform/main.tf` with the new image name
- update `GCP-terraform/modules/nev.tf` with the new image name

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
