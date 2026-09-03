# Description

Serverless automation for the presales demo fleet. Each subfolder is a self-contained Lambda function; most are deployed with the AWS SAM CLI, and the WorkMail ones via CloudFormation. See the README inside each subfolder for build and deploy details.

# Functions

- `scheduled-ec2-instances-start` - Starts instances on a daily schedule (e.g. Mon-Fri, 06:00 UTC). Only instances whose `startDailyUntil` tag is empty or set to a future ISO date are started.
- `scheduled-ec2-instances-stop` - Stops instances on a schedule.
- `route-53-auto-update` - Keeps Route 53 records in sync, updating an instance's DNS record when it is started or stopped.

Note: the workmail-related resources are from an experiment in automatic creation of email accounts for demos. The exercise is incomplete. Consider these stale.

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
