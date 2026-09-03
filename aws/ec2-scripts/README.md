# Description

Provisioning scripts for the demo EC2 instances. The `setup-*` scripts run automatically on first boot and configure the host from the environment variables the template passes in. `newDNS.sh` is a maintenance script run by hand.

# Scripts

- `setup-nuxeo.sh` - Runs on first boot of a Nuxeo instance. Sets the hostname/FQDN, applies required kernel settings, clones the [nuxeo-presales-docker](https://github.com/nuxeo-sandbox/nuxeo-presales-docker) compose stack, writes its `.env`, and brings Nuxeo up. Progress is logged to `/var/log/nuxeo_install.log`.
- `setup-nev.sh` - Equivalent for a standalone NEV instance. Clones the [nuxeo-presales-nev](https://github.com/nuxeo-sandbox/nuxeo-presales-nev) compose stack, pulls Docker credentials from Secrets Manager, and brings NEV up. Progress is logged to `/var/log/nev_install.log`.
- `newDNS.sh` - Run by hand (as root) on an existing instance to move it to a new DNS name after you change its `dnsName` tag. It rewrites the FQDN across the host config (env file, Apache vhost, compose `.env`), reissues the TLS certificate via certbot, and optionally removes the old one. See the header comment in the script for the full procedure. Note: This is automatically installed on the instance.

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data can be stored in both SQL & NoSQL databases. The development of the Nuxeo Platform is mostly done by Hyland employees with an open development model. The source code, documentation, roadmap, issue tracker, testing, benchmarks are all public.

Organizations across industries such as financial services, insurance, manufacturing, healthcare, and government use Nuxeo to build a wide range of information management solutions on a single platform. Its schema-flexible metadata and content models let the same platform be adapted to different industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that enables thousands of organizations to deliver better experiences to the people they serve. Learn more at [hyland.com](https://www.hyland.com).
