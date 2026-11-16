# Description

Tooling required to reach the presales demo servers, which are only accessible via EC2 Instance Connect Endpoints (EICE). This lets you SSH and `scp` to an instance by its EC2 Name, dnsName, or host instead of its Instance ID.

# helper-scripts/unix

Wrappers around the AWS CLI that resolve an instance identifier (ID, Name, dnsName, or host) to an instance and act on it. All accept `-p <profile>` and `-r <region>`; run any script with no arguments to see full usage.

- `nxpssh.sh` - SSH into an instance, or `scp` files to/from it (`-d` to download instead of upload, `-u` to override the default `ubuntu` OS user).
- `nxpstart.sh` - Start a stopped instance.
- `nxpstop.sh` - Stop a running instance.

# ssh-config

Drop-in SSH client configuration that makes plain `ssh` and `scp` tunnel through an EC2 Instance Connect Endpoint, so a host matching an Instance ID (`i-*`) connects without a bastion or a permanent key. Provided for both platforms; use the copy matching your OS.

- `unix/config` and `windows/config` - SSH config snippets to add to your `~/.ssh/config` (matches `i-*` hosts and routes them through the proxy).
- `unix/aws-proxy.sh` and `windows/aws-proxy.bat` - Proxy helper invoked by the SSH config that pushes an ephemeral key and opens the EICE tunnel. Referenced by the config; not run directly.

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
