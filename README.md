# Description

Cloud deployment resources used by the Nuxeo Presales Team. These are provided for inspiration and we encourage developers to use them as code samples and learning resources.

# Requirements

* Nuxeo LTS 2025

# Content

## VM image builder
A [packer.io](https://www.packer.io/) template to automate the creation of cloud images with all the required OS packages pre-installed. See the [README](_COMMON/vm-image-builder/README.md) to get more details about how to use it.

## AWS resources
The [aws](aws) folder contains AWS tooling to deploy a demo instance on AWS.

## GCP resources
The [gcp](gcp) folder contains GCP tooling to deploy a demo instance on GCP.

# Quick Links
- [Create an AWS demo instance](aws/cf-templates/Nuxeo.template)
- [Create a GCP demo instance](gcp/terraform/README.md)
- [Build a new instance image](_common/vm-image-builder/README.md)

# Support

**These features are not part of the Nuxeo Production platform.**

These solutions are provided for inspiration and we encourage customers to use them as code samples and learning resources.

This is a moving project (no API maintenance, no deprecation process, etc.) If any of these solutions are found to be useful for the Nuxeo Platform in general, they will be integrated directly into platform, not maintained here.

# License

[Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html)

# About Nuxeo

More information is available at [https://www.hyland.com/en/solutions/products/nuxeo-platform](https://www.hyland.com/en/solutions/products/nuxeo-platform).
