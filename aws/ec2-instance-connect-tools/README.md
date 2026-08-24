# Description

Tooling required to reach the presales demo servers, which are only accessible via EC2 Instance Connect Endpoints (EICE). This lets you SSH and `scp` to an instance by its EC2 Name, dnsName, or host instead of its Instance ID.

# helper-scripts/unix

Wrappers around the AWS CLI that resolve an instance identifier (ID, Name, dnsName, or host) to an instance and act on it. All accept `-p <profile>` and `-r <region>`; run any script with no arguments to see full usage.

- `nxpssh.sh` — SSH into an instance, or `scp` files to/from it (`-d` to download instead of upload, `-u` to override the default `ubuntu` OS user).
- `nxpstart.sh` — Start a stopped instance.
- `nxpstop.sh` — Stop a running instance.

# ssh-config

Drop-in SSH client configuration that makes plain `ssh` and `scp` tunnel through an EC2 Instance Connect Endpoint, so a host matching an Instance ID (`i-*`) connects without a bastion or a permanent key. Provided for both platforms; use the copy matching your OS.

- `unix/config` and `windows/config` — SSH config snippets to add to your `~/.ssh/config` (matches `i-*` hosts and routes them through the proxy).
- `unix/aws-proxy.sh` and `windows/aws-proxy.bat` — Proxy helper invoked by the SSH config that pushes an ephemeral key and opens the EICE tunnel. Referenced by the config; not run directly.

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.

Learn more at https://www.hyland.com/products/nuxeo-platform.
