import { EC2Client, DescribeInstancesCommand } from "@aws-sdk/client-ec2";
import { Route53Client, ChangeResourceRecordSetsCommand } from "@aws-sdk/client-route-53";

const ec2 = new EC2Client({});
const route53 = new Route53Client();

export const handler = async (event) => {
    console.log('Event:', JSON.stringify(event));
    
    const instanceId = event.detail['instance-id'];
    console.log('Fetching instance info :', instanceId);

    const describeInstanceResponse = await client.send(new DescribeInstancesCommand({
        InstanceIds: [
            instanceId,
        ]
    }));

    const instance = describeInstanceResponse.Reservations[0].Instances[0];
    console.log('Success getting EC2 instance info', JSON.stringify(instance, null, 2));

    let publicDNS = instance.PublicDnsName;
    console.log('Instance public DNS', publicDNS);

    let nuxeoDnsName;

    let templateVer = instance.Tags.find(function (tag) {
        return tag.Key === "cfTemplateVersion";
    });
    let dnsTag = instance.Tags.find(function (tag) {
        return tag.Key === "dnsName";
    });

    if (dnsTag) {
        nuxeoDnsName = dnsTag.Value;
    } else {
        nuxeoDnsName = instance.Tags.find(function (tag) {
            return tag.Key === "aws:cloudformation:stack-name";
        }).Value;
    }
    console.log('Nuxeo DNS Name', nuxeoDnsName);

    const instanceState = event.detail['state'];
    let action;

    if (instanceState === "running") {
        action = "UPSERT";
    } else if (instanceState === 'shutting-down' || instanceState === "stopping") {
        action = "DELETE";
    } else {
        throw ("Unsupported instance state");
    }

    const dnsChanges = [{
        Action: action,
        ResourceRecordSet: {
            Name: nuxeoDnsName + '.cloud.nuxeo.com.',
            ResourceRecords: [{
                Value: publicDNS
            }],
            TTL: 300,
            Type: "CNAME"
        }
    }];
    if (!templateVer) {
        // Unversioned templates use kibana DNS name
        dnsChanges.push({
            Action: action,
            ResourceRecordSet: {
                Name: 'kibana-' + nuxeoDnsName + '.cloud.nuxeo.com.',
                ResourceRecords: [{
                    Value: publicDNS
                }],
                TTL: 300,
                Type: "CNAME"
            }
        });
    }

    //update records
    const updateRecordResponse = await client.send(new ChangeResourceRecordSetsCommand({
        ChangeBatch: {
            Changes: dnsChanges,
            Comment: "Update after instance restart"
        },
        HostedZoneId: process.env.HOSTED_ZONE
    }));

    console.log('Success updating route 53 record', JSON.stringify(updateRecordResponse, null, 2));

};