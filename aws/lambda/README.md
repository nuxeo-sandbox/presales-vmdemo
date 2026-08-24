# Description

Serverless automation for the presales demo fleet. Each subfolder is a self-contained Lambda function; most are deployed with the AWS SAM CLI, and the WorkMail ones via CloudFormation. See the README inside each subfolder for build and deploy details.

# Functions

- `scheduled-ec2-instances-start` — Starts instances on a daily schedule (e.g. Mon–Fri, 06:00 UTC). Only instances whose `startDailyUntil` tag is empty or set to a future ISO date are started.
- `scheduled-ec2-instances-stop` — Stops instances on a schedule.
- `route-53-auto-update` — Keeps Route 53 records in sync, updating an instance's DNS record when it is started or stopped.

Note: the workmail-related resources are from an experiment in automatic creation of email accounts for demos. The exercise is incomplete. Consider these stale.

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.

Learn more at https://www.hyland.com/products/nuxeo-platform.
