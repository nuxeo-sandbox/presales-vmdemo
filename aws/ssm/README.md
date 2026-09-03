# Description

AWS Systems Manager documents for maintaining and remediating existing demo instances (as opposed to the CloudFormation templates, which only run at launch time).

# Documents

- `pin-lts-kernel.ssm.yaml` - Temporary workaround. Pins Ubuntu 24.04 hosts to the 6.8 GA-LTS kernel so MongoDB 8.0.x keeps working, without freezing kernel security updates. It downloads and runs the same pin script used by the AMI build, so new and existing instances stay consistent, and can be enforced continuously via a State Manager association. This is the "existing instances" half of the MongoDB kernel workaround and should be removed once the upstream issue ([MongoDB SERVER-131779](https://jira.mongodb.org/browse/SERVER-131779)) is fixed.

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
