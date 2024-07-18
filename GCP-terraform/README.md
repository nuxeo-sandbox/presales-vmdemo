# Description

[terraform](https://developer.hashicorp.com/terraform) template to automate the creation of a Nuxeo demo instance on GCP

# How to build

[install terraform](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli)

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer

```
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd GCP-terraform
terraform init
terraform plan -var="stack_name=<my stack name>" -var="nx_studio=<my studio project>"
terraform apply -var="stack_name=<my stack name>" -var="nx_studio=<my studio project>"
```

# How to destroy resources

```
terraform apply -var="stack_name=<my stack name>" -var="nx_studio=<my studio project>" --destroy
```

# About Nuxeo
[Nuxeo](www.hyland.com/en/products/nuxeo-platform), developer of the leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business. Founded in 2008, the company is based in New York with offices across the United States, Europe, and Asia.

Learn more at www.hyland.com/en/products/nuxeo-platform.


