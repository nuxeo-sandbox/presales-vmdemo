# Description

A GCP cloud function to automatically remove DNS records when an compute instance goes offline

# Installation

Install [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).

For Hyland team members, use `gcloud auth application-default login` to set/refresh the GCP credentials on your computer.

Install tooling:

```bash
git clone https://github.com/nuxeo-sandbox/presales-vmdemo
cd presales-vmdemo/gcp/cloud-functions/remove-dns-record-compute-engine-instance
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

To test the function, send a http request to the local npm server with the test payload

```bash
curl localhost:8080 \
 -X POST \
 -H "Content-Type: application/json" \
 -H "ce-type: google.cloud.pubsub.topic.v1.messagePublished" \
 -d '{
    "protoPayload": {
      "serviceName": "compute.googleapis.com",
      "methodName": "v1.compute.instances.stop"
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
gcloud functions call remove-dns-record-gce --data '{
    "protoPayload": {
      "serviceName": "compute.googleapis.com",
      "methodName": "v1.compute.instances.stop"
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
gcloud functions logs read remove-dns-record-gce --gen2
```

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).