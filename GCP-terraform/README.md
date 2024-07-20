# Description

Tooling to automate the creation of a Nuxeo demo instance on GCP via [terraform](https://developer.hashicorp.com/terraform).

# Installation

Install [terraform CLI](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer.

Install tooling:

```bash
git clone -b gcp https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/GCP-terraform
terraform init
```

# Create Resources

## Bootstrap

Use the included script to automate the setup:

```bash
./bootstrap.sh
```

You may supply param values via environment vars, e.g.:

```bash
NX_STACK_NAME=my-stack NX_STUDIO_PROJECT=my-studio-project NX_USE_NEV=false NX_DNS_NAME=my-dns-name NX_NEV_VERSION=2023.2.1 ./bootstrap.sh
```

Don't forget to make the script executable if needed:

```bash
chmod u+x bootstrap.sh
```

## Terraform CLI

Deploy using Terraform CLI directly:

```bash
terraform workspace new <stack_name>
terraform apply <params>
```

Possible params are:

Param | Purpose | Default
--- | --- | ---
stack_name | Used for Compute Instance ID | n/a
dns_name | URL e.g. "dns_name.gcp.cloud.nuxeo.com" | stack_name
nx_studio | Nuxeo Studio Project ID | n/a
auto_start | Start Nuxeo stack after instance creation | true
with_nev | Deploy NEV? | false
nev_version | Version of NEV to deploy | 2.3.1


NB: `params` are not required, Terraform will prompt you to enter values, but you must pass them to override anything that has a default value.

Example:

```bash
terraform apply -var="stack_name=my-stack-name" -var="nx_studio=my-studio-project" -var="with_nev=false"
```

# Destroy Resources

Make sure to select the correct Workspace for the resources that you want to destroy. You can run `terraform workspace list` to find the Workspace name.

```bash
terraform workspace select <stack_name>
terraform apply --destroy
```

Note: `terraform apply --destroy` will prompt for variable values, but the values aren't used. You can just press enter or, if the value can't be null, you can enter junk. Cf. https://github.com/hashicorp/terraform/issues/23552 and https://github.com/hashicorp/terraform/pull/29291

# About Nuxeo

[Hyland](https://www.hyland.com), developer of the leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). [Nuxeo](https://www.hyland.com/en/products/nuxeo-platform) is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business. Founded in 2008, the company is based in New York with offices across the United States, Europe, and Asia.

Learn more at [https://www.hyland.com/en/products/nuxeo-platform](https://www.hyland.com/en/products/nuxeo-platform).


