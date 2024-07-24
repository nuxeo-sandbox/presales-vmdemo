/*
    List all running instances of the project (in every region) and check if they need to be stopped.
    This is called from a scheduler.

    A label is set to every instance, nuxeo-keep-alive.
    WARNING: See below the format requirement, it is not possible to use an ISO date/Time.
    Basically the value MUST BE either:
      * true
      * YYYY-MM-DDtHHhMMm
      * HHhMMm
    
    Any other value (of if the label is not set) => instance is not stopped, the log describes the error.
    (we should send a notification)

    An instance is stopped if
      * The date and/or time set in the label is < current date/time
      * If the nuxeo-keep-alive contains only a time ("21h00m"), it means "stop the instance every day at this time"
    
    An instance is never stopped if nuxeo-keep-alive is "true".
    
    The code handles time zone. nuxeo-keep-alive does not define a time zone, only hours and minutes.
    The value is converted to a date using the time zone of the zone in which lives the instance
    (for example, 'America/Chicago' for 'us-central1')
*/

// GCP
const functions = require('@google-cloud/functions-framework');
const compute = require('@google-cloud/compute');
// Others
const moment = require('moment-timezone');

const JOB_NAME = "daily-gce-instance-shutdown";

// For labels, <GCP does not allows "Only hyphens (-), underscores (_), lowercase characters, and numbers are allowed [...]>
// => nuxeoKeepAlive can't be used
const KEEP_ALIVE_LABEL = "nuxeo-keep-alive"; //"nuxeoKeepAlive"
// Holly..., the values themselves are to follow the same limitation.
// So, the values will not be ISO, but must follow this format:
// Instead of 2024-08-31T21:00:00 => 2024-08-31t21h00m
// The code below will resotre an ISO date.
const REGEX_TIME = /^(?:[01]\d|2[0-3])h[0-5]\dm$/;
const REGEX_DATE_AND_TIME = /^\d{4}-\d{2}-\d{2}t(?:[01]\d|2[0-3])h[0-5]\dm$/;
function backToISO(dateStr) {
  return dateStr.replace("t", "T").replace("h", ":").replace("m", ":") + "00";
}

let countOfStopped = 0;

functions.http('handlerHttp', async (req, res) => {

  const jobName = req.body.jobName;
  const projectId = req.body.projectId;

  // Check input
  if (jobName !== JOB_NAME) {
    const msg = `Wrong event, Skipped! (was expecting <${JOB_NAME}>)\n`;
    console.log(msg);
    return res.send(msg);
  }

  if(!projectId) {
    const msg = `Missing projectId\n`;
    console.log(msg);
    return res.send(msg);
  }

  // Run
  let instancesToStop = await listInstancesToStop(projectId);
  if(instancesToStop.length > 0) {
    console.log(`Instance(s) to stop: ${instancesToStop.length}`);
    // Stop the instances
    await stopInstances(instancesToStop, projectId);
  } else {
    console.log("No instance to stop");
  }

  const msg = `daily-gce-instance-shutdown: Done. Instance(s) stopped: ${countOfStopped}\n`;
  console.log(msg);
  return res.send(msg);




/*
  const zoneNames = await listAllZones(projectId);
  if (zoneNames.length > 0) {
    console.log(`Checking instances in ${zoneNames.length} instances...`);
    for (const zoneName of zoneNames) {
      //console.log(`Checking instances in ${zoneName}...`);
      let instancesToStop = await listInstancesToStop(projectId, zoneName);
      if(instancesToStop.length > 0) {
        console.log(`instancesToStop in ${zoneName}: ${instancesToStop.length}`);
      }

      // Stop the instances
      await stopInstances(instancesToStop, projectId, zoneName);
    }
  } else {
    console.log('No zones found.');
    return res.send('daily-gce-instance-shutdown: No zones found???');
  }

  const msg = `daily-gce-instance-shutdown: Done. Instance(s) stopped: ${countOfStopped}\n`;
  console.log(msg);
  return res.send(msg);
  */
  

});

/*
async function listInstancesToStop(projectId, zoneName) {

  const instancesClient = new compute.InstancesClient();

  // Create the request to list running instances
  const request = {
    project: projectId,
    zone: zoneName,
    filter: "status = RUNNING"
  };
  //console.log(JSON.stringify(request, null, 2));
  const foundInstances = instancesClient.listAsync(request);

  // Get the instances (using for...of to handle asynchronicity)
  let instancesToStop = [];
  for await (const instance of foundInstances) {
    //console.log(`Instance name: ${instance.name}`);
    let label = "" + instance.labels[KEEP_ALIVE_LABEL];
    //console.log(`${instance.name}, ${KEEP_ALIVE_LABEL}: ${instance.labels[KEEP_ALIVE_LABEL]}`)
    if(!label) {
      // Not normal, all instance should ha this label => not stopped, just log
      // We should send a mail, a notification
      //instancesToStop.push(instance.name);
      console.log(`Error: ${instance.name} dos not have the ${KEEP_ALIVE_LABEL} label set.`);
    } else {
      let now = newDate();
      let nowStr = now.toISOString();

      // If the label is only a time, let's add the current date for comparison
      console.log("label before: " + label);
      if(REGEX_TIME.test(label)) {
        label = prefixTimeWithDate(label, now);
      } else if(REGEX_TIME_NO_SECONDS.test(label)) {
        label = prefixTimeWithDate(label, now) + ": 00";
      } else if(REGEX_DATE_AND_TIME.test(label)) {
        // No change
      } else if(REGEX_DATE_AND_TIME_NO_SECONDS.test(label)) {
        label += ":00";
      } else if(label !== "true") {// Not a date
        console.log("label is not a date and is not 'true' => stop instance");
        instancesToStop.push(instance.name);
        continue;
      }
      console.log("label after: " + label);

      if(nowStr > label) {
        instancesToStop.push(instance.name);
      }
    }
  }

  return instancesToStop;
}
  */

// Return an array of {"instanceName": <name>, "zone": "<zone>"}, all the instances to stop.
// They have been checked against their label, so we return only the instances
// that really should be stopped given the urrent time.
async function listInstancesToStop(projectId) {
  const instancesClient = new compute.InstancesClient();

  //Use the `maxResults` parameter to limit the number of results that the API returns per response page.
  const aggListRequest = instancesClient.aggregatedListAsync({
    project: projectId,
    maxResults: 20
  });

  let instancesToStop = [];
  // Despite using the `maxResults` parameter, you don't need to handle the pagination
  // yourself. The returned object handles pagination automatically,
  // requesting next pages as you iterate over the results.
  for await (const [zone, instancesObject] of aggListRequest) {
    const instances = instancesObject.instances;

    if (instances && instances.length > 0) {
      let zoneName = zone.replace("zones/", "");
      let zoneTimeZone = getTimeZoneForZoneOrRegion(zoneName);
      if(!zoneTimeZone) {
        // This script must be updated (add the entry to REGION_TO_TIME_ZONE)
        // We should send a mail, a notification
        console.error(`ERROR: Cannot calculate timeZone for zone ${zoneName}. Script must be updated`);
        continue;
      }

      console.log(`${zoneName} (${zoneTimeZone}) has ${instances.length} instance(s) whatever their status. Checking if some needs to be stopped...`);
      for (const instance of instances) {
        if(instance.status === "RUNNING") {
          let label = "" + instance.labels[KEEP_ALIVE_LABEL];
          if(!label || label === "undefined") { 
            // Not normal, every instance should have this label => not stopped, just log
            // We should send a mail, a notification
            console.error(`ERROR: ${instance.name} does not have the ${KEEP_ALIVE_LABEL} label set. We keep it alive.`);
          } else {
            let now = new Date();

            // If the label is only a time, let's add the current date for comparison
            //console.log("label before: " + label);
            let labelUpdated = label;
            if(REGEX_TIME.test(label)) {
              labelUpdated = prefixTimeWithDate(label, now);
            } else if(REGEX_DATE_AND_TIME.test(label)) {
              labelUpdated = backToISO(label);
            } else if(label !== "true") {// Not a date, not "true"
              // We should send a mail, a notification
              console.log(`Error: ${instance.name}: Label (${label}) is not a date and is not 'true' => Ignoring (instance is not stopped)`);
              continue;
            }
            //console.log("label after: " + labelUpdated);

            let labelDate = buildDateWithTimeZone(labelUpdated, zoneTimeZone);
            let labelUTCDate = getUTCYearMonthDayAsStr(labelDate);
            let labelUTCTime = getUTCHoursMinutesAsStr(labelDate);

            let nowUTCDate = getUTCYearMonthDayAsStr(now);
            let nowUTCTime = getUTCHoursMinutesAsStr(now);

            let logInfo = `\n  Running instance: ${instance.name}, ${KEEP_ALIVE_LABEL}: ${label} -> ${labelUpdated}\n    Now UTC:   ${nowUTCDate}, ${nowUTCTime}\n    Label UTC: ${labelUTCDate}, ${labelUTCTime}\n`;
            let originalLength = instancesToStop.length;

            if(label === "true"){
              // Do nothing...
            } else if(nowUTCDate > labelUTCDate) {
              instancesToStop.push({"instanceName": instance.name, "zone": zoneName});
            } else if(nowUTCDate === labelUTCDate) {
              if(nowUTCTime > labelUTCTime) {
                instancesToStop.push({"instanceName": instance.name, "zone": zoneName});
              }
            }
            if(instancesToStop.length > originalLength) {
              logInfo += "    => Added to the list of instances to stop.";
            } else {
              logInfo += "    => Not to be stopped";
            }
            console.log(logInfo);
          }
        }
      }
    }
  }

  return instancesToStop;
}

function prefixTimeWithDate (aStr, aDate) {
  let year = aDate.getFullYear();
  let month = aDate.getMonth() + 1;
  if (month < 10) {
    month = "0" + month;
  }

  let date = aDate.getDate();
  if (date < 10) {
    date = "0" + date;
  }

  let result = `${year}-${month}-${date}T${aStr}`;
  return backToISO(result);
}

// Warning: instances is an array of {"instanceName": <name>, "zone": "<zone>"}
async function stopInstances(instances, projectId) {
  const instancesClient = new compute.InstancesClient();

  const stopPromises = instances.map(instance => {
    const stopRequest = {
      project: projectId,
      zone: instance.zone,
      instance: instance.instanceName,
    };

    console.log(`Stopping instance ${instance.instanceName}...`);
    return instancesClient.stop(stopRequest).then(() => {
      console.log(`Instance ${instance.instanceName} has been stopped.`);
      countOfStopped += 1;
    }).catch(error => {
      console.error(`Error stopping instance ${instance.instanceName}:`, error);
    });
  });

  // Wait for all stop requests to complete
  await Promise.all(stopPromises);
}

// Function to list all zone names in a project
async function listAllZones(projectId) {
  const zonesClient = new compute.ZonesClient();

  // Create the request to list zones
  const request = {
    project: projectId,
  };

  const zoneNames = [];
  try {
    // Use the list method to list zones
    const [response] = await zonesClient.list(request);

    if (response && response.length > 0) {
      let done = false;
      for (const zone of response) {
        zoneNames.push(zone.name);
      }
    } else {
      console.log('No zones found.');
    }
  } catch (error) {
    console.error('Error listing zones:', error);
  }

  return zoneNames;
}

// ==================================================
// Date utils
// ==================================================
function getUTCYearMonthDayAsStr(aDate) {

  let str = aDate.getUTCFullYear() + "-";

  // +1 because UTC starts at 0
  let m = aDate.getUTCMonth() + 1;
  if(m < 10) {
    str += "0";
  }
  str += m + "-";

  let d = aDate.getUTCDate();
  if(d < 10) {
    str += "0";
  }
  str += d;

  return str;
}
function getUTCHoursMinutesAsStr(aDate) {

  let str = "";
  let hours = aDate.getUTCHours();
  if(hours < 10) {
    str += "0";
  }
  str += hours + ":";

  let mn = aDate.getUTCMinutes();
  if(mn < 10) {
    str += "0";
  }
  str += mn;

  return str;
}

// ==================================================
// Time zone and zones and regions
// ==================================================
const REGION_TO_TIME_ZONE = {
  // Americas
  'northamerica-northeast1': 'America/Toronto',
  'northamerica-northeast2': 'America/Toronto',
  'southamerica-east1': 'America/Sao_Paulo',
  'southamerica-east1': 'America/Santiaog',
  'us-central1': 'America/Chicago',
  'us-east1': 'America/New_York',
  'us-east4': 'America/New_York',
  'us-east5': 'America/New_York',
  'us-west1': 'America/Los_Angeles',
  'us-west2': 'America/Los_Angeles',
  'us-west3': 'America/Denver',
  'us-west4': 'America/Las_Vegas',
  'us-south1': 'America/Dallas',

  // Europe
  'europe-north1': 'Europe/Helsinki',
  'europe-central12': 'Eurpoe/Warshow',
  'europe-west1': 'Europe/Brussels',
  'europe-west2': 'Europe/London',
  'europe-west3': 'Europe/Frankfurt',
  'europe-west4': 'Europe/Amsterdam',
  'europe-west6': 'Europe/Zurich',
  //'europe-west7': 'Europe/Zurich',
  'europe-west8': 'Europe/Milan',
  'europe-west9': 'Europe/Paris',
  'europe-west10': 'Europe/Berlin',
  //'europe-west11': 'Europe/Berlin',
  'europe-west12': 'Europe/Turin',
  'europe-central2': 'Europe/Warsaw',

  // Asia Pacific
  'asia-east1': 'Asia/Taipei',
  'asia-east2': 'Asia/Hong_Kong',
  'asia-northeast1': 'Asia/Tokyo',
  'asia-northeast2': 'Asia/Osaka',
  'asia-northeast3': 'Asia/Seoul',
  'asia-south1': 'Asia/Kolkata',
  'asia-south2': 'Asia/Hyderabad',
  'asia-southeast1': 'Asia/Singapore',
  'asia-southeast2': 'Asia/Jakarta',

  // Australia
  'australia-southeast1': 'Australia/Sydney',
  'australia-southeast2': 'Australia/Melbourne',

  // Middle East
  'me-central1': 'Asia/Dubai',
  'me-west1': 'Asia/Jerusalem',

  // Africa
  'africa-northeast1': 'Africa/Cairo',
  'africa-south1': 'Africa/Johannesburg',
};

function getTimeZoneForZoneOrRegion(regionOrZone) {
  // Some calls to GCP return a kind of prefix. "zones/us-central1-a"
  let zoneName = regionOrZone.replace("zones/", "");

  // us-central1-a => us-central1
  let region = zoneName.split("-");
  region = region[0] + "-" + region[1];

  const timeZone = REGION_TO_TIME_ZONE[region];
  if (!timeZone) {
    return null; //(`Timezone for region ${region} is not defined in the mapping.`);
  }

  //console.log(`The timezone of region ${region} is ${timeZone}`);
  return timeZone;
}

// Recieves a string with no time zone info at all, and a time zone, return a date object
function buildDateWithTimeZone(dateString, timeZone) {
  // Make sure the stinrg has no time zone. And for our use case,
  // we don't need seconds or microseconds (should not even be passed)
  dateString = dateString.substring(0, 16) + ":00"

  // Parse the date string without timezone information
  const date = moment.tz(dateString, timeZone);
  //return date.format('YYYY-MM-DDTHH:mm:ssZ'); // or any other format you prefer
  return date.toDate();
}
