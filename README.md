# Description

Cloud deployment resources used by the Nuxeo Presales Team. These are provided for inspiration and we encourage developers to use them as code samples and learning resources.

# Requirements

* Nuxeo LTS 2025

# Content

## VM image builder
A [packer.io](https://www.packer.io/) template to automate the creation of cloud images with all the required OS packages pre-installed. See the [README](_COMMON/vm-image-builder/README.md) to get more details about how to use it.

## AWS resources
[AWS](aws/README.md) contains AWS CLoud Formation templates and scripts to deploy a demo instance on AWS.
The folder also contains Lambda functions to automatically update DNS records and schedule instances uptime.

## GCP resources
[GCP](gcp/README.md) contains terraform templates and scripts to deploy a demo instance on GCP.
The folder also contains Cloud Functions to automatically update DNS records and schedule instances uptime.

# Quick Links
- [Create an AWS demo instance](aws/cf-templates/Nuxeo.template)
- [Create a GCP demo instance](gcp/terraform/README.md)
- [Build a new instance image](_common/vm-image-builder/README.md)

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
