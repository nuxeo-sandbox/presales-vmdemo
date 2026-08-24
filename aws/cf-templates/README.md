# Description

CloudFormation templates that provision the Nuxeo Presales demo stacks. Instances launch from the AMI built by the packer template at [vm-image-builder](../../_common/vm-image-builder/README.md).

# Things to know

- AMI IDs are hard-coded per region. Each template carries an `AWSRegionArch2AMI` mapping listing a specific AMI ID for every supported region. Whenever a new image is built via [vm-image-builder](../../_common/vm-image-builder/README.md), these mappings must be updated with the new AMI IDs in both templates, or new stacks will keep launching from the old image.

- Networking is hard-coded per region. The templates also pin the VPC, subnet, and security group for each region (`AWSRegionSubnet`). A template will only work in a region that has an entry here and where that presales networking actually exists; adding a new region means adding the AMI and the networking entries.

- Branch determines the Nuxeo version. The `master` branch targets the current LTS. To deploy a different version, use the corresponding branch rather than editing the template.

- The Nuxeo template can optionally create a NEV stack too. The standalone NEV template is only needed when provisioning NEV on its own.

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.

Learn more at https://www.hyland.com/products/nuxeo-platform.
