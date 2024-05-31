import { EC2Client, DescribeSecurityGroupRulesCommand, AuthorizeSecurityGroupIngressCommand, RevokeSecurityGroupIngressCommand } from "@aws-sdk/client-ec2"; // ES Modules import

const updateRule = async (client, rule, cidrIp) => {
    //delete existing rule
    const revokeCommand = new RevokeSecurityGroupIngressCommand({
        GroupId: rule.GroupId,
        SecurityGroupRuleId: [rule.SecurityGroupRuleId],
        CidrIp: rule.CidrIpv4,
        IpProtocol: "tcp",
        FromPort: 22,
        ToPort: 22
    });
    const revokeResp = await client.send(revokeCommand);
    console.log(`Rule ${rule.SecurityGroupRuleId} deleted: ${revokeResp.Return}`);

    //add new rule
    const authorizeCommand = new AuthorizeSecurityGroupIngressCommand({
        "GroupId": rule.GroupId,
        "IpPermissions": [
            {
                "FromPort": 22,
                "IpProtocol": "tcp",
                "IpRanges": [
                    {
                        "CidrIp": cidrIp,
                        "Description": "SSH access only from VPC"
                    }
                ],
                "ToPort": 22,
            }
        ]
    });
    const authResp = await client.send(authorizeCommand);
    console.log(`New SSH Rule for ${rule.GroupId} SG added: ${authResp.Return}`);

};

const updateRegionRules = async (regionName, cidr) => {
    const client = new EC2Client({
        region: regionName
    });
    const listCommand = new DescribeSecurityGroupRulesCommand({
        MaxResults: 1000
    });
    const response = await client.send(listCommand);
    response.SecurityGroupRules.forEach(rule => {
        if (rule.ToPort !== 22) {
            return;
        }
        // Update rule for port 22
        console.log(`Update ${rule.GroupId} ${rule.SecurityGroupRuleId}`);
        updateRule(client, rule, cidr);
    });
}

const regions = {
    "ap-northeast-1": {
        "vpc": "vpc-73016014",
        "subnet": "subnet-f3daebba",
        "cidr": "172.30.0.0/16"
    }/*,
    "eu-west-1": {
        "vpc": "vpc-5420e830",
        "subnet": "subnet-dbc879bf",
        "cidr": "172.30.0.0/16"
    },
    "us-east-1": {
        "vpc": "vpc-01311a6a321841d60",
        "subnet": "subnet-0d192be7ed6d2faa2",
        "cidr": "10.0.255.0/24"
    },
    "us-west-1": {
        "vpc": "vpc-420fa925",
        "subnet": "subnet-5d71ff06",
        "cidr": "172.30.0.0/16"
    },
    "us-west-2": {
        "vpc": "vpc-0e6cdc3402852ec63",
        "subnet": "subnet-070006c83fad19822",
        "cidr": "172.30.0.0/16"
    },
    "sa-east-1": {
        "vpc": "vpc-0d2362c5f3e332f13",
        "subnet": "subnet-00c372f7bb8d17f3f",
        "cidr": "10.0.0.0/16"
    }*/
}

Object.keys(regions).forEach(regionName => {
    const cidr = regions[regionName].cidr;
    updateRegionRules(regionName,cidr);
})


