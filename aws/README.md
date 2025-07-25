# Description
AWS resources used by the Nuxeo Presales Team. These are provided for inspiration and we encourage developers to use them as code samples and learning resources.

Note: The master branch currently deploys Nuxeo LTS 2023. To deploy Nuxeo LTS 2021, please use the [lts2021](https://github.com/nuxeo-sandbox/presales-vmdemo/tree/lts2021) branch.

# Content

## CF-templates
Contains a [template](cf-templates/Nuxeo.template) to provision a Nuxeo demo stack, and a [template](cf-templates/NEV.template) to provision an NEV stack.
These templates use the AMI built with the packer template at [vm-image-builder](../_COMMON/vm-image-builder/README.md).

## EC2-instance-Connect-Tools
Helpful stuff for working on localhost, including:
* [Scripts](ec2-instance-connect-tools/helper-scripts/unix/) to start and stop an instance using the EC2 Name, dnsName, or host (more convenient than Instance IDs)
* A [script](ec2-instance-connect-tools/helper-scripts/unix/nxpssh.sh) to connect to an instance, and/or scp files, using the EC2 Name, dnsName, or host (more convenient than Instance IDs)
* [Tooling](ec2-instance-connect-tools/ssh-config) to allow `scp` to function when connecting via EC2 Instance Connect Endpoints

## EC2-scripts
Scripts that are executed when a new EC2 instance is launched using the CF template.

## Lambda
Lambda functions used to automate various tasks including:
* Automatic shutdown of instances
* Automatic start of instances
* Automatic update of Route53 records when instances are started or stopped

See dedicated READMEs for each function in  [Lambda](lambda)

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.

Learn more at https://www.hyland.com/products/nuxeo-platform.
