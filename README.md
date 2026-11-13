# CNQ Spark

Deploy CNQ Spark, a scratch file system for AI and cloud workloads, into your own Azure subscription. Mount it over NFS or SMB, reach it as S3-compatible object storage, or script it through REST, and point your workload at it.

**Not for production use. Spark does not provide data resiliency or protection. Use it for scratch and non-production data only. There is no support, and Spark is provided as-is.**

## What you get

- A single-VM file system that runs in your own Azure subscription.
- NFS, SMB, S3-compatible object and REST access. REST listens on port 8000. S3 is off by default: turn it on as described in Qumulo's [S3 API guide](https://docs.qumulo.com/administrator-guide/s3-api/configuring-using-s3-api.html).
- A web UI on the VM's private IP address, over HTTPS: watch the install, finish the first run, and manage shares, users, the admin password and the directory. `sudo spark` over SSH does the same in a terminal.
- A standard Canonical Ubuntu VM. There is no Qumulo image to find or trust: the template installs Spark when the VM first boots (see [What the VM installs and contacts](#what-the-vm-installs-and-contacts)).
- No public IP address. The template opens no inbound ports.
- A 1 TB plan: a 1,024 GiB Premium SSD data disk, 768 GiB usable.
- No license fee, and no feature or function expires.

## Cost

There is no software licensing fee. Standard Azure billing rates apply to the VM and the 1 TB disk, and you pay them to Microsoft through your own subscription.

<a id="before-you-deploy"></a>
## Before you start

You need:

- An Azure subscription where you can create a VM, a network interface and a managed disk.
- An existing virtual network and subnet, in the same subscription and region you deploy to. The portal lists them for you to pick.
- A way to reach that subnet, such as a VPN, Azure Bastion, or a VM on the same or a peered network. Spark gets no public IP address, so you cannot reach it from the internet.
- Outbound internet access from that subnet, such as a NAT gateway or a firewall. The VM downloads its software at install time and at first run, and it cannot do that without it.
- An SSH key. You can let the portal generate a key pair: it downloads the private key when you select Create. That needs permission to create SSH keys in the resource group. Or use a key stored in Azure, or your own public key.
- A size: Standard (Standard_D4s_v5) or Plus (Standard_D8s_v5).
- A Spark admin password you choose: 12 to 64 characters, with at least three of lower case, upper case, a digit and a symbol, and no spaces, double quotes (`"`) or backslashes (`\`).

Regions: any Azure region where the size you choose is available to your subscription.

## Deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FQumulo%2Fcnq-spark%2Fv0.10.1%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FQumulo%2Fcnq-spark%2Fv0.10.1%2FcreateUiDefinition.json)

The portal asks for your subscription, resource group and region, then six values:

1. **VM name.** This also becomes the cluster name: 2 to 15 characters, lowercase letters, numbers and hyphens, starting with a letter.
2. **Size.** Standard (`Standard_D4s_v5`) or Plus (`Standard_D8s_v5`).
3. **Virtual network and subnet.** Pick an existing virtual network in the same subscription and region, then one of its subnets.
4. **SSH key.** Generate a new key pair, and the portal downloads the private key when you select Create; keep it, it's how you sign in as `azureuser`. Generating one needs permission to create SSH keys in the resource group; without it, the key dialog stays greyed out. Or use a key stored in Azure, or paste your own public key.
5. **Email.** The VM sends it to Qumulo when it installs (see below).
6. **Spark admin password.** You sign in to the web UI as `admin` with it. 12 to 64 characters, with at least three of lower case, upper case, a digit and a symbol, and no spaces, double quotes (`"`) or backslashes (`\`). It is stored on the VM in `/etc/spark/admin-password`, readable by root only.

On the **Tags** tab you can add tags for the VM, its network interface and the Run Command that sets the admin password, if your organization requires them. The disks made with the VM take none: Azure has no way to tag them at creation.

The template creates a network interface with a private IP address only, and the VM: a standard Canonical Ubuntu 22.04 image with a 1,024 GiB Premium SSD data disk. It also adds a Run Command to the VM, `spark-admin-password`, which writes the admin password onto the VM. The password reaches the VM as the Run Command's protected parameter, not in the VM's custom data. The template creates no public IP address and no network security group. The network interface and both disks are set to delete with the VM.

### Deploy with your own AI agent

[RUNBOOK.md](RUNBOOK.md) is a plain-text walkthrough written for an AI agent. Give it to your own agent and it will walk you through the deployment in your own Azure sign-in. Qumulo does not run it for you.

## What the VM installs and contacts

The VM sets itself up on first boot. You don't sign in to it for this.

1. **Spark.** The VM downloads this release's Spark bundle from this repository and checks it against a sha256 fixed in the template. The bundle holds the compiled Spark program and its install scripts, not the program's source. It installs Docker from Ubuntu's package archive.
2. **Qumulo Core.** Spark asks Azure's metadata service for the VM's signed identity document and sends it, with the email from the deployment form, to a registration service that Qumulo runs outside your subscription. The service checks Microsoft's signature, records the VM, and returns a download link that expires in 15 minutes. Spark downloads Qumulo Core (about 600 MB) from Qumulo's Azure storage, checks its sha256, loads it into Docker and sets up the file system. This takes a few minutes after the VM starts.
3. **First run.** The web UI, or `sudo spark` over SSH, shows the setup's progress, then the first run. When you first sign in to the web UI, or when the first-run wizard opens in `sudo spark`, Spark registers the cluster with Qumulo under the same email; it doesn't ask for the email again.

<a id="what-spark-sends-to-qumulo"></a>**What Qumulo receives:** the email, and Microsoft's signed identity document for the VM, which names its VM ID and subscription ID, with the region and the Core version. Qumulo keeps the email, the VM ID, a hash of the subscription ID (not the ID itself), the region, the Core version, the cluster ID once the first run starts, and when each arrived, for a year after the VM was last seen. Qumulo uses them to count Spark installs. Nothing from your file system or your data is sent. Qumulo does not sign in to your subscription, and registering does not put you on a sales or marketing list.

**Outbound access:** the VM needs outbound access from its subnet to these hosts:

| Host | Port | For |
|---|---|---|
| `github.com` and `release-assets.githubusercontent.com` | HTTPS 443 | The Spark bundle, from this repository's release |
| `archive.ubuntu.com` and `security.ubuntu.com` (the VM's own Azure mirror is the fallback) | HTTP 80 | Docker, from Ubuntu's package archive |
| `spark-register.sedemo.qumulo.com` | HTTPS 443 | Qumulo's registration service |
| `qumulosparkcore.blob.core.windows.net` | HTTPS 443 | The Qumulo Core download |

Azure's metadata service is reachable from inside the VM with no setup. Subnets in new virtual networks are private by default, so you usually have to add outbound access yourself. Microsoft recommends a [NAT gateway](https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access); a firewall with a route also works.

## After you deploy

The deployment's output `webUrl` is the web UI's address, `https://<the VM's private IP>/`. Open it from a machine inside your network. While the install is still running, the page shows its progress without a sign-in. Then sign in as `admin` with the password you entered in the form, and the first run opens: Password (optional), Shares, Users, Directory, Finish.

The web UI listens on port 443, and port 80 only redirects to it, on the VM's private IP address. The certificate is self-signed, so the browser warns the first time. To check it, compare its fingerprint with the one in the SSH login message or in `sudo spark web status`. The web UI is on by default. Anyone your network lets reach the VM can reach its sign-in page, so limit that with your own network rules, or turn it off with `sudo spark web off` (it stays off after a restart; `sudo spark web on` turns it back on).

Or connect over SSH as `azureuser` and run `sudo spark`: the same progress and first run, in a terminal. Then check that Spark is ready:

```
sudo spark status --json
```

Exit code 0 means ready. The admin password is the one you entered in the form, until you change it in the web UI or `sudo spark`. The VM keeps the current one in `/etc/spark/admin-password`; read it with `sudo cat /etc/spark/admin-password`.

Mount the file system from a workload in the same network:

```
sudo mount -t nfs <spark-ip>:/<export> /mnt/spark
```

First boot creates one NFS export, `/`, and one SMB share, `Files`. In the web UI or `sudo spark` you can add more exports and shares, or remove them.

From Windows, map the SMB share:

```
net use Z: \\<spark-ip>\Files
```

## Remove Spark

Delete the VM. Its network interface and both disks are deleted with it. [RUNBOOK.md](RUNBOOK.md) has the exact command.

```
az vm delete -g <resource-group> -n <name> --yes
```

If the portal generated your SSH key, Azure also saved its public key as an SSH key resource in the resource group. It stays after the VM is deleted. Delete it too if you no longer need it. List the key names, then delete yours:

```
az sshkey list -g <resource-group> --query "[].name" -o tsv
az sshkey delete -g <resource-group> -n <key name> --yes
```

## Support and contact

There is no support for Spark, and this repository is provided as-is. For licensing, legal or privacy questions, [contact Qumulo](https://qumulo.com/contact). To report a security problem, see [SECURITY.md](SECURITY.md).

## Terms and license

Use of Spark is subject to the [Qumulo end user license agreement](https://qumulo.com/terms-hub). The files in this repository (the deployment template, portal form, runbook and scripts) are licensed under the license in [LICENSE](LICENSE). That license covers these files only. It does not cover, and grants no rights to, the Spark program attached to this repository's releases, Qumulo Core, or any other Qumulo software.
