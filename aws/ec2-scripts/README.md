# Description

Provisioning scripts for the demo EC2 instances. The `setup-*` scripts run automatically on first boot and configure the host from the environment variables the template passes in. `newDNS.sh` is a maintenance script run by hand.

# Scripts

- `setup-nuxeo.sh` — Runs on first boot of a Nuxeo instance. Sets the hostname/FQDN, applies required kernel settings, clones the [nuxeo-presales-docker](https://github.com/nuxeo-sandbox/nuxeo-presales-docker) compose stack, writes its `.env`, and brings Nuxeo up. Progress is logged to `/var/log/nuxeo_install.log`.
- `setup-nev.sh` — Equivalent for a standalone NEV instance. Clones the [nuxeo-presales-nev](https://github.com/nuxeo-sandbox/nuxeo-presales-nev) compose stack, pulls Docker credentials from Secrets Manager, and brings NEV up. Progress is logged to `/var/log/nev_install.log`.
- `newDNS.sh` — Run by hand (as root) on an existing instance to move it to a new DNS name after you change its `dnsName` tag. It rewrites the FQDN across the host config (env file, Apache vhost, compose `.env`), reissues the TLS certificate via certbot, and optionally removes the old one. See the header comment in the script for the full procedure. Note: This is automatically installed on the instance.

# About Nuxeo
[Nuxeo](https://www.hyland.com/products/nuxeo-platform), leading Content Services Platform, is reinventing enterprise content management (ECM) and digital asset management (DAM). Nuxeo is fundamentally changing how people work with data and content to realize new value from digital information. Its cloud-native platform has been deployed by large enterprises, mid-sized businesses and government agencies worldwide. Customers like Verizon, Electronic Arts, ABN Amro, and the Department of Defense have used Nuxeo's technology to transform the way they do business.

Learn more at https://www.hyland.com/products/nuxeo-platform.
