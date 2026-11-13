# CNQ Spark deployment runbook (for AI agents)

This file is written for an AI agent. A person gives it to you so that you can walk them through deploying CNQ Spark into their own Azure subscription. Qumulo does not run this for you and does not see what you do. The deployed VM does contact a Qumulo registration service while it installs; see "What gets deployed".

Spark is for scratch and non-production data only. It has no data protection, no support, and is provided as-is.

## Rules

Follow these without exception. If a step cannot be done within them, stop and tell the person.

- The person signs in to Azure themselves. Never ask for, accept or store a password, token or key.
- Use only the template at the pinned URL below. Do not edit it, write a different one, or add resources to it. Outside it, you may create only these, each after a clear yes: a new resource group (step 2), a NAT gateway and its public IP address for an existing subnet when the person asks (step 2), and the network pieces in "No usable virtual network".
- Do not create a public IP address for the VM or attach one to it. The only public IP address you may create is a NAT gateway's, which carries outbound traffic only, in the two cases in step 2. Do not open inbound ports 22, 80, 443, 445, 2049 or 8000 to the internet. Do not change the network security group to allow them.
- Use the SSH public key only. Never read, print or upload a private key. If the person has no key, tell them how to create one and let them run it.
- The person chooses the Spark admin password and writes it into a parameters file themselves (step 2). Never ask for the password, suggest or generate one, or open, read, print, copy or upload that file. Pass it to Azure only as the file's path, `--parameters "$PW_FILE"`, never with `@` in front: with `@`, the Azure CLI prints the file's contents if the file is not valid JSON.
- Before anything is created or deleted, show the person exactly what will change and wait for a clear yes.
- Before the person deploys, tell them what Spark sends to Qumulo (see "What gets deployed") and that the subnet needs outbound internet access.
- Never type, guess or supply the person's email address. Ask for their email and pass exactly what they type as `workEmail`.
- If a command fails, show the exact error and stop. Do not retry with different values, and do not fall back to another image, region, template or method.

## What gets deployed

One VM and one network interface with a private IP address only, with one empty 1,024 GiB Premium SSD data disk, and a Run Command on the VM, `spark-admin-password`, that writes the admin password onto it as a protected parameter. No public IP address and no network security group. The VM runs a standard Canonical Ubuntu 22.04 image. The software has no license fee. Azure bills the person for the VM and the disk at standard rates. The network interface and both disks are deleted with the VM.

Spark serves a web UI on the VM's private IP address: HTTPS on port 443, and port 80 only redirects to it. It is on by default. The deployment's `webUrl` output is its address.

What the VM installs and contacts, on first boot, with no sign-in:

- It downloads this release's Spark bundle from the repository, checks its sha256 against the template, and installs Docker from Ubuntu's package archive.
- Spark sends Azure's signed VM identity document and the email from the deployment to a registration service that Qumulo runs, then downloads Qumulo Core from Qumulo's Azure storage. This takes a few minutes after the VM starts.
- Qumulo keeps the email, the VM ID, a hash of the subscription ID, the region, the Core version, and later the cluster ID, for a year after the VM was last seen. None of the person's data is sent. Qumulo does not sign in to the subscription.

The subnet needs outbound access to `github.com` and `release-assets.githubusercontent.com` (HTTPS), `archive.ubuntu.com` and `security.ubuntu.com` (HTTP), `spark-register.sedemo.qumulo.com` (HTTPS) and `qumulosparkcore.blob.core.windows.net` (HTTPS).

Template URL (pinned to a release):

```
TEMPLATE_URL=https://raw.githubusercontent.com/Qumulo/cnq-spark/v0.10.1/azuredeploy.json
```

## Step 1. Confirm the Azure sign-in

Ask the person to sign in with `az login` if they have not. Then run:

```
az account show --query "{name:name, id:id}" -o json
```

Show the result and ask: "Is this the subscription you want Spark in?" If not, help them switch with `az account set --subscription <id>`. Do not continue until they confirm.

## Step 2. Collect the values

Ask the person for each of these. Do not pick values for them.

1. **Resource group.** An existing one, or a new one. Creating a resource group is a change, so get a yes first. Create a new one right before the first command that needs it: the name check in "No usable virtual network", or the validate in step 3. By then the size check (item 2) has passed and you have the tags, if their organization requires them (item 8); before step 3's validate, the subnet checks in step 2 have passed too. First check that the name is free: `az group exists -n "$RG"` must print `false`. If it prints `true`, a group with that name already exists, and creating it would change that group: stop and tell the person. Do not reuse or change it. Then run `az group create -n "$RG" -l "$LOC" -o none`, with `--tags` for those tags. Whenever you stop after creating it, tell the person the group exists and stays unless they ask you to delete it. Until it exists, Azure answers `ResourceGroupNotFound` for anything in it.
2. **Region.** The region of the subnet's virtual network (item 4), as `LOC`. If the person gives you a subnet ID, read the region from it: `az network vnet show --ids "${SUBNET%/subnets/*}" --query location -o tsv`. Spark runs in any Azure region that offers the chosen size to this subscription. Check it once you have the region and the size, with `SIZE` set to `Standard_D4s_v5` for standard or `Standard_D8s_v5` for plus:

   ```
   az vm list-skus -l "$LOC" --size "$SIZE" --resource-type virtualMachines --all \
     --query "[?name=='$SIZE'].{size:name, blocked:restrictions[?type=='Location'].reasonCode}" -o json
   ```

   It must print one entry whose `blocked` list is empty. No entry means the size isn't offered in that region; a reason under `blocked`, such as `NotAvailableForSubscription`, means the region is closed to this subscription for that size. In either case, show the person and stop. Restrictions of type `Zone` don't matter: they apply only to a VM pinned to that zone, and this runbook deploys without one.
3. **VM name.** It also becomes the Spark cluster name. 2 to 15 characters: lowercase letters, numbers and hyphens, starting with a letter.
4. **Subnet.** The full resource ID of an existing subnet. If they do not have it, list the virtual networks in this subscription, in every region, so that a network in another region is not missed:

   ```
   az network vnet list --query "[].{name:name, resourceGroup:resourceGroup, region:location}" -o table
   ```

   Then list the subnets of the one they choose, and let them pick:

   ```
   az network vnet subnet list -g <its resource group> --vnet-name <its name> --query "[].{name:name, id:id}" -o table
   ```

   If the network they want is in another subscription, go back to step 1 and switch to that subscription: a network interface cannot join a subnet in a different subscription. If they have no network they can use, see "No usable virtual network" below.
5. **SSH public key file.** The path to a `.pub` file. Refuse a path that does not end in `.pub`.
6. **Email.** The person types it. Pass it exactly as typed, as `EMAIL`.
7. **Admin password file.** The path to a parameters file that the person writes themselves, holding the Spark admin password they choose. They sign in to the web UI as `admin` with it. The password must be 12 to 64 characters, with at least three of lower case, upper case, a digit and a symbol, and no spaces, double quotes (`"`) or backslashes (`\`). The file looks like this:

   ```json
   {
     "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
     "contentVersion": "1.0.0.0",
     "parameters": {
       "adminPassword": { "value": "<the Spark admin password>" }
     }
   }
   ```

   Tell the person to create it in their own editor, not through you, and to make it readable only by them (on Linux or macOS, `chmod 600 <file>`).

   Ask only for the file's path, as `PW_FILE`. You may check that it exists (`test -f "$PW_FILE"`), but never open, read, print, copy or upload it.
8. **Tags**, only if their organization requires them. Ask which tags, and add `tagsByResource='{"Microsoft.Compute/virtualMachines": {...}, "Microsoft.Compute/virtualMachines/runCommands": {...}, "Microsoft.Network/networkInterfaces": {...}}'` to the `--parameters` below with exactly what they give. The Run Command that sets the admin password takes its own tags. The disks made with the VM take no tags.

Also ask for the size: `standard` (Standard_D4s_v5) or `plus` (Standard_D8s_v5).

Then check these before going on:

- The subnet is in the same subscription as the one confirmed in step 1. A network interface cannot join a subnet in a different subscription.
- The subnet's virtual network is in the region chosen in item 2.
- The subnet has outbound internet access. The install downloads software from GitHub, Ubuntu and Qumulo, so without it the deployment will not finish setting up. Ask the person how the subnet reaches the internet (a NAT gateway, or a firewall with a route). You can look at the subnet:

  ```
  az network vnet subnet show --ids "$SUBNET" --query "{nat:natGateway.id, routeTable:routeTable.id, defaultOutboundAccess:defaultOutboundAccess}" -o json
  ```

  If there is no NAT gateway and no route table, tell the person the install is likely to fail and stop. Do not add a public IP address to the VM. Adding a NAT gateway is a separate change that is not part of this template; do it only if the person asks.
  - It changes outbound traffic for everything in that subnet, so the person must own the network or have its owner's agreement.
  - It goes in their resource group, in the subnet's region.
  - Use the name check, the public IP and NAT gateway commands, and the failure handling in "No usable virtual network". Leave out the virtual network.
  - Tell them that Azure bills the NAT gateway and its public IP address by the hour, and the NAT gateway by the data it processes, and that both stay when Spark is removed.
  - Show them exactly what it creates and wait for a clear yes. Then attach it:

    ```
    az network vnet subnet update --ids "$SUBNET" --nat-gateway "$(az network nat gateway show -g "$RG" -n "$NAME-nat" --query id -o tsv)" -o none
    ```
- The person already has a network path to that subnet, such as a VPN, Azure Bastion, or a VM on the same or a peered network. Spark gets no public IP address, so without a path they cannot reach it. If they have none, stop and say so. Do not offer to add a public IP address.

### No usable virtual network

Spark deploys into an existing virtual network. If the person has none they can use, tell them what it needs:

- a subnet in the chosen region, in this subscription;
- outbound internet access from that subnet, such as a NAT gateway or a firewall with a route;
- a way for them to reach the subnet, such as a VPN, Azure Bastion, or peering with a network they already reach. Spark gets no public IP address.

Ask how they will reach a new network first. A new virtual network is reachable only through a path they set up after it exists, such as peering, Azure Bastion or a VPN. If they have no plan for one, stop: Spark could not be used. Do not offer a public IP address for the VM. There is no support for Spark, so do not send the person to Qumulo for a network or a path.

You may then offer to create a virtual network with one subnet and a NAT gateway. Ask the person for:

- the region, as `LOC`. Check the size there as in item 2 before anything else;
- the virtual network's address range, as `VNET_RANGE`, and the subnet's range inside it, as `SUBNET_RANGE`. They must not overlap networks the person will connect from or peer with. Do not pick them.

If the resource group from item 1 is new, create it now, in `LOC`, as item 1 says, after the size check above. The names below come from the VM name. Check that none of them is taken:

```
az network vnet show -g "$RG" -n "$NAME-vnet" --query id -o tsv
az network public-ip show -g "$RG" -n "$NAME-nat-ip" --query id -o tsv
az network nat gateway show -g "$RG" -n "$NAME-nat" --query id -o tsv
```

Each must fail with `ResourceNotFound`. If one prints an ID, a resource with that name already exists, and a create command would change it: stop and tell the person. Do not reuse or change it. If one fails with another error, show it and stop.

Show the person the four resources, in their resource group and region:

- the virtual network `$NAME-vnet`;
- its subnet `spark`, attached to the NAT gateway;
- the public IP address `$NAME-nat-ip`, used by the NAT gateway for outbound traffic only. Nothing can connect in through it, and the VM gets no public IP address;
- the NAT gateway `$NAME-nat`.

Tell them that:
- Azure bills the NAT gateway and its public IP address by the hour, and the NAT gateway by the data it processes;
- these stay when Spark is removed;
- Spark is not deployed until their path to the new network works.

Wait for a clear yes. If their organization requires tags (item 8), add `--tags` with the same tags to each `create` command. Create the network first: it costs nothing, and Azure checks the address ranges as it creates it. Then:

```
az network vnet create -g "$RG" -n "$NAME-vnet" -l "$LOC" --address-prefixes "$VNET_RANGE" \
  --subnet-name spark --subnet-prefixes "$SUBNET_RANGE" -o none
az network public-ip create -g "$RG" -n "$NAME-nat-ip" -l "$LOC" --sku Standard --allocation-method Static -o none
az network nat gateway create -g "$RG" -n "$NAME-nat" -l "$LOC" --public-ip-addresses "$NAME-nat-ip" -o none
az network vnet subnet update -g "$RG" --vnet-name "$NAME-vnet" -n spark --nat-gateway "$NAME-nat" -o none
SUBNET=$(az network vnet subnet show -g "$RG" --vnet-name "$NAME-vnet" -n spark --query id -o tsv)
```

If a command fails, show the error and stop. Run the three `show` commands from the name check again to see what was created, and tell the person. Anything already created stays, and the public IP address and NAT gateway bill until deleted. Offer to delete what was created, using the commands in "Remove Spark", and do it only after a clear yes. Do not retry with other values on your own.

Then the person sets up their path to `$NAME-vnet`, outside this runbook. Wait until they say it works. If it isn't ready yet, stop here: the network stays, and they can come back later and continue with this subnet. Once it works, go back to the checks above with this subnet.

## Step 3. Validate and preview

If the resource group from item 1 is new and doesn't exist yet, create it first, as item 1 says.

These commands print only the result and the list of resources, never the parameters.

```
az deployment group validate \
  --resource-group "$RG" \
  --template-uri "$TEMPLATE_URL" \
  --parameters location="$LOC" vmName="$NAME" subnetId="$SUBNET" \
    sshPublicKey="$(cat "$PUBKEY_PATH")" compute="$COMPUTE" workEmail="$EMAIL" \
  --parameters "$PW_FILE" \
  --query properties.provisioningState -o tsv

az deployment group what-if \
  --resource-group "$RG" \
  --template-uri "$TEMPLATE_URL" \
  --parameters location="$LOC" vmName="$NAME" subnetId="$SUBNET" \
    sshPublicKey="$(cat "$PUBKEY_PATH")" compute="$COMPUTE" workEmail="$EMAIL" \
  --parameters "$PW_FILE" \
  --result-format ResourceIdOnly
```

Show the person the list of resources that will be created. Remind them that Azure bills the VM and the disk, and that the Azure portal's cost estimate for the chosen size is the number to go by. Ask for a clear yes.

## Step 4. Deploy

```
az deployment group create \
  --name "spark-$NAME" \
  --resource-group "$RG" \
  --template-uri "$TEMPLATE_URL" \
  --parameters location="$LOC" vmName="$NAME" subnetId="$SUBNET" \
    sshPublicKey="$(cat "$PUBKEY_PATH")" compute="$COMPUTE" workEmail="$EMAIL" \
  --parameters "$PW_FILE" \
  --query properties.outputs.webUrl.value -o tsv
```

It prints the web UI's address, `https://<private-ip>/`. If the deployment fails at `spark-admin-password` with "the admin password breaks Spark's rules", show the person the error and let them fix their file against the rules in step 2. Run step 4 again only after they say it's fixed.

## Step 5. Check the result

Confirm the VM has no public IP address. This should print `null`:

```
az network nic show -g "$RG" -n "nic-$NAME" \
  --query "ipConfigurations[0].publicIPAddress" -o json
```

Get the private IP address:

```
az vm list-ip-addresses -g "$RG" -n "$NAME" \
  --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv
```

Tell the person the private IP address and the web UI's address. The install runs on first boot and takes a few minutes after the deployment finishes.

## Step 6. Connect and finish setup (the person does this)

From a machine that can reach the private IP address, the person opens the web UI at `https://<private-ip>/`. While the install is still running, the page shows its progress without a sign-in. Then they sign in as `admin` with the password from their parameters file, and the first run opens: Password (optional), Shares, Users, Directory, Finish. When they first sign in, Spark registers the cluster with Qumulo under the same email.

The certificate is self-signed, so the browser warns the first time. To check it, the person compares its fingerprint with the one in the SSH login message or in `sudo spark web status`. Anyone their network lets reach the VM can reach the sign-in page; they can turn the web UI off with `sudo spark web off`, and back on with `sudo spark web on`.

Or the person connects over SSH as `azureuser` and runs `sudo spark`, which does the same in a terminal. When its first-run wizard opens, Spark registers the cluster with Qumulo under the same email. Then they run:

```
sudo spark status --json
```

Exit code 0 means Spark is ready. If it is not ready yet, wait a few minutes and run it again.

The admin password is the one in the person's parameters file, until they change it in the web UI or `sudo spark`. The VM keeps the current one in `/etc/spark/admin-password`, readable by root only. Do not read it for them or repeat it.

Mount the file system from a workload on the same network:

```
sudo mount -t nfs <private-ip>:/<export> /mnt/spark
```

First boot creates one NFS export, `/`, and one SMB share, `Files`. In the web UI or `sudo spark` the person can add more exports and shares, or remove them.

## Finish without SSH (optional)

If the person can't reach the VM, or asks you to finish for them, you can finish the first run through Azure's Run Command, which needs no network path to the VM. `spark first-run` registers the cluster with the email from the deployment and marks the first run done, so the web UI and `sudo spark` later open on Home. It keeps the default NFS export and SMB share, and the admin password from the person's parameters file. It does not add users or join Active Directory; the person does those later in the web UI or `sudo spark`.

Tell the person what it does and wait for a clear yes. Then wait for the install to finish. The install usually takes about 15 minutes; this checks up to 20 times, a minute apart, and stops at the first Azure error:

```
ready=no
for i in $(seq 1 20); do
  msg=$(az vm run-command invoke -g "$RG" -n "$NAME" --command-id RunShellScript \
    --scripts 'test -f /etc/spark/first-boot.done && echo SPARK_READY' \
    --query 'value[0].message' -o tsv) || { ready=error; break; }
  case "$msg" in *SPARK_READY*) ready=yes; break ;; esac
  sleep 60
done
echo "ready=$ready"
```

Go on only if it prints `ready=yes`. If it prints `ready=error`, show the person the Azure error and stop. If it prints `ready=no`, stop and tell the person that setup hasn't finished. In both cases, don't finish the first run and don't retry on your own. The person can watch the progress in the web UI, or sign in over SSH, where the login message says which logs to read.

Then finish the first run and check the result:

```
az vm run-command invoke -g "$RG" -n "$NAME" --command-id RunShellScript \
  --scripts '/usr/local/bin/spark first-run && /usr/local/bin/spark status --json' \
  --query 'value[0].message' -o tsv
```

Run Command reports `Enable succeeded` even when the script fails, so read the output: it must contain `first run done` (or `first run already done`), followed by the status. If it doesn't, show the person the output and stop. It is safe to run again. Never read or print `/etc/spark/admin-password` this way.

## Remove Spark

Only if the person asks. The VM's network interface and both disks are deleted with the VM, so the VM is the only thing to delete.

Show the person exactly what will be deleted: the VM, its network interface `nic-$NAME` and its two disks. Wait for a yes. Then:

```
az vm delete -g "$RG" -n "$NAME" --yes
```

Never delete the resource group unless the person created it for Spark and says so. If this runbook created it (item 1), you may delete it when the person asks: first show that it is empty (`az resource list -g "$RG" -o table` lists nothing), then get a yes, then `az group delete -n "$RG" --yes`.

If you created the network pieces in "No usable virtual network", they stay after the VM is deleted. Delete them only if the person asks, after showing them the list and getting a yes. The network can be deleted only after the person removes what they added to it, such as a Bastion host, a VPN gateway or peerings. Do not delete those for them. Then, in this order:

```
az network vnet delete -g "$RG" -n "$NAME-vnet"
az network nat gateway delete -g "$RG" -n "$NAME-nat"
az network public-ip delete -g "$RG" -n "$NAME-nat-ip"
```

If you added a NAT gateway to an existing subnet (step 2), it stays after the VM is deleted, and it can't be deleted while it is attached. Remove it only if the person asks. Detaching it ends that outbound path for everything in the subnet, so show them that and get a yes. Then:

```
az network vnet subnet update --ids "$SUBNET" --remove natGateway -o none
az network nat gateway delete -g "$RG" -n "$NAME-nat"
az network public-ip delete -g "$RG" -n "$NAME-nat-ip"
```

Never delete their virtual network or subnet.

## If something goes wrong

Stop and show the error. Common causes: the subnet is in a different subscription or region, the person lacks permission to create a VM there, the subnet has no outbound internet access, or the Ubuntu image is not available in the chosen region. Do not work around any of them. There is no support for Spark, so the person decides how to proceed.

Things the person can check on the VM, over SSH:

- `sudo spark web status` shows whether the web UI runs, its ports and its certificate fingerprint. Its logs: `sudo journalctl -u spark-web -u spark-web-helper`.
- If the admin password never reached the VM, first boot stops after 30 minutes and says why. Once the cause is fixed, `sudo systemctl restart spark-first-boot` starts it again.
