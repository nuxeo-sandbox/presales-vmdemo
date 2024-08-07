import { EC2Client, DescribeImagesCommand, DeregisterImageCommand, DeleteSnapshotCommand } from "@aws-sdk/client-ec2"; // ES Modules import

const dryRun = false;

const deregisterImage = async (client, name, imageId) => {
  const input = {
    ImageId: imageId,
    DryRun: dryRun
  };
  try {
    const command = new DeregisterImageCommand(input);
    const response = await client.send(command);
    console.log(`Deregister ${name} ${imageId} : ${response.Return}`)
  } catch (error) {
    console.log(`Deregister ${name} ${imageId} : ${error}`)
  }
}

const deleteSnaphot = async (client, snapshotId) => {
    const input = {
        SnapshotId: snapshotId,
        DryRun: dryRun,
    };

    try {
        const command = new DeleteSnapshotCommand(input);
        const response = await client.send(command);
        console.log(`Deleted Snapshot ${snapshotId} : ${response.Return}`)
    } catch (error) {
        console.log(`Deleted Snapshot ${snapshotId} : ${error}`)
    }
  }

const processImage = async (client, image) => {
    console.log(`Deregister ${image.Name}`)
    await deregisterImage(client,image.Name,image.ImageId);
    image.BlockDeviceMappings.forEach(mapping => {
        if (mapping.Ebs) {
            deleteSnaphot(client,mapping.Ebs.SnapshotId);
        }
    });
  }


const cleanupRegion = async (regionName) => {
    const client = new EC2Client({
        region: regionName,
        requestHandler: {
          requestTimeout: 3_000,
          httpsAgent: { maxSockets: 3 }
        }
    });
    const input = { // DescribeImagesRequest
      Owners: ["self"],
      Filters: [
      {
        Name: "name",
        Values: [
          "nuxeo-sec*",
        ],
      },
    ],
      MaxResults: 400,
    };
    const command = new DescribeImagesCommand(input);
    const response = await client.send(command);
    response.Images.forEach(async image => {
      await processImage(client,image)
    });
}

const regions = [
    "ap-southeast-2",
    "eu-central-1",
    "eu-west-2",
    "eu-west-3",
    "ca-central-1",
    "us-east-2",
    "ap-northeast-1",
    "eu-west-1",
    "us-east-1",
    "us-west-1",
    "us-west-2",
    "sa-east-1"
]

regions.forEach(regionName => {
    cleanupRegion(regionName);
})