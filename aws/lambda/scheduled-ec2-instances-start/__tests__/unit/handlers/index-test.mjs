import { handler, getStartInstancesCommandPayload } from '../../../src/index.mjs';
import { mockClient } from "aws-sdk-client-mock";
import { EC2Client, DescribeInstancesCommand, StartInstancesCommand } from "@aws-sdk/client-ec2";
import 'aws-sdk-client-mock-jest';

describe('Test instance start', function () {

  it('Verifies the instances are not started without the tag', async () => {
    const instanceId = "i-08abcedef";
    const dnsName = "test";

    const ec2Mock = mockClient(EC2Client);
    ec2Mock
      .on(DescribeInstancesCommand)
      .resolves({
        Reservations: [{
            Instances: [{
              InstanceId: instanceId,
              Tags: []
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {}

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommandTimes(StartInstancesCommand, 0);

  });

  it('Verifies the empty startDailyUntil is respected', async () => {
    const instanceId = "i-08abcedef";
    const dnsName = "test";

    const ec2Mock = mockClient(EC2Client);
    ec2Mock
      .on(DescribeInstancesCommand)
      .resolves({
        Reservations: [{
            Instances: [{
              InstanceId: instanceId,
              Tags: [{
                Key: "startDailyUntil",
                Value: ""
              }]
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {}

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommandWith(StartInstancesCommand, getStartInstancesCommandPayload([instanceId]));

  });

  it('Verifies that future startDailyUntil value is respected', async () => {
    const instanceId = "i-08abcedef";
    const dnsName = "test";

    const tomorrow = new Date()
    tomorrow.setDate(tomorrow.getDate() + 1) 

    const ec2Mock = mockClient(EC2Client);
    ec2Mock
      .on(DescribeInstancesCommand)
      .resolves({
        Reservations: [{
            Instances: [{
              InstanceId: instanceId,
              Tags: [{
                Key: "startDailyUntil",
                Value: tomorrow.toISOString().substring(0,10)
              }]
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {}

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommandWith(StartInstancesCommand, getStartInstancesCommandPayload([instanceId]));

  });

  it('Verifies that past startDailyUntil value is respected', async () => {
    const instanceId = "i-08abcedef";
    const dnsName = "test";

    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1); 

    const ec2Mock = mockClient(EC2Client);
    ec2Mock
      .on(DescribeInstancesCommand)
      .resolves({
        Reservations: [{
            Instances: [{
              InstanceId: instanceId,
              Tags: [{
                Key: "startDailyUntil",
                Value: yesterday.toISOString().substring(0,10)
              }]
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {}

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommandTimes(StartInstancesCommand, 0);

  });

})
