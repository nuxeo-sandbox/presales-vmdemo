import { getChangeResourceRecordSetsCommandPayload, getDescribeInstancePayload, updateRoute53Records } from '../../../src/handlers/updateRoute53Records.mjs';
import { mockClient } from "aws-sdk-client-mock";
import { EC2Client, DescribeInstancesCommand } from "@aws-sdk/client-ec2";
import { Route53Client, ChangeResourceRecordSetsCommand } from "@aws-sdk/client-route-53";
import 'aws-sdk-client-mock-jest';

describe('Test route53 record update', function () {

  it('Verifies the route53 record is deleted', async () => {
    const instanceId = "i-08abcedef";
    const dnsName = "test";

    const ec2Mock = mockClient(EC2Client);
    ec2Mock
      .on(DescribeInstancesCommand)
      .resolves({
        Reservations: [{
          Instances: [{
            Tags: [{
              Key: "dnsName",
              Value: dnsName
            },
            {
              Key: "cfTemplateVersion",
              Value: "1.0.0"
            }]
          }]
        }]
      });

    const route53Mock = mockClient(Route53Client);
    
    route53Mock
      .on(ChangeResourceRecordSetsCommand)
      .resolves({});

    // Create a sample event payload 
    var payload = {
      "version": "0",
      "detail-type": "EC2 Instance State-change Notification",
      "source": "aws.ec2",
      "detail": {
        "instance-id": instanceId,
        "state": "shutting-down"
      }
    }

    await updateRoute53Records(payload, null);

    expect(ec2Mock).toHaveReceivedCommandWith(
      DescribeInstancesCommand, 
      getDescribeInstancePayload(instanceId));
      
    expect(route53Mock).toHaveReceivedCommandWith(
      ChangeResourceRecordSetsCommand, 
      getChangeResourceRecordSetsCommandPayload("DELETE", undefined, "test", false));
  });

  it('Verifies the route53 record is added', async () => {
    const instanceId = "i-08abcedef";
    const dnsName = "test";

    const ec2Mock = mockClient(EC2Client);
    ec2Mock
      .on(DescribeInstancesCommand)
      .resolves({
        Reservations: [{
          Instances: [{
            Tags: [{
              Key: "dnsName",
              Value: dnsName
            },
            {
              Key: "cfTemplateVersion",
              Value: "1.0.0"
            }]
          }]
        }]
      });

    const route53Mock = mockClient(Route53Client);
    
    route53Mock
      .on(ChangeResourceRecordSetsCommand)
      .resolves({});

    // Create a sample event payload 
    var payload = {
      "version": "0",
      "detail-type": "EC2 Instance State-change Notification",
      "source": "aws.ec2",
      "detail": {
        "instance-id": instanceId,
        "state": "running"
      }
    }

    await updateRoute53Records(payload, null);

    expect(ec2Mock).toHaveReceivedCommandWith(
      DescribeInstancesCommand, 
      getDescribeInstancePayload(instanceId));
      
    expect(route53Mock).toHaveReceivedCommandWith(
      ChangeResourceRecordSetsCommand, 
      getChangeResourceRecordSetsCommandPayload("UPSERT", undefined, "test", false));
  })

})
