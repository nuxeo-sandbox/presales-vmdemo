import { EC2Client, DescribeInstancesCommand, StopInstancesCommand } from "@aws-sdk/client-ec2";

const ec2 = new EC2Client({});

export const handler = async (event, context) => {

    const isWeekend = event?.resources?.[0].includes('nuxeo-scheduled-ec2-shutdown-weekend');

    const describeInstanceResponse = await ec2.send(
        new DescribeInstancesCommand(getDescribeInstancesPayload()));

    console.log('Reservations', describeInstanceResponse.Reservations);

    let instanceIds = [];

    describeInstanceResponse.Reservations.forEach(reservation => {
        reservation.Instances.forEach(instance => {
            // Disabled per Derick Deleo's request on 08-01-2024
            // if (isWeekend) {
            //     instanceIds.push(instance.InstanceId);
            //     return;
            // }

            // Look for nuxeoKeepAlive tag
            let tagIndex = instance.Tags.findIndex(tag => {
                if (tag.Key === "nuxeoKeepAlive") {
                    // If this is a date, check to see if it is in the past
                    // Current date will be "in the past" for the daily check
                    if (/([12]\d{3}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]))/.test(tag.Value)) {
                        let keepAliveDate = new Date(tag.Value);
                        let currentDate = new Date();
                        // If today is less than the keep alive date, return true
                        return currentDate.getTime() < keepAliveDate.getTime();
                    }
                    return tag.Value !== "false";
                }
                return false;
            });
            if (tagIndex == -1) {
                instanceIds.push(instance.InstanceId);
            }
        })
    });

    console.log('Instances to stop', instanceIds);

    if (instanceIds.length > 0) {
        await ec2.send(new StopInstancesCommand(getStopInstancesCommandPayload(instanceIds)));
        console.log('Success stopping instances');
    }
}


export const getDescribeInstancesPayload = () => {
    return {
        Filters: [{
            Name: 'instance-state-name',
            Values: ['running']
        }]
    }
}


export const getStopInstancesCommandPayload = instanceIds => {
    return {
        InstanceIds: instanceIds
    }
}