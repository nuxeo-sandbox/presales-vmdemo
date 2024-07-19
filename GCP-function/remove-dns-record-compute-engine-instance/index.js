const functions = require('@google-cloud/functions-framework');
const {DNS} = require('@google-cloud/dns');
const compute = require('@google-cloud/compute');

functions.http('handlerHttp', async (req, res) => {
  console.log(req.body);

  const payload = req.body.protoPayload;

  if (payload.serviceName !== 'compute.googleapis.com' || payload.methodName !== 'v1.compute.instances.stop') {
    return res.send(`Skipped!`);
  }

  const resource = req.body.resource;

  const projectId = resource.labels.project_id
  const instanceId = resource.labels.instance_id;
  const zoneId = resource.labels.zone;

  const computeClient = new compute.InstancesClient();

  // Run request
  const response = await computeClient.get({
    instance: instanceId,
    project: projectId,
    zone: zoneId
  });

  //console.log('Instances found:');
  //console.log(response);

  if (response.length < 0) {
    return res.send(`No instance!`);
  }

  const instance = response[0];

  if (instance.status !== "TERMINATED") {
    console.log(`The instance ${instanceId} is not down: ${instance.status}`)
    return res.send(`Skipped!`);
  }

  const dnsname = instance.name;
  
  console.log(dnsname)

  const dns = new DNS();

  const dnsZone = dns.zone('gcp');

  // get record
  const records = await dnsZone.getRecords({
    name: `${dnsname}.gcp.cloud.nuxeo.com.`,
    type: 'A'
  })

  console.log(records[0][0].data);

  const recordDeletePayload = dnsZone.record('a', { name: `${dnsname}.gcp.cloud.nuxeo.com.`, data: records[0][0].data[0], ttl: 300 });

  console.log(recordDeletePayload);

  const deleteRecordResponse = await dnsZone.deleteRecords(recordDeletePayload);

  console.log(response);

  return res.send(`Done!`);
});