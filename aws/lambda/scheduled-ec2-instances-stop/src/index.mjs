import { EC2Client, DescribeInstancesCommand, StopInstancesCommand } from "@aws-sdk/client-ec2";

const ec2 = new EC2Client({});


const getDateTimeWithTz = (dateString) => {

    const pad = (num) => {
      return (num < 10 ? '0' : '') + num;
    };

    const currentDate = new Date();
    const tzOffset = currentDate.getTimezoneOffset();

    const sign = tzOffset >= 0 ? '+' : '-';
    const hourOffset = pad(Math.floor(Math.abs(tzOffset) / 60));
    const minuteOffset = pad(Math.abs(tzOffset) % 60);

    return `${dateString}T23:59:59.999${sign}${hourOffset}:${minuteOffset}`
}


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
                        const currentDate = new Date();
                        console.log(`Now: ${currentDate.toISOString()}`);
                        const keepAliveDateIsoStr = getDateTimeWithTz(tag.Value);
                        console.log(`keepAliveDateIsoStr: ${keepAliveDateIsoStr} `);
                        let keepAliveDate = new Date(keepAliveDateIsoStr);
                        console.log(`keepAliveDate: ${keepAliveDate.toISOString()} `);
                        // If now is less than the keep alive date, return true
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