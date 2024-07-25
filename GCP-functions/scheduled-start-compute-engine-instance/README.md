# Description

A GCP cloud function to automatically start instances using a [GCP Cloud Scheduler](https://console.cloud.google.com/cloudscheduler)

# Installation

Install [terraform CLI](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer.

Install tooling:

```bash
git clone -b gcp https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/GCP-functions/scheduled-start-compute-engine-instance
terraform init
terraform apply
```

# Destroy Resources

```bash
terraform apply --destroy
```

# Dev
## Test locally
Start the npm server

```bash
cd src
npm-watch start
```

The local server supports hotreload when modifications are made to the function source.

To test the function, send a http request to the local npm server with the test payload

```bash
curl localhost:8080 \
 -X POST \
 -H "Content-Type: application/json" \
 -d '{
      "jobName":"daily-gce-instance-start"
    }'
```

## Deploy changes 

```bash
terraform apply
```

## Run on GCP

Once deployed, a function run can be triggered manually

```bash
gcloud functions call scheduled-shutdown-gce --data '{
    "jobName":"daily-gce-instance-start"
}'
```

The scheduler can also be triggered to test the end-to-end feature

```bash
gcloud scheduler jobs run daily-gce-instance-start  --location=us-central1
```

The function run logs can be accessed with 

```bash
gcloud functions logs read scheduled-start-gce --gen2
```

# About Nuxeo

[Hyland](https://www.hyland.com), developer of the leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). [Nuxeo](https://www.hyland.com/en/products/nuxeo-platform) is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business. Founded in 2008, the company is based in New York with offices across the United States, Europe, and Asia.

Learn more at [https://www.hyland.com/en/products/nuxeo-platform](https://www.hyland.com/en/products/nuxeo-platform).