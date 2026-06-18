# Azure Load-Balanced VM Scale Set (Infrastructure as Code)

Bicep template that deploys a highly-available web tier on Microsoft Azure. Built while studying for **AZ-104** to practise Infrastructure as Code, virtual networking, and least-privilege network security.

## Architecture

```
Internet
   |
[ Public IP (Standard) ]
   |
[ Load Balancer LB-01 ]  --- health probe (TCP/80), rule 80 -> 80
   |
[ Backend pool ]
   |
[ VM Scale Set (2x Ubuntu 24.04, Trusted Launch) ]
   |
[ Subnet 172.16.0.0/24 ] in [ VNet 172.16.0.0/16 ]
   |
[ NSG ]  --- inbound HTTP/80 (any), mgmt/8080 (trusted IP only)
```

## Resources deployed

| Resource | Detail |
|----------|--------|
| Virtual Network | `vnet-eastus`, address space `172.16.0.0/16` |
| Subnet | `snet-eastus-1`, `172.16.0.0/24` |
| Network Security Group | Inbound HTTP/80 (any), management 8080 restricted to a trusted CIDR |
| Public IP | Standard SKU, static |
| Load Balancer | Standard SKU, frontend + backend pool, TCP/80 rule, TCP/80 probe |
| VM Scale Set | 2 instances, Ubuntu 24.04, SSH-key auth, Trusted Launch (Secure Boot + vTPM) |

## Parameters

| Parameter | Purpose |
|-----------|---------|
| `location` | Azure region (defaults to the resource group's region) |
| `sshPublicKey` | SSH public key for the `azureuser` admin account |
| `adminSourceAddressPrefix` | CIDR allowed to reach the 8080 management rule, e.g. `1.2.3.4/32` |

## Deploy

```bash
az group create -n rg-webtier -l eastus

az deployment group create \
  -g rg-webtier \
  --template-file main.bicep \
  --parameters sshPublicKey="ssh-rsa AAAA..." adminSourceAddressPrefix="YOUR_IP/32"
```

Tear down to avoid charges:

```bash
az group delete -n rg-webtier --yes
```

## What I learned

- Using a **VM Scale Set** behind a **Standard Load Balancer** for horizontal scale and availability.
- Designing **NSG rules** with least privilege: HTTP open to the world, management locked to a single source IP.
- Wiring resource dependencies in Bicep (`resourceId()`, `dependsOn`) so the LB, subnet and NSG attach correctly to the VMSS NICs.
- Parameterising **secrets and environment-specific values** (SSH key, source IP) out of the template instead of hard-coding them.
- Enabling **Trusted Launch** (Secure Boot + vTPM) for the VM instances.

## Security note

This template is parameterised so no real credentials, subscription IDs, or personal IPs are committed. Supply your own values at deploy time.
