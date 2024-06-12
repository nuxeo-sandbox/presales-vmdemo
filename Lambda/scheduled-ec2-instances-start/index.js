/*jshint esversion: 6 */
const AWS = require('aws-sdk');

exports.handler = async (event) => {

    const ec2 = new AWS.EC2();
    return ec2.describeInstances({
        Filters: [{
            Name: 'instance-state-name',
            Values: ['stopped']
        }]
    }).promise().then(data => {

        console.log('Reservations', data.Reservations);

        let instancesToStart = [];

        data.Reservations.forEach(reservation => {
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
                        }
                        // We only accept valid ISO dates
                        return false;
                    }
                    return false;
                });
                if (tagIndex > -1) {
                    instancesToStart.push(instance.InstanceId);
                }
            })
        });

        if(instancesToStart.length > 0) {
            console.log('Instances to start', instancesToStart);
            return ec2.startInstances({
                InstanceIds: instancesToStart
            }).promise();
        } else {
            console.log('No instance to start');
        }

    }).then(data => {
        if(data) {
            console.log('Success starting instances', JSON.stringify(data, null, 2));
        } else {
            console.log('Success calling nuxeo-scheduled-ec2-start (no instance to start)');
        }
    }).catch(err => {
        console.log('failure', err);
    });

};