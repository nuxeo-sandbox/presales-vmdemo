# Description

Tooling to automate the creation of a Nuxeo demo instance on GCP via [Terraform](https://developer.hashicorp.com/terraform).

# Installation

Install [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer.

Install tooling:

> [!IMPORTANT]
> When ready to merge with master, remove the branch info

```bash
git clone -b gcp https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/GCP/Demo-stack
terraform init
```

# Create Resources

You can use the bootstrap script to automate resource creation, or handle it manually using the Terraform CLI. Note that in either case we use [Workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces) to separate our instances.

## Bootstrap Script

Use the included script to automate the setup:

```bash
./bootstrap.sh
```

The script will prompt for all needed values, but you may also supply param values via environment vars, e.g.:

```bash
NX_STACK_NAME=my-stack NX_STUDIO_PROJECT=my-studio-project NX_USE_NEV=false NX_DNS_NAME=my-dns-name NX_NEV_VERSION=2023.2.1 ./bootstrap.sh
```

Available variables:

Var | Purpose | Default
--- | --- | ---
NX_STACK_NAME | Used for Compute Instance ID | n/a
NX_DNS_NAME | URL i.e. `NX_DNS_NAME.gcp.cloud.nuxeo.com` | NX_STACK_NAME
NX_NUXEO_VERSION | Nuxeo Docker image version | 2023
NX_STUDIO_PROJECT | Nuxeo Studio Project ID | n/a
NX_ZONE | Deployment zone | us-central1-a
NX_MACHINE_TYPE | Compute Engine instance type | e2-standard-2
NX_AUTO_START | Start Nuxeo stack after instance creation | true
NX_USE_NEV | Deploy NEV? | false
NX_NEV_VERSION | Version of NEV to deploy | 2023.2.1
NX_KEEP_ALIVE | Control auto shutdown | 20h00m
NX_CUSTOMER | Prospect company name or 'generic' | n/a

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
nuxeo_version | Nuxeo Docker image version | 2023
nx_studio | Nuxeo Studio Project ID | n/a
nuxeo_zone | Deployment zone | us-central1-a
machine_type | Compute Engine instance type | e2-standard-2
auto_start | Start Nuxeo stack after instance creation | true
with_nev | Deploy NEV? | false
nev_version | Version of NEV to deploy | 2023.2.1
nuxeo_keep_alive | Control auto shutdown | 20h00m
customer | Prospect company name or 'generic' | n/a

NB: params are not required. Terraform will prompt you to enter values as needed, but if you want to override any default values you must pass the new value, Terraform won't prompt for values that have a default.

Example:

```bash
terraform apply -var="stack_name=my-stack-name" -var="nx_studio=my-studio-project" -var="with_nev=false"
```

# Destroy Resources

Make sure to select the correct Workspace for the resources that you want to destroy. You can run `terraform workspace list` to find the Workspace name.

```bash
terraform workspace select <stack_name>
```

## Script

Use the included script to automate the deletion:

```bash
./destroy.sh
```

Don't forget to make the script executable if needed:

```bash
chmod u+x destroy.sh
```

## Terraform CLI

You can do it manually as well. You *must* specify the stack name when running `terraform apply --destroy`. You can parameterize it like so:

```bash
terraform apply --destroy -var="stack_name=my-stack-name"
```

Note: `terraform apply --destroy` will prompt for any variable values that don't have a default. Other than the stack name, you can just press enter or, if the value can't be null, you can enter junk. Cf. https://github.com/hashicorp/terraform/issues/23552 and https://github.com/hashicorp/terraform/pull/29291

If you're done with this project, delete the Workspace:

```bash
terraform workspace select default # You have to switch to a different Workspace before you delete
terraform workspace delete <stack_name>
```

# About Nuxeo

[Hyland](https://www.hyland.com), developer of the leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). [Nuxeo](https://www.hyland.com/en/products/nuxeo-platform) is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business. Founded in 2008, the company is based in New York with offices across the United States, Europe, and Asia.

Learn more at [https://www.hyland.com/en/products/nuxeo-platform](https://www.hyland.com/en/products/nuxeo-platform).


