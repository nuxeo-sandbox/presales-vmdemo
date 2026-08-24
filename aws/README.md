# Description

AWS resources used by the Nuxeo Presales Team. These are provided for inspiration and we encourage developers to use them as code samples and learning resources.

Note: The master branch currently deploys Nuxeo LTS 2025. To deploy other versions please use the appropriate branch.

# Content

## cf-templates
CloudFormation templates that provision the demo infrastructure, launching instances from the AMI built by the packer template at [vm-image-builder](../_common/vm-image-builder/README.md).

## ec2-instance-connect-tools
Tooling for interacting with demo servers (ssh, scp, start and stop, etc.).

## ec2-scripts
Provisioning scripts that run automatically when a new instance is launched.

## lambda
Serverless automation for the demo fleet (e.g. automatically stop instances, automatic Route53 updates, etc.)

## ssm
AWS Systems Manager documents for maintaining and remediating existing instances.

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.

Learn more at https://www.hyland.com/products/nuxeo-platform.
