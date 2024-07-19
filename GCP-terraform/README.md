# Description

[terraform](https://developer.hashicorp.com/terraform) template to automate the creation of a Nuxeo demo instance on GCP

# How to init your environment

[install terraform](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli)

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer

```bash
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd GCP-terraform
terraform init
```

# How to deploy a stack

```bash
terraform workspace new <stack_name>
terraform apply -var="stack_name=<my stack name>" -var="nx_studio=<my studio project>" -var="with_nev=false"
```

# How to destroy resources

Make sure to select the correct Workspace for the resources that you want to destroy. You can run `terraform workspace list` to find the Workspace name.

```bash
terraform workspace select <stack_name>
terraform apply --destroy
```

Note: `terraform apply --destroy` will still prompt for variable values but they are not needed; you can enter whatever you want.

# About Nuxeo
[Nuxeo](www.hyland.com/en/products/nuxeo-platform), developer of the leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business. Founded in 2008, the company is based in New York with offices across the United States, Europe, and Asia.

Learn more at www.hyland.com/en/products/nuxeo-platform.


