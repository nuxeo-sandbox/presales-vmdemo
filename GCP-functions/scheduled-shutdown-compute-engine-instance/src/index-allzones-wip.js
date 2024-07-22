const functions = require('@google-cloud/functions-framework');
const compute = require('@google-cloud/compute');

const JOB_NAME = "daily-gce-instance-shutdown";
const KEEP_ALIVE_TAG = "nuxeo-keep-alive"; //"nuxeoKeepAlive" => "nly hyphens (-), underscores (_), lowercase characters, ..."

let countOfStopped = 0;

functions.http('handlerHttp', async (req, res) => {

  const jobName = req.body.jobName;
  const projectId = req.body.projectId;
  const zone = req.body.zone;

  // Check input
  if (jobName !== JOB_NAME) {
    const msg = `Wrong event, Skipped! (was expecting <${JOB_NAME}>)\n`;
    console.log(msg);
    return res.send(msg);
  }

  if(!projectId || !zone) {
    const msg = `Missing parameter, either projectId or zone\n`;
    console.log(msg);
    return res.send(msg);
  }

  const zoneNames = await listAllZones(projectId);
  if (zoneNames.length > 0) {
    for (const zoneName of zoneNames) {
      console.log(`Checking instances in ${zoneName}...`);
      let instancesToStop = await listInstancesWithLabel(projectId, zoneName);
      console.log(`instancesToStop in ${zoneName}: ${instancesToStop.length}`);

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
  

});

// Function to list instances with a specific label
async function listInstancesToStop(projectId, zoneName) {

  const instancesClient = new compute.InstancesClient();

  // Create the request to list instances with the specified label
  const request = {
    project: projectId,
    zone: zoneName,
    filter: "labels." + KEEP_ALIVE_TAG + "=* AND status = RUNNING"
  };
  //console.log(JSON.stringify(request, null, 2));

  // Use the listAsync method to list instances
  const foundInstances = instancesClient.listAsync(request);

  let instancesToStop = [];
  // Iterate over the iterable object to get the instances
  for await (const instance of foundInstances) {
    //console.log(`Instance name: ${instance.name}`);
    let tag = "" + instance.labels[KEEP_ALIVE_TAG];
    console.log(`${instance.name}, ${KEEP_ALIVE_TAG}: ${instance.labels[KEEP_ALIVE_TAG]}`)
    if(tag) {// Should not happen that the tag is empty or null, we did filter above, but well.
      // If this is a date, check to see if it is in the past
      // We compare strings to avoid issues with time.
      if (/([12]\d{3}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]))/.test(tag)) {
          let currentDate = new Date().toISOString().split('T')[0];
          // If today is after the keep alive date, we must stop the instance
          if(currentDate > tag) {
            instancesToStop.push(instance.name);
          }
      } else if(tag !== "true") {
        instancesToStop.push(instance.name);
      }
    }
  }

  return instancesToStop;
}

// Function to stop instances
async function stopInstances(instances, projectId, zoneName) {
  const instancesClient = new compute.InstancesClient();

  const stopPromises = instances.map(instance => {
    const stopRequest = {
      project: projectId,
      zone: zoneName,
      instance: instance.name,
    };

    console.log(`Stopping instance ${instance.name}...`);
    return instancesClient.stop(stopRequest).then(() => {
      console.log(`Instance ${instance.name} has been stopped.`);
      countOfStopped += 1;
    }).catch(error => {
      console.error(`Error stopping instance ${instance.name}:`, error);
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



