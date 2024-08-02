import { handler, getStopInstancesCommandPayload } from '../../../src/index.mjs';
import { mockClient } from "aws-sdk-client-mock";
import { EC2Client, DescribeInstancesCommand, StopInstancesCommand } from "@aws-sdk/client-ec2";
import 'aws-sdk-client-mock-jest';

describe('Test instance shutdown', function () {

  it('Verifies the instances are shut down', async () => {
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

    expect(ec2Mock).toHaveReceivedCommandWith(StopInstancesCommand, getStopInstancesCommandPayload([instanceId]));

  });

  it('Verifies the empty nuxeoKeepAlive is respected', async () => {
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
                Key: "nuxeoKeepAlive",
                Value: ""
              }]
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {}

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommandTimes(StopInstancesCommand, 0);

  });

  it('Verifies that future nuxeoKeepAlive value is respected', async () => {
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
                Key: "nuxeoKeepAlive",
                Value: tomorrow.toISOString()
              }]
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {}

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommandTimes(StopInstancesCommand, 0);

  });

  it('Verifies that past nuxeoKeepAlive value is respected', async () => {
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
                Key: "nuxeoKeepAlive",
                Value: yesterday.toISOString()
              }]
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {}

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommandWith(StopInstancesCommand, getStopInstancesCommandPayload([instanceId]));

  });

  it('Verifies that weekend takes precedence over nuxeoKeepAlive', async () => {
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
                Key: "nuxeoKeepAlive",
                Value: ""
              }]
            }]
          }]
      });

    // Create a sample event payload 
    var payload = {
      resources:["nuxeo-scheduled-ec2-shutdown-weekend"]
    }

    await handler(payload, null);

    expect(ec2Mock).toHaveReceivedCommand(DescribeInstancesCommand);

    expect(ec2Mock).toHaveReceivedCommand(StopInstancesCommand);

  })


})
