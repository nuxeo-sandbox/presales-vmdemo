/*
    List all running instances of the project (in every region) and check if they need to be stopped.
    This is called from a scheduler.

    Both Compute Engine instances and Cloud SQL instances are handled. Cloud SQL
    instances are only relevant for the Nuxeo stacks that use Cloud SQL for
    PostgreSQL instead of the MongoDB container; a Cloud SQL instance keeps
    billing 24/7 as long as it runs, even when its Nuxeo VM is stopped.

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

// Cloud SQL is not covered by @google-cloud/compute. Rather than adding a new
// npm dependency, we call the Cloud SQL Admin REST API directly.
const SQL_ADMIN_BASE = "https://sqladmin.googleapis.com/v1";

// For labels, <GCP does not allows "Only hyphens (-), underscores (_), lowercase characters, and numbers are allowed [...]>
// => nuxeoKeepAlive can't be used
const KEEP_ALIVE_LABEL = "nuxeo-keep-alive"; //"nuxeoKeepAlive"
// Holly..., the values themselves are to follow the same limitation.
// So, the values will not be ISO, but must follow this format:
// Instead of 2024-08-31T21:00:00 => 2024-08-31t21h00m
// The code below will restore an ISO date.
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

  /* ==================== Cloud SQL ====================
     Handled after Compute Engine and fully wrapped in a try/catch: a failure
     here (missing IAM permission, API disabled, ...) must never prevent the
     Compute Engine instances from being stopped. */
  let sqlMessage = "";
  try {
    const sqlInstancesToStop = await listSqlInstancesToStop(projectId);
    let countOfSqlStopped = 0;
    if (sqlInstancesToStop.length > 0) {
      console.log(`Cloud SQL instance(s) to stop: ${sqlInstancesToStop.length}`);
      countOfSqlStopped = await stopSqlInstances(sqlInstancesToStop, projectId);
    } else {
      console.log("No Cloud SQL instance to stop");
    }
    sqlMessage = ` Cloud SQL instance(s) stopped: ${countOfSqlStopped}.`;
  } catch (error) {
    console.error("Error while handling Cloud SQL instances. Compute Engine instances were NOT impacted:", error);
    sqlMessage = " Cloud SQL handling FAILED, see the logs.";
  }

  const msg = `${JOB_NAME}: Done. Instance(s) stopped: ${countOfStopped}.${sqlMessage}\n`;
  console.log(msg);
  return res.send(msg);

});


// Return an array of {"instanceName": <name>, "zone": "<zone>"}, all the instances to stop.
// They have been checked against their label, so we return only the instances
// that really should be stopped given the current time.
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
// Cloud SQL
// ==================================================

/*
   Shared decision helper: given a nuxeo-keep-alive label value and a time zone,
   tell whether the resource must be stopped right now.
   Returns { stop: boolean, reason: string }.
*/
function shouldStopNow(label, timeZone) {
  if (!label || label === "undefined") {
    return { stop: false, reason: `no ${KEEP_ALIVE_LABEL} label => kept alive` };
  }
  if (label === "true") {
    return { stop: false, reason: `${KEEP_ALIVE_LABEL}=true => never stopped` };
  }

  const now = new Date();

  // If the label is only a time, let's add the current date for comparison
  let labelUpdated;
  if (REGEX_TIME.test(label)) {
    labelUpdated = prefixTimeWithDate(label, now);
  } else if (REGEX_DATE_AND_TIME.test(label)) {
    labelUpdated = backToISO(label);
  } else {
    return { stop: false, reason: `${KEEP_ALIVE_LABEL}='${label}' is not a date-time => ignored` };
  }

  const labelDate = buildDateWithTimeZone(labelUpdated, timeZone);
  const labelUTCDate = getUTCYearMonthDayAsStr(labelDate);
  const labelUTCTime = getUTCHoursMinutesAsStr(labelDate);
  const nowUTCDate = getUTCYearMonthDayAsStr(now);
  const nowUTCTime = getUTCHoursMinutesAsStr(now);

  const reason = `${KEEP_ALIVE_LABEL}=${label} -> ${labelUpdated} | now UTC ${nowUTCDate} ${nowUTCTime} | label UTC ${labelUTCDate} ${labelUTCTime}`;

  if (nowUTCDate > labelUTCDate) {
    return { stop: true, reason };
  }
  if (nowUTCDate === labelUTCDate && nowUTCTime > labelUTCTime) {
    return { stop: true, reason };
  }
  return { stop: false, reason };
}

// The function's own service account token, read from the metadata server.
// Cloud Functions gen2 run on Cloud Run, which always exposes it.
async function getAccessToken() {
  const response = await fetch(
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token',
    { headers: { 'Metadata-Flavor': 'Google' } }
  );
  if (!response.ok) {
    throw new Error(`Cannot get an access token from the metadata server: ${response.status}`);
  }
  const body = await response.json();
  return body.access_token;
}

// Return an array of Cloud SQL instance names to stop.
// Instances without the nuxeo-keep-alive label are never touched, so Cloud SQL
// instances created outside of this tooling are safe.
async function listSqlInstancesToStop(projectId) {
  const token = await getAccessToken();

  const response = await fetch(`${SQL_ADMIN_BASE}/projects/${projectId}/instances`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  if (!response.ok) {
    throw new Error(`Cannot list Cloud SQL instances: ${response.status} ${await response.text()}`);
  }

  const body = await response.json();
  const instances = body.items || [];
  const instancesToStop = [];

  for (const instance of instances) {
    // Anything that is not RUNNABLE is already stopped, or still being created.
    if (instance.state !== "RUNNABLE") {
      continue;
    }
    // A NEVER activation policy means the instance is already stopped.
    if (instance.settings && instance.settings.activationPolicy === "NEVER") {
      continue;
    }

    const labels = (instance.settings && instance.settings.userLabels) || {};
    const label = labels[KEEP_ALIVE_LABEL];
    if (!label) {
      console.log(`Cloud SQL ${instance.name} has no ${KEEP_ALIVE_LABEL} label => we don't touch it.`);
      continue;
    }

    // Cloud SQL instances are regional, getTimeZoneForZoneOrRegion handles both.
    const timeZone = getTimeZoneForZoneOrRegion(instance.region);
    if (!timeZone) {
      // This script must be updated (add the entry to REGION_TO_TIME_ZONE)
      console.error(`ERROR: Cannot calculate timeZone for region ${instance.region}. Script must be updated`);
      continue;
    }

    const decision = shouldStopNow(label, timeZone);
    const action = decision.stop ? "Added to the list of instances to stop." : "Not to be stopped";
    console.log(`\n  Running Cloud SQL instance: ${instance.name} (${instance.region}, ${timeZone})\n    ${decision.reason}\n    => ${action}`);

    if (decision.stop) {
      instancesToStop.push(instance.name);
    }
  }

  return instancesToStop;
}

// Stopping a Cloud SQL instance means setting its activation policy to NEVER.
// Returns the number of instances actually stopped.
async function stopSqlInstances(instanceNames, projectId) {
  const token = await getAccessToken();
  let countOfSqlStopped = 0;

  const stopPromises = instanceNames.map(async (name) => {
    console.log(`Stopping Cloud SQL instance ${name}...`);
    try {
      const response = await fetch(`${SQL_ADMIN_BASE}/projects/${projectId}/instances/${name}`, {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ settings: { activationPolicy: 'NEVER' } })
      });
      if (!response.ok) {
        console.error(`Error stopping Cloud SQL instance ${name}: ${response.status} ${await response.text()}`);
        return;
      }
      console.log(`Cloud SQL instance ${name} has been stopped.`);
      countOfSqlStopped += 1;
    } catch (error) {
      console.error(`Error stopping Cloud SQL instance ${name}:`, error);
    }
  });

  // Wait for all stop requests to complete
  await Promise.all(stopPromises);

  return countOfSqlStopped;
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
