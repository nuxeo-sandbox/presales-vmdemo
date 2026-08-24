# Description

CloudFormation templates that provision the Nuxeo Presales demo stacks. Instances launch from the AMI built by the packer template at [vm-image-builder](../../_common/vm-image-builder/README.md).

# Things to know

- AMI IDs are hard-coded per region. Each template carries an `AWSRegionArch2AMI` mapping listing a specific AMI ID for every supported region. Whenever a new image is built via [vm-image-builder](../../_common/vm-image-builder/README.md), these mappings must be updated with the new AMI IDs in both templates, or new stacks will keep launching from the old image.

- Networking is hard-coded per region. The templates also pin the VPC, subnet, and security group for each region (`AWSRegionSubnet`). A template will only work in a region that has an entry here and where that presales networking actually exists; adding a new region means adding the AMI and the networking entries.

- Branch determines the Nuxeo version. The `master` branch targets the current LTS. To deploy a different version, use the corresponding branch rather than editing the template.

- The Nuxeo template can optionally create a NEV stack too. The standalone NEV template is only needed when provisioning NEV on its own.

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
