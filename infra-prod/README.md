# Production template — Fabric tenant Private Link landing (no on-prem)

A trimmed, production-oriented variant of the lab in [`../infra`](../infra). It deploys **only** the
Azure-side Fabric **tenant Private Link** landing and connects to your **real** corporate network —
it does **not** create the simulated on-prem VNet, VPN gateways, VMs, or VNet-to-VNet connections.

The Fabric capacity is **dual-mode**: **use an existing capacity** or **create a new one**.

> Full architecture, DNS design, lockout pre-flight, gateway egress, and feature-availability
> details are in [`../docs/fabric-private-link-vpn-runbook.md`](../docs/fabric-private-link-vpn-runbook.md).

## What it deploys

- One **services VNet** with `snet-pe` (private endpoint) and — when `deployDnsResolver=true` —
  `snet-dnspr-inbound`.
- **Azure DNS Private Resolver** inbound endpoint (so your on-prem DNS can conditionally forward
  Fabric names privately). Optional.
- The **3 Fabric/Power BI private DNS zones** (`privatelink.analysis.windows.net`,
  `privatelink.pbidedicated.windows.net`, `privatelink.prod.powerquery.microsoft.com`) + VNet links.
- The **tenant Private Link service** (`Microsoft.PowerBI/privateLinkServicesForPowerBI`) + the
  **tenant private endpoint** (`groupId: tenant`) + DNS zone group.
- **Fabric capacity**: referenced (existing) **or** created (new) — your choice.
- **Optional** peering to your existing connectivity hub (ExpressRoute / Site-to-Site VPN).

## What it does NOT deploy

No simulated on-prem network, VPN gateways, VMs, or VNet-to-VNet connections. Connectivity to
on-prem is **your existing ExpressRoute / Site-to-Site VPN**, peered to the services VNet.

## Prerequisites

1. **Enable tenant Azure Private Link** in the Fabric admin portal first (Tenant settings → Advanced
   networking) — `privateLinkServicesForPowerBI` fails to create until it is on.
2. You are a **Fabric administrator** (for the tenant setting and, in CREATE mode, capacity admin).
3. EXISTING mode: the capacity resource ID. CREATE mode: at least one `fabricCapacityAdmins` entry.

## Capacity modes

| Mode | Set | Result |
| --- | --- | --- |
| **Use existing** (default) | `createFabricCapacity=false` + `existingFabricCapacityResourceId=<id>` | References your capacity; deploys only the private-link landing. |
| **Create new** | `createFabricCapacity=true` + `fabricCapacityAdmins=[...]` (+ optional `newFabricCapacitySku`, `newFabricCapacityName`) | Creates the capacity **and** the private-link landing. |

## Deploy

### azd (subscription scope, creates the RG)

```bash
azd env new fabricpl-prod
azd env set AZURE_LOCATION eastus2
# --- choose ONE capacity mode ---
# Existing:
azd env set CREATE_FABRIC_CAPACITY false
azd env set EXISTING_FABRIC_CAPACITY_ID "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Fabric/capacities/<name>"
# New:
# azd env set CREATE_FABRIC_CAPACITY true
# azd env set FABRIC_CAPACITY_ADMIN  admin@contoso.com
# azd env set FABRIC_CAPACITY_SKU    F2
azd provision --no-prompt   # azd uses infra-prod via this folder's azure.yaml override, or run az below
```

### az (subscription scope)

```bash
# Existing capacity:
az deployment sub create --location eastus2 \
  --template-file infra-prod/main.bicep \
  --parameters environmentName=fabricpl-prod location=eastus2 \
    createFabricCapacity=false \
    existingFabricCapacityResourceId="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Fabric/capacities/<name>"

# New capacity:
az deployment sub create --location eastus2 \
  --template-file infra-prod/main.bicep \
  --parameters environmentName=fabricpl-prod location=eastus2 \
    createFabricCapacity=true newFabricCapacitySku=F2 \
    fabricCapacityAdmins='["admin@contoso.com"]'
```

### az (resource-group scope, compiled ARM)

```bash
az group create -n rg-fabricpl-prod -l eastus2
az deployment group create -g rg-fabricpl-prod \
  --template-file infra-prod/azuredeploy.json \
  --parameters @infra-prod/azuredeploy.parameters.json
```

### Validate before applying

```bash
az bicep build --file infra-prod/resources.bicep --outfile infra-prod/azuredeploy.json
az deployment sub what-if --location eastus2 --template-file infra-prod/main.bicep \
  --parameters environmentName=fabricpl-prod location=eastus2 createFabricCapacity=false \
    existingFabricCapacityResourceId="<id>"
```

## Post-deploy (manual, not in IaC)

1. **Approve** the private endpoint connection if not auto-approved (PLS → Private endpoint
   connections).
2. **Peer** the services VNet to your connectivity hub if you didn't pass `peerToHubVnetResourceId`
   — and create the **reciprocal hub → services** peering with `allowGatewayTransit=true` on the hub.
3. **On-prem DNS:** add conditional forwarders for the parent domains (output
   `onPremForwarderDomains`) pointing at the resolver inbound IP (output `resolverInboundIp`):
   `analysis.windows.net`, `pbidedicated.windows.net`, `prod.powerquery.microsoft.com`,
   `powerbi.com`, `fabric.microsoft.com`. Use the **broad parents** to avoid the OneLake DNS leak.
4. **Verify private resolution** from a machine on your network (all Fabric FQDNs → the PE private
   IPs), then optionally enable **Block Public Internet Access** for VPN-only access. **Run the
   lockout pre-flight first** — see the runbook §9.

## Parameters

| Parameter | Default | Notes |
| --- | --- | --- |
| `createFabricCapacity` | `false` | `false`=use existing, `true`=create new. |
| `existingFabricCapacityResourceId` | `''` | Required when `createFabricCapacity=false`. |
| `newFabricCapacitySku` / `newFabricCapacityName` | `F2` / auto | CREATE mode. |
| `fabricCapacityAdmins` | `[]` | Required (≥1) when `createFabricCapacity=true`. |
| `namePrefix` | `fabpl` | Resource name prefix. |
| `location` | RG region | Region for VNet/resolver/PE (+capacity when created). |
| `vnetAddressSpace` / `peSubnetPrefix` / `resolverSubnetPrefix` | `10.40.0.0/16` / `…1.0/24` / `…2.0/28` | Must not overlap your networks. |
| `deployDnsResolver` | `true` | Deploy the resolver inbound endpoint. |
| `resolverInboundIp` | `10.40.2.4` | Inside `resolverSubnetPrefix`. |
| `peerToHubVnetResourceId` | `''` | Optional peering to your hub. |
| `useRemoteGateways` | `true` | When peering, use the hub's ExpressRoute/VPN gateway (needs hub gateway transit). |
| `tenantId` | deployment tenant | For the Private Link service. |

> **Note on on-prem data gateway:** the standard on-premises data gateway is **not supported with
> Azure Private Link enabled** (registration fails). Use the **VNet data gateway** for production —
> see the runbook §12.4.
