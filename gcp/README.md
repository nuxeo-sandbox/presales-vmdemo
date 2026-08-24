# Description
GCP resources used by the Nuxeo Presales Team. These are provided for inspiration and we encourage developers to use them as code samples and learning resources.

# Content

## Demo Stack Tooling
Contains tooling to deploy a full demo stack on GCP. See [README](terraform/README.md) to get started.
This tooling uses the compute image built with the packer template at [vm-image-builder](../_common/vm-image-builder/README.md).

## Cloud Functions
Functions used to automate various tasks including:
* Automatic shutdown of instances
* Automatic start of instances
* Automatic update of DNS records when instances are started or stopped

See dedicated READMEs for each function in  [cloud-functions](cloud-functions)

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
