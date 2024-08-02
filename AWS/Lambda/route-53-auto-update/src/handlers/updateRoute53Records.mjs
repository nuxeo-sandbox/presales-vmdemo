/**
 * A Lambda function that update route53 records according to ec2 instances state changes
 */

import { EC2Client, DescribeInstancesCommand } from "@aws-sdk/client-ec2";
import { Route53Client, ChangeResourceRecordSetsCommand } from "@aws-sdk/client-route-53";

const ec2 = new EC2Client({});
const route53 = new Route53Client();

export const updateRoute53Records = async (event, context) => {

    console.log('Event:', JSON.stringify(event));

    console.log(`HOST_ZONE_ID: ${process.env.HOSTED_ZONE}`);
    
    const instanceId = event.detail['instance-id'];

    console.log('Fetching instance info :', instanceId);

    const describeInstanceResponse = await ec2.send(new DescribeInstancesCommand(getDescribeInstancePayload(instanceId)));

    const instance = describeInstanceResponse.Reservations[0].Instances[0];
    console.log('Success getting EC2 instance info');

    const publicDNS = instance.PublicDnsName;
    console.log('Instance public DNS', publicDNS);

    let nuxeoDnsName;

    const templateVer = instance.Tags.find(function (tag) {
        return tag.Key === "cfTemplateVersion";
    });
    const dnsTag = instance.Tags.find(function (tag) {
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

    //update records
    const updateRecordResponse = await route53.send(new ChangeResourceRecordSetsCommand(
        getChangeResourceRecordSetsCommandPayload(action, publicDNS, nuxeoDnsName, !templateVer)
    ));

    console.log('Success updating route 53 record', JSON.stringify(updateRecordResponse, null, 2));

}

export const getDescribeInstancePayload = instanceId => {
    return {
        InstanceIds: [
            instanceId,
        ]
    }
} 

export const getDnsChangePayload = (action, publicAwsDns, nuxeoDnsName, withKibana) => {
    const dnsChanges = [{
        Action: action,
        ResourceRecordSet: {
            Name: nuxeoDnsName + process.env.DOMAIN,
            ResourceRecords: [{
                Value: publicAwsDns
            }],
            TTL: 300,
            Type: "CNAME"
        }
    }];
    if (withKibana) {
        // Unversioned templates use kibana DNS name
        dnsChanges.push({
            Action: action,
            ResourceRecordSet: {
                Name: 'kibana-' + nuxeoDnsName + process.env.DOMAIN,
                ResourceRecords: [{
                    Value: publicAwsDns
                }],
                TTL: 300,
                Type: "CNAME"
            }
        });
    }
    return dnsChanges;
} 


export const getChangeResourceRecordSetsCommandPayload = (action, publicAwsDns, nuxeoDnsName, withKibana) => {
    return {
        ChangeBatch: {
            Changes: getDnsChangePayload(action, publicAwsDns, nuxeoDnsName, withKibana),
            Comment: "Update after instance state modification"
        },
        HostedZoneId: process.env.HOSTED_ZONE
    }
} 