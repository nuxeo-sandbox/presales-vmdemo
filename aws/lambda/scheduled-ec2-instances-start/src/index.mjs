import { EC2Client, DescribeInstancesCommand, StartInstancesCommand } from "@aws-sdk/client-ec2";

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
                        const currentDate = new Date();
                        console.log(`Now: ${currentDate.toISOString()}`);
                        const startUntilDateIsoStr = getDateTimeWithTz(tag.Value);
                        console.log(`startUntil: ${startUntilDateIsoStr}`);
                        const startUntil = new Date(startUntilDateIsoStr);
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