# Description

AWS Systems Manager documents for maintaining and remediating existing demo instances (as opposed to the CloudFormation templates, which only run at launch time).

# Documents

- `pin-lts-kernel.ssm.yaml` — Temporary workaround. Pins Ubuntu 24.04 hosts to the 6.8 GA-LTS kernel so MongoDB 8.0.x keeps working, without freezing kernel security updates. It downloads and runs the same pin script used by the AMI build, so new and existing instances stay consistent, and can be enforced continuously via a State Manager association. This is the "existing instances" half of the MongoDB kernel workaround and should be removed once the upstream issue ([MongoDB SERVER-131779](https://jira.mongodb.org/browse/SERVER-131779)) is fixed.

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.

Learn more at https://www.hyland.com/products/nuxeo-platform.
