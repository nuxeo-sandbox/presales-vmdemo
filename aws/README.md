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

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
