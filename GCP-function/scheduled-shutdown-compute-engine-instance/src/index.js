const functions = require('@google-cloud/functions-framework');
const compute = require('@google-cloud/compute');

functions.http('handlerHttp', async (req, res) => {
  console.log(req.body);
  return res.send(`Done!`);
});