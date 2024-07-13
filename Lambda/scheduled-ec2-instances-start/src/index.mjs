import { EC2Client, DescribeInstancesCommand, StartInstancesCommand } from "@aws-sdk/client-ec2";

const ec2 = new EC2Client({});

export const handler = async (event, context) => {

    const describeInstanceResponse = await ec2.send(
        new DescribeInstancesCommand(getDescribeInstancesPayload()));

    console.log('Reservations', describeInstanceResponse.Reservations);

    let instanceIds = [];

    describeInstanceResponse.Reservations.forEach(reservation => {
        reservation.Instances.forEach(instance => {
            // Look for nuxeoKeepAlive tag
            let tagIndex = instance.Tags.findIndex(tag => {
                if (tag.Key === "startDailyUntil") {
                    // Check we have a date
                    if (/([12]\d{3}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]))/.test(tag.Value)) {
                        let startUntil = new Date(tag.Value);
                        // Make it the end of day, so currentDate is <= currentDate if we are the same day
                        // Anyway, the spirit of this lambda is to start instances in the morning
                        startUntil.setHours(20);
                        startUntil.setMinutes(59);
                        startUntil.setSeconds(59);
                        let currentDate = new Date();
                        return currentDate.getTime() <= startUntil.getTime();
                    } else {
                        return true;
                    }
                }
                return false;
            });
            if (tagIndex >= 0) {
                instanceIds.push(instance.InstanceId);
            }
        })
    });

    console.log('Instances to start', instanceIds);

    if (instanceIds.length > 0) {
        await ec2.send(new StartInstancesCommand(getStartInstancesCommandPayload(instanceIds)));
        console.log('Success starting instances');
    }
}


export const getDescribeInstancesPayload = () => {
    return {
        Filters: [{
            Name: 'instance-state-name',
            Values: ['stopped']
        }]
    }
}


export const getStartInstancesCommandPayload = instanceIds => {
    return {
        InstanceIds: instanceIds
    }
}