# Description
Cloud deployment resources used by the Nuxeo Presales Team. These are provided for inspiration and we encourage developers to use them as code samples and learning resources.

Note: The master branch currently deploys Nuxeo LTS 2023. To deploy Nuxeo LTS 2021, please use the [lts2021](https://github.com/nuxeo-sandbox/presales-vmdemo/tree/lts2021) branch.

# Content

## VM image builder
A [packer.io](https://www.packer.io/) template to automate the creation of cloud images with all the required OS packages pre-installed. See the [README](_COMMON/vm-image-builder/README.md) to get more details about how to use it.

## AWS resources
[AWS](AWS/README.md) contains AWS CLoud Formation templates and scripts to deploy a demo instance on AWS.
The folder also contains Lambda functions to automatically update DNS records and schedule instances uptime.


## GCP resources
[GCP](GCP/Demo-stack/README.md) contains terraform templates and scripts to deploy a demo instance on GCP.
The folder also contains Cloud Functions to automatically update DNS records and schedule instances uptime.

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.
Learn more at https://www.hyland.com/products/nuxeo-platform.
