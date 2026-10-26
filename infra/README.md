# SAP infrastructure with Bicep and Azure Verified Modules

This Bicep/AVM deployment supports Azure DevOps delivery and nine independent development portal options. It is not an SAP installer or a production HA design.

VM profiles are ordinary configuration in the shared catalogue, while resource-sized Azure Verified Modules (AVMs) own resource implementation. The same Bicep entry point serves the portal and pipeline workflows.

## Structure

| File | Responsibility |
|---|---|
| [main.bicep](main.bicep) | One resource-group-scoped entry point; availability-set and VM AVM loops. |
| [types.bicep](types.bicep) | Compile-time contracts for roles, instances, networking, ownership, images and bootstrap. No deployments. |
| [catalog.json](catalog.json) | Sixteen role profiles and eight named landscape presets. |
| [environments/](environments/) | Independent development, test and production Bicep parameter files. |
| [portal/development.bicep](portal/development.bicep) | Shared development-only portal wrapper; SINGLE role selection or a named landscape preset. |
| [portal/](portal/) | Nine generated, self-contained ARM JSON launch templates; [development.json](portal/development.json) retains the Cloud Connector URL. |
| [../azure-pipelines.yml](../azure-pipelines.yml) | Credential-free build/lint/test CI. |
| [../pipelines/deploy.yml](../pipelines/deploy.yml) | Manually queued, environment-selected plan/approval/deploy workflow. |
| [../pipelines/README.md](../pipelines/README.md) | Service connection, permission, approval and pipeline setup. |

Pinned dependencies:

- [`avm/res/compute/virtual-machine:0.22.3`](https://github.com/Azure/bicep-registry-modules/tree/avm/res/compute/virtual-machine/0.22.3/avm/res/compute/virtual-machine), including its NIC and managed-disk implementation.
- [`avm/res/compute/availability-set:0.2.4`](https://github.com/Azure/bicep-registry-modules/tree/avm/res/compute/availability-set/0.2.4/avm/res/compute/availability-set).
- Bicep and test dependencies in [the tool-version manifest](../pipelines/tools.psd1).

There are no new per-property deployment modules, remotely hosted template links, or secret-forwarding helper deployments. AVM internals still compile to nested deployments; flattening the source does not mean removing resource-level module boundaries.

The [development portal instructions](../README.md) provide SINGLE, FULL, NetWeaver Gateway, Gateway FES, SAP PO, SAP BW, S/4HANA Utilities, Cloud Connector and S/4HANA Hybris Billing options. Required inputs are scalar fields; images requiring a marketplace purchase plan also need the optional plan object. SINGLE accepts any typed application/database role and an instance number from 0 to 9. Each published template fixes its launch profile and retains SSH-only access, host encryption and disabled bootstrap, without environment, VM-size or disk-size overrides.

All VMs in a portal deployment share the selected existing primary/secondary subnet pair, with dynamic IP allocation. Pipeline parameter files can instead configure a different pair for each network family. The portal does not execute pipeline preflight or approvals; operators must perform the documented support and capability checks. Source tags distinguish portal deployments from the unchanged Azure DevOps default.

Regenerate all published templates with `.\pipelines\scripts\Build-IaC.ps1 -UpdatePortalTemplate` from the repository root. The generator changes only each profile's default, allowed value and generation metadata; it removes the compiler hash because the launch defaults changed after compilation. CI checks every published file against the compiled source, including the selected VM topology and README label.

## Deployment Boundaries

- Single-instance roles and deterministic role/instance naming; no SAP clustering, replication or HA is configured.
- SLES for SAP 15 BYOS images with explicit versions and SSH-key-only administration.
- No guest bootstrap by default. Use a prepared image or explicitly configure the independently reviewed custom-script hook through Bicep/pipeline parameters.
- Networks and shared services are existing, environment-specific dependencies.

## Role and Resource Configuration

- Sixteen roles with explicit data-disk capacities/order, service classifications and availability-set suffixes. VM selections follow the environment-specific SAP policy below.
- Two private NICs per VM, with NIC 1 primary. Each NIC supports one to four ordered IPv4 configurations. The first configuration is primary on each NIC, implemented by the AVM.
- Blank address entries mean dynamic allocation; nonblank entries mean static allocation. Database roles enable accelerated networking on both NICs; application roles do not.
- Role-specific subnet pairs, aligned availability sets with two fault domains and twenty update domains, ownership tags and deterministic disk/NIC names.
- Eight named landscape compositions, fixed instance numbers and default NIC address counts. SINGLE constructs a one-element VM array with the selected role/instance and four dynamic IP configurations per NIC.
- Incremental resource reconciliation. Removing a VM from configuration does not delete it.

The PO database profile requests a 31 GiB disk and the Hybris database profile includes 256 GiB disks. Review these capacities and their storage design before use. FULL selects 16 VMs, 32 NICs and 74 data disks, with no guest bootstrap extensions by default.

## Security and Resource Lifecycle

- Password authentication is disabled; no infrastructure password, storage key or secret-forwarding outputs are defined.
- VMs use system-assigned identities and platform-managed boot diagnostics.
- Data disks use `Premium_LRS` and `None` caching; host encryption is enabled by default and required by the portal.
- OS disks, data disks and NICs use explicit `Detach` retention when a VM is deleted. Detached resources continue to incur cost.
- Disks are attached but not formatted by default. A reviewed guest workflow must establish filesystems and mounts.
- Pipeline preflight checks identifiers, duplicate VM identities, IP formats and duplicate static addresses.
- NICs inherit VNet DNS unless explicit DNS-server addresses are supplied through Bicep/pipeline parameters. Guest suffixes and DNS registration belong to the guest workflow.
- Outputs contain non-secret VM identities, managed identity principal IDs and private NIC configurations, not application readiness.

Standard VM security and availability sets are explicit. This baseline does not promise Trusted Launch, availability zones, automatic OS patching, backup policies, or production certification. Review security policy and image/SKU support before deployment. A Trusted Launch/zone design must be validated separately against the placement model.

## SAP Support and VM Selection

Reviewed **2026-10-26**, using public Microsoft guidance and the public SAP HANA Hardware Directory. [SAP Note 1928533](https://me.sap.com/notes/1928533) opens the SAP for Me sign-in page; its current SKU tables and SAPS values were **not** accessed. No authentication restriction was bypassed and no claim is made to have verified that Note.

The user-selected policy is **production-only HANA certification**: development and test retain smaller database candidates. An Azure VM family name alone is never sufficient evidence of SAP support, and NetWeaver support is not equivalent to HANA certification.

| Roles | Development/test default | Production default | Evidence and boundary |
|---|---|---|---|
| All application roles | `Standard_E4ds_v5`, 32 GiB | `Standard_E4ds_v5`, 32 GiB | Edsv5 application candidate. Exact SKU, SAP product and OS support must be confirmed against Note 1928533 and applicable component documentation before deployment. |
| HANA for NetWeaver Gateway, SAP PO, Gateway FES | `Standard_E8ds_v5`, 64 GiB | `Standard_E20ds_v5`, 160 GiB | Production: SAP directory record **2638**, OLTP single node. Smaller nonproduction sizes require Note 1928533 confirmation; they are not claimed production-HANA-certified. |
| HANA for SAP BW | `Standard_E16ds_v5`, 128 GiB | `Standard_M32ls`, 256 GiB | Production: SAP directory record **2008**, OLAP single node. An OLTP-only E-series record does not qualify for this role. |
| HANA for Utilities and Hybris Billing | `Standard_E32ds_v5`, 256 GiB | `Standard_E32ds_v5`, 256 GiB | Production: SAP directory record **2639**, OLTP single node. |

Production defaults intentionally increase the smaller HANA database footprints; they are certification-aware starting points, not SAPS sizing recommendations. Memory, dataset growth, CPU/SAPS, IOPS, throughput, licensing, regional supply and cost still need a workload sizing review. M-series is selected for BW because the inspected M32ls record explicitly covers OLAP, not because all M-series sizes are assumed certified.

[The catalogue](catalog.json) holds the exact candidate sets and certification URLs. The pipeline rejects arbitrary `Standard_*` overrides. Production HANA overrides must have a catalogue record for the role's `oltp` or `olap` workload; for example, M32ls has separately inspected OLTP and OLAP records, but E20ds_v5 and E32ds_v5 have only the inspected OLTP records. Adding another SKU requires evidence and a reviewed policy change, not just a regex match.

The required `sapSupportReviewReference` is a **non-secret change/review reference** (for example, `CHG-12345/SAP-BASIS-REVIEW`). Obtain that review from someone authorized to inspect Note 1928533, the Product Availability Matrix, the relevant product requirements (including Cloud Connector where applicable), OS/kernel/HANA revisions and storage restrictions. Record the approved exact SKUs and releases in the referenced evidence. The reference is included in tags and the plan; entering a reference is an operator attestation, not automated access to SAP or proof of support.

**VM certification is not full-system certification.** The inspected production HANA records require compatible OS/HANA releases and storage. Their details include Gen2-only requirements for the selected E-series SKUs and specific `/hana/data` and `/hana/log` storage choices. In particular, those E-series records allow Premium SSD v1 for **data**, not as a blanket approval for Premium SSD v1 **log** volumes. The retained all-`Premium_LRS` disk baseline is therefore **not** a certified production HANA storage design. Resolve log/data storage, performance and guest filesystem configuration before a production workload is installed; changing VM size or adding a review reference cannot repair them.

Planning now checks the selected subscription/region's SKU availability and restrictions, x64/Gen2 capability, two-NIC and disk-count limits, Premium storage, host encryption, and accelerated networking for database roles. These are Azure platform checks, not SAP certification checks; they do not guarantee deploy-time capacity or quota.

Public sources actually inspected:

- [Microsoft SAP support scope and Note 1928533 guidance](https://learn.microsoft.com/en-us/azure/sap/workloads/supported-product-on-azure)
- [Microsoft HANA production versus nonproduction guidance](https://learn.microsoft.com/en-us/azure/sap/workloads/hana-vm-operations#choose-azure-vm-types)
- [SAP HANA directory: E20ds_v5 OLTP, record 2638](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2638)
- [SAP HANA directory: E32ds_v5 OLTP, record 2639](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2639)
- [SAP HANA directory: M32ls OLAP, record 2008](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2008)
- [SAP HANA directory: M32ls OLTP, record 2278](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2278)
- [Microsoft HANA storage requirements](https://learn.microsoft.com/en-us/azure/sap/workloads/hana-vm-operations-storage)

## Configure an Environment

1. Edit its [Bicep parameter file](environments/) and [pipeline target variables](../pipelines/environments/).
2. Replace **every** `REQUIRED_` value. Examples intentionally compile for CI but fail authenticated preflight until configured. Subscription IDs, resource group names and SSH public keys are configuration, not secrets; private keys must never be committed.
3. Select an image available in the deployment region, pin `Major.Minor.Build`, and verify the operating system's SAP support/licensing. The sample `SUSE:sles-sap-15-sp6-byos:gen2` reference is a starting point, not a live availability assertion. If its image metadata requires a purchase plan, supply the `marketplacePlan` object with `name`, `product` and `publisher`, and have the platform owner accept its terms.
4. Supply the existing, same-subscription VNet resource group/name and all six subnet-family pairs. Only selected roles' subnets are checked live, but the configuration must not contain unused placeholders.
5. Ensure those existing subnets have suitable NSGs, routes, DNS, egress and private administration paths. No public IP, network, NSG, firewall or Bastion host is created here.
6. Confirm `Microsoft.Compute/EncryptionAtHost` is registered and the chosen VM sizes support host encryption, two NICs, the selected disks and the regional capacity/quota. Production preflight will not allow host encryption to be disabled.
7. Review exact-SKU SAP support and compute/storage sizing, IOPS, throughput, caching and operating-system/HANA support, then set `sapSupportReviewReference`. **Certified production VM choices do not certify the retained storage baseline or establish production sizing.**

Example environment selections are deliberately independent:

| Environment | Example selection | Code | Deployment number |
|---|---|---|---|
| development | Cloud Connector, 1 VM | `d` | `20` |
| test | Gateway FES pair, 2 VMs | `t` | `21` |
| production | FULL, 16 VMs | `p` | `30` |

Choose a different preset by changing `param virtualMachines = catalog.landscapes.gatewayFes`, for example. Available presets are `netweaverGateway`, `gatewayFes`, `sapPo`, `sapBw`, `utilities`, `cloudConnector`, `hybrisBilling`, and `full`.

For a single VM or reviewed production overrides, use an explicit array:

```bicep
param virtualMachines = [
  {
    role: 'app-gateway-fes'
    instance: '2'
    nic1IpAddresses: ['10.20.1.10', '']
    nic2IpAddresses: ['10.20.2.10']
    vmSize: 'Standard_E4ds_v5'
    dataDiskSizesGB: [32, 32, 64]
  }
]
```

The example IPs and size are illustrative, not an instruction to use those addresses or that size in production. `vmSize` and `dataDiskSizesGB` are optional per-VM overrides. Omitting `vmSize` selects the catalogue's production default in production and its smaller default in development/test; an explicit override must pass the role/environment policy. LUNs remain zero-based and sequential.

With prefix `azsu`, development number `20` and app instance `0`, the VM name is `azsu-d-sap200`. Test and production use `t` and `p`. Names exclude the detailed role: two different app roles cannot reuse the same deployment/instance identity. Multiple instances of one role share its availability set.

## Reviewed Guest Configuration Hook

Default:

```bicep
param bootstrap = {
  mode: 'disabled'
}
```

To opt in, replace that object in the chosen environment:

```bicep
param bootstrap = {
  mode: 'custom-script'
  scriptUri: 'https://YOURACCOUNT.blob.core.windows.net/approved/v1/bootstrap.sh'
  sha256: 'REQUIRED_64_CHARACTER_HEX_SHA256_OF_REVIEWED_SCRIPT'
  managedIdentityResourceId: '/subscriptions/YOUR_SUBSCRIPTION/resourceGroups/YOUR_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/YOUR_IDENTITY'
}
```

This is a configuration example, not a deployable checksum or resource ID. The script:

- Must be an independently reviewed, idempotent replacement compatible with the selected SLES image and actual disk layout.
- Must be served from an immutable Azure Blob path ending in `/bootstrap.sh`, over HTTPS, with no SAS/query string.
- Is downloaded using an existing user-assigned managed identity with narrowly scoped Storage Blob Data Reader access.
- Runs only after `sha256sum` succeeds, through `/bin/bash`, receiving `--role <catalogue-id> --environment <environment>`.
- Must surface failures; the extension does not suppress them. A changed checksum forces an extension update. It must not assume that repeated execution is harmless merely because infrastructure deployment is incremental.

No storage account, identity assignment permission, blob-role assignment or secret is created for this hook. Grant the deployment identity permission to attach the existing user-assigned identity. Grant any guest Key Vault access separately to the guest identity, and retrieve secrets at runtime instead of embedding credentials in commands, tags, parameters, images or outputs.

Without the hook or a prepared image, filesystems, SUSE Manager, proxies, DNS registration, Puppet and SAP/HANA remain unconfigured. Extension success is not a substitute for guest or SAP readiness tests.

## Local Validation

PowerShell 7.2+, Azure CLI 2.76+, and the pinned compiler/test modules are required. No Azure sign-in is needed for build and tests. Restore missing tools to your approved development environment:

```powershell
$tools = Import-PowerShellDataFile .\pipelines\tools.psd1
az bicep install --version "v$($tools.BicepVersion)"
Install-Module Pester -RequiredVersion $tools.PesterVersion -Scope CurrentUser
Install-Module powershell-yaml -RequiredVersion $tools.YamlVersion -Scope CurrentUser
.\pipelines\scripts\Build-IaC.ps1
Import-Module Pester -RequiredVersion $tools.PesterVersion
Invoke-Pester -Path .\tests -Output Detailed
```

Build outputs are ignored under `.build/`; the script compiles and lints the shared and portal entry points and all environment parameter files, then stamps SHA-256 hashes and the source commit. CI publishes the compiled templates, compiled parameters, catalogue and manifest. No deployment stage recompiles Bicep. Use `-UpdatePortalTemplate` when intentionally refreshing the nine committed portal JSON files.

Tests cover typed role/catalogue consistency, ordered disks, landscape topologies, all nine portal choices and generated-file freshness, compiled AVM settings, environment validation, YAML contracts, artifact integrity, plan/apply binding, subscription errors and infrastructure verification using mocked Azure calls. Local YAML parsing does not replace Azure DevOps server-side pipeline expansion.

## Existing Deployment Adoption

Do not point this deployment at populated VMs and expect an in-place OS upgrade. The new baseline changes image generation/version, authentication, diagnostics, explicit disk management and potentially environment names. AVM-managed data disks also introduce explicit disk resources.

First deploy into separate, disposable resource groups with reviewed names/addresses. For existing resources, inventory actual IDs, disks, VM placement and guest state; inspect what-if; and make a dedicated adoption/data-migration plan with backups and rollback. A pipeline rerun is not a rollback, and retained disks do not replace tested backups.

Production approval here governs infrastructure changes. It does not establish SAP application availability, recovery objectives, certification of the complete HANA configuration or HA. Those need a separate workload design and acceptance process.

## References

- [Bicep parameter files](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameter-files)
- [Bicep and Azure Pipelines](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/add-template-to-azure-pipelines)
- [SAP HANA storage requirements](https://learn.microsoft.com/en-us/azure/sap/workloads/hana-vm-operations-storage)
- [Trusted Launch compatibility](https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch)
