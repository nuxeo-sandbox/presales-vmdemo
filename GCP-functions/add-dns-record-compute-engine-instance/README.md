# Description

A GCP cloud function to automatically add DNS records when an compute instance goes online

# Installation

Install [terraform CLI](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer.

Install tooling:

```bash
git clone -b gcp https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/GCP-functions/add-dns-record-compute-engine-instance
terraform init
terraform apply
```

# Destroy Resources

```bash
terraform apply --destroy
```

# Dev
## Test locally

Install `npm-watch`:

```bash
npm install -g npm-watch
```

Start the npm server:

```bash
cd src
npm install
npm-watch start
```

The local server supports hotreload when modifications are made to the function source.

To test the function, send an http request to the local npm server with the test payload

```bash
curl localhost:8080 \
 -X POST \
 -H "Content-Type: application/json" \
 -H "ce-type: google.cloud.pubsub.topic.v1.messagePublished" \
 -d '{
    "protoPayload": {
      "serviceName": "compute.googleapis.com",
      "methodName": "v1.compute.instances.start"
    },
    "resource": {
     "type": "gce_instance",
     "labels":{
      "instance_id": "22880703951",
      "zone": "us-central1-a",
      "project_id": "nuxeo-presales-apis"
     }
    }
  }'
```

## Deploy changes

```bash
terraform apply
```

## Run on GCP

Once deployed, a function run can be triggered manually

```bash
gcloud functions call add-dns-record-gce --data '{
    "protoPayload": {
      "serviceName": "compute.googleapis.com",
      "methodName": "v1.compute.instances.start"
    },
    "resource": {
     "type": "gce_instance",
     "labels": {
      "instance_id": "228807926809951",
      "zone": "us-central1-a",
      "project_id": "nuxeo-presales-apis"
     }
    }
  }'
```

The function run logs can be accessed with

```bash
gcloud functions logs read add-dns-record-gce --gen2
```

# About Nuxeo

[Hyland](https://www.hyland.com), developer of the leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). [Nuxeo](https://www.hyland.com/en/products/nuxeo-platform) is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business. Founded in 2008, the company is based in New York with offices across the United States, Europe, and Asia.

Learn more at [https://www.hyland.com/en/products/nuxeo-platform](https://www.hyland.com/en/products/nuxeo-platform).