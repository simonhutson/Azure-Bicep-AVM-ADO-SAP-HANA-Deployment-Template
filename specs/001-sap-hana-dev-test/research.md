# Supporting Analysis: Legacy Azure SAP HANA Dev/Test Deployment

**Date**: 2026-10-26

**Related specification**: [spec.md](spec.md)

## Evidence and Interpretation

This analysis covers all 40 ARM template files, seven parameter examples, and six shell scripts in the workspace. The [original README](../../README.md) describes the intended use, but template values take precedence when documentation and code disagree.

Three categories are kept separate:

1. **Observed**: Configuration and execution paths present in the checked-in source.
2. **Inferred intent**: The operator-facing capability described by the [feature specification](spec.md).
3. **Unverified**: Live resource availability, remotely hosted script contents, management-service behavior, deployment success, and SAP readiness.

No Azure deployment or guest script was executed. Static checks found that 46 of 47 JSON files parse as strict JSON; the remaining file is identified below. Parameter examples were checked without reproducing credential values. No runtime template or script has been changed.

## Execution Model

The repository is a linked-template infrastructure factory, not a self-contained SAP installer:

```text
Selected operator-facing wrapper
  -> shared per-VM pipeline
       -> validation/normalization
            -> two existing Key Vault secret lookups
       -> tag assembly and property assembly, after validation
       -> resource deployment, after both assemblies
            -> NIC 1, NIC 2, availability set (independent)
            -> VM (after both NICs and the availability set)
            -> Custom Script extension (after VM)
```

- All nine wrappers call [azuredeploy.json](../../azuredeploy.json). Their peer VM deployments have empty dependency lists; application/database ordering is not established.
- The core calls [validate.json](../../validate.json), then [tags.json](../../tags.json) and [settings.json](../../settings.json), then [deploy.json](../../deploy.json).
- Validation reads two existing secrets through [validate.keyvault.json](../../validate.keyvault.json) and emits one normalized parameter object.
- Property assembly delegates to [settings.vm.json](../../settings.vm.json), [settings.nic1.json](../../settings.nic1.json), [settings.nic2.json](../../settings.nic2.json), availability-set settings, and extension settings.
- VM property assembly further delegates storage assembly to [settings.vm.storageprofile.json](../../settings.vm.storageprofile.json). The remaining leaf templates return property values without creating infrastructure.
- Child template URIs are resolved relative to `deployment().properties.templateLink.uri`. The parent must therefore have a usable linked-template URI and the sibling templates must be retrievable by Azure. Deploying only a local file is not a self-contained substitute.
- Every declared linked deployment uses `Incremental`. This avoids intentional pruning by those child deployments, but is not transactional rollback, bootstrap idempotency, or protection against an independently selected outer complete-mode deployment.

The interpretation of linked-template URI resolution, outputs, and deployment modes is consistent with [Microsoft's linked-template documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/linked-templates).

## Launch-Profile Catalogue

Counts describe **requested topology**, not verified successful deployments. Instance numbers below are literal wrapper values.

| Entry point | Requested roles and instances | VM count | Parameter example |
|---|---|---:|---|
| [azuredeploy.single.json](../../azuredeploy.single.json) | Caller selects any shared role and one-character instance | 1 | [Single example](../../azuredeploy.single.parameters.json) |
| [azuredeploy.netweavergateway.json](../../azuredeploy.netweavergateway.json) | App NetWeaver Gateway `1`; DB NetWeaver Gateway `0`; both role strings omit required `(IMOS)` | 2 | [NetWeaver example](../../azuredeploy.netweavergateway.parameters.json) |
| [azuredeploy.gatewayfes.json](../../azuredeploy.gatewayfes.json) | App Gateway FES `2`; DB Gateway FES `2` | 2 | [Gateway FES example](../../azuredeploy.gatewayfes.parameters.json) |
| [azuredeploy.sappo.json](../../azuredeploy.sappo.json) | App SAP PO `1`; DB SAP PO `1` | 2 | [SAP PO example](../../azuredeploy.sappo.parameters.json) |
| [azuredeploy.sapbw.json](../../azuredeploy.sapbw.json) | App SAP BW `3`; DB SAP BW `3` | 2 | [SAP BW example](../../azuredeploy.sapbw.parameters.json) |
| [azuredeploy.s4hanautilities.json](../../azuredeploy.s4hanautilities.json) | App S/4HANA Utilities `4`; DB S/4HANA Utilities `4` | 2 | [Utilities example](../../azuredeploy.s4hanautilities.parameters.json) |
| [azuredeploy.cloudconnector.json](../../azuredeploy.cloudconnector.json) | App Cloud Connector `9` | 1 | [Cloud Connector example](../../azuredeploy.cloudconnector.parameters.json) |
| [azuredeploy.s4hanahybrisbilling.json](../../azuredeploy.s4hanahybrisbilling.json) | App Convergent Charging `5`, Convergent Invoicing `6`, SOM ABAP `7`, SOM JAVA `8`; DB Hybris Billing `5` | 5 | None supplied |
| [azuredeploy.full.json](../../azuredeploy.full.json) | All ten app roles `0`-`9` and six DB roles `0`-`5`, as listed below | 16 | None supplied |

FULL requests 16 VMs, 32 NICs, 16 distinct availability sets, 16 OS disks, 74 data disks, and 16 extensions. Disks are requested within VM storage profiles, not through standalone disk templates.

### Input Contract

| Input | Observed contract |
|---|---|
| `vmDeploymentNumber` | Required string, exactly two characters in the core and every wrapper. Descriptions say "digits", but there is no numeric pattern check. |
| `vmInstanceNumber` | Required, exactly one character for the single wrapper/core. Landscape wrappers supply fixed values. |
| `vmRole` | Sixteen allowed strings in the core. Single wrapper defaults to `App - NetWeaver Gateway (IMOS)`; landscape wrappers supply literals. |
| `vmImage` | Three allowed gallery labels: `Gallery Image - SLES SAP BYOS 12-SP1`, `Gallery Image - SLES SAP BYOS 12-SP2`, `Gallery Image - SLES SAP BYOS 12-SP3`. All nine wrappers default to SP2; the core requires a value. |
| `vmAdminUserName` | String, default `azureuser`. |
| `vmAdminPassword` | Required `securestring` at the core/wrapper boundary. All seven example parameter files omit it; it must be supplied separately. Later secret handling does not preserve this protection throughout the pipeline. |
| NIC arrays | Single wrapper exposes `Nic-1` and `Nic-2`; landscape wrappers expose role-prefixed names. These map to core `nic1IpAddresses` and `nic2IpAddresses`. Wrappers enforce one to four entries; the core only declares arrays. |
| Ownership inputs | `tagServiceOwner`, `tagServiceTicketRequestID`, `tagSource`, `tagProjectName`, `tagCostCodeID`. Wrappers provide fixed legacy defaults. No external service-ticket integration is implemented. |
| Location/subscription | Not freely selectable inputs: the core supplies `resourceGroup().location` and `subscription().displayName`. Validation allows only `uksouth` and `SAP Dev Test`, respectively. |

Every example's parameter names exist in its matching wrapper; none is complete without the separately supplied password.

### NIC Default Cardinalities

All defaults are blank strings, so the default request is dynamic allocation. Counts differ by wrapper; the factory does not always request four IPs or require both NICs to have equal counts.

| Wrapper family | App NIC 1 / NIC 2 | DB NIC 1 / NIC 2 |
|---|---|---|
| Single | `4 / 4` | Same caller-selected role behavior |
| NetWeaver Gateway, Gateway FES, SAP PO, SAP BW, Utilities | `4 / 3` | `2 / 2` |
| Cloud Connector | `4 / 3` | Not applicable |
| Hybris Billing | `3 / 3` for each app | `4 / 4` |
| FULL | `3 / 3` for each app | `3 / 4` for each DB |

Examples can override these defaults: the single example uses `4 / 3`, and the Gateway FES example uses `4 / 3` for its DB rather than the wrapper default `2 / 2`.

## Naming Contract

Normalization in [validate.json](../../validate.json) lowercases names and derives:

| Identity | Formula or example |
|---|---|
| Internal deployment identity | `<deployment>.<app-or-db>.<instance>`, e.g. `20.app.0` |
| VM name | `azsu-d-<sap-or-han><deployment><instance>`, e.g. `azsu-d-sap200` or `azsu-d-han200` |
| NIC names | `<vm>-nic-1` and `<vm>-nic-2` |
| OS disk name | `<vm>-osdisk` |
| Data disk names | `<vm>-datadisk-00`, `<vm>-datadisk-01`, continuing with the zero-based LUN |
| Extension name | `<vm>/script` |
| Availability set | `azsu-as-sap-devtest-<sap-or-han><deployment>-<role-suffix>-001` |

Applications use `sap`; databases use `han`. Availability-set names exclude instance number, grouping instances of the same role/deployment. VM names exclude the detailed role: arbitrary reuse of an instance within the same deployment/category can target the same VM and NICs.

## Role Catalogue

Compute sizes come from [hardware settings](../../settings.vm.hardwareprofile.json); disk capacities and order come from [data-disk settings](../../settings.vm.storageprofile.datadisks.json). Capacities below are the literal `diskSizeGB` values, listed in LUN order beginning at zero. They are not a new sizing recommendation.

| Exact shared role | FULL instance | VM size | Data disks, GB in LUN order | Availability-set suffix |
|---|---:|---|---|---|
| App - NetWeaver Gateway (IMOS) | 0 | `Standard_E4s_v3` | `32,32,64` | `nw-gateway` |
| App - SAP PO (IMOS) | 1 | `Standard_E4s_v3` | `32,32,64` | `sap-po` |
| App - Netweaver Gateway FES | 2 | `Standard_E4s_v3` | `32,32,64` | `nw-fes` |
| App - SAP BW | 3 | `Standard_E4s_v3` | `32,32,64` | `bw` |
| App - S/4HANA Utilities | 4 | `Standard_E4s_v3` | `32,32,64` | `utilities` |
| App - Convergent Charging | 5 | `Standard_E4s_v3` | `32,32,64` | `hybris-cc` |
| App - Convergent Invoicing | 6 | `Standard_E4s_v3` | `32,32,64` | `hybris-ci` |
| App - SOM (CRM ABAP) | 7 | `Standard_E4s_v3` | `32,32,64` | `som-abap` |
| App - SOM (CRM JAVA) | 8 | `Standard_E4s_v3` | `32,32,64` | `som-java` |
| App - Cloud Connector | 9 | `Standard_E4s_v3` | `32,32,64` | `cloudconnector` |
| DB - NetWeaver Gateway (IMOS) | 0 | `Standard_E8s_v3` | `32,32,64,128,64,32` | `nwgateway` |
| DB - SAP PO (IMOS) | 1 | `Standard_E8s_v3` | `32,32,64,128,64,31` | `po` |
| DB - Netweaver Gateway FES | 2 | `Standard_E8s_v3` | `32,32,64,128,64,32` | `nwgatewayfes` |
| DB - SAP BW | 3 | `Standard_E16s_v3` | `32,32,128,512,128,64` | `bw` |
| DB - S/4HANA Utilities | 4 | `Standard_E32s_v3` | `32,32,128,512,128,64` | `utilities` |
| DB - S/4HANA Hybris Billing | 5 | `Standard_E32s_v3` | `32,32,128,256,128,64,128,256,128,64,128,256,128,64` | `hybrisbilling` |

### Shared VM Settings

- [Image-reference settings](../../settings.vm.storageprofile.imagereference.json): publisher `SUSE`, offer `SLES-SAP-BYOS`, SKU `12-SP1`, `12-SP2`, or `12-SP3`, version `latest`. There is no custom-image selection path despite the README's broader wording.
- [OS-disk settings](../../settings.vm.storageprofile.osdisk.json): Linux, `FromImage`, `ReadWrite` caching, explicitly `Premium_LRS`; no explicit OS-disk capacity.
- [OS-profile settings](../../settings.vm.osprofile.json): computer name, administrator username, and password. SSH-key authentication is not configured.
- [Availability-set settings](../../settings.availabilityset.json): twenty update domains and two fault domains; [VM availability-set settings](../../settings.vm.availabilityset.json) reference the derived availability-set resource ID.
- [Diagnostic settings](../../settings.vm.diagnosticsprofile.json): boot diagnostics enabled at `https://azsudsapvmdiags.blob.core.windows.net/`.
- [Network-profile settings](../../settings.vm.networkprofile.json): both NIC IDs attached; NIC 1 primary, NIC 2 secondary.
- Data disks use `createOption: Empty` and sequential LUNs; their storage account type and caching mode are not explicitly set. The README's P-tier descriptions are not an explicit data-disk SKU contract in the template.

## Network Contract

The existing networking resource group is `azsu-rg-sap-devtest-defaultnetworking-001`, with VNet `azsu-vnet-devtest-sap-001`.

[NIC 1 IP settings](../../settings.nic1.ipconfigurations.json) and [NIC 2 IP settings](../../settings.nic2.ipconfigurations.json) select these subnet pairs:

| Role family, for both app and DB where present | NIC 1 subnet | NIC 2 subnet |
|---|---|---|
| NetWeaver Gateway and Gateway FES | `azsu-subn-devtest-sap-nw-gateway-an-001` | `azsu-subn-devtest-sap-nw-gateway-001` |
| SAP PO | `azsu-subn-devtest-sap-nw-pi-an-001` | `azsu-subn-devtest-sap-nw-pi-001` |
| SAP BW | `azsu-subn-devtest-sap-bw-an-001` | `azsu-subn-devtest-sap-bw-001` |
| S/4HANA Utilities | `azsu-subn-devtest-sap-utilities-an-001` | `azsu-subn-devtest-sap-utilities-001` |
| Hybris apps and Hybris database | `azsu-subn-devtest-sap-hybris-an-001` | `azsu-subn-devtest-sap-hybris-001` |
| Cloud Connector | `azsu-subn-devtest-sap-cloud-connect-an-001` | `azsu-subn-devtest-sap-cloud-connect-001` |

- Each array entry becomes `ipconfig00`, `ipconfig01`, etc., in input order.
- Empty strings request `Dynamic`; other values request `Static`. Configuration zero is primary on each NIC. The generated IP-level `primary` values are string expressions returning `'true'`/`'false'`, not native Boolean literals; live schema/coercion behavior was not tested.
- [NIC 1 acceleration settings](../../settings.nic1.enableacceleratednetworking.json) and [NIC 2 acceleration settings](../../settings.nic2.enableacceleratednetworking.json) enable acceleration for all six DB roles and disable it for all ten app roles.
- [NIC 1 DNS settings](../../settings.nic1.dnssettings.json) and [NIC 2 DNS settings](../../settings.nic2.dnssettings.json) specify `azure.uk.centricaplc.com` as internal suffix and empty `dnsServers`/`appliedDnsServers` arrays.
- No public IP, load balancer, NSG, VNet, or subnet is created here. Existing network-level controls are outside this template.
- Azure-side secondary IP configuration is not equivalent to complete guest configuration. The local scripts do not configure every guest secondary address or route.

## Directly Created Resource Surfaces

The only non-deployment resource declarations are the five leaf resources below. Managed disks are also requested implicitly through the VM storage profile.

| Leaf template | Resource type | API version | Dependency enforced by parent |
|---|---|---|---|
| [deploy.nic1.json](../../deploy.nic1.json) | `Microsoft.Network/networkInterfaces` | `2018-08-01` | None of the other four |
| [deploy.nic2.json](../../deploy.nic2.json) | `Microsoft.Network/networkInterfaces` | `2018-08-01` | None of the other four |
| [deploy.availabilityset.json](../../deploy.availabilityset.json) | `Microsoft.Compute/availabilitySets`, SKU `Aligned` | `2018-06-01` | None of the other four |
| [deploy.vm.json](../../deploy.vm.json) | `Microsoft.Compute/virtualMachines` | `2018-06-01` | Both NICs and availability set |
| [deploy.customscriptextension.json](../../deploy.customscriptextension.json) | `Microsoft.Compute/virtualMachines/extensions` | `2018-06-01` | VM |

Linked deployment resources use API `2017-05-10`; the templates declare the `2015-01-01` deployment-template schema and content version `1.0.0.0`.

### Tags and Outputs

[Tag assembly](../../tags.json) derives `Environment` from the subscription and `Service Name` from the role. Service families are IMOS, NetWeaver Gateway, SAP Business Warehouse, Utilities, SAP Hybris Billing, and SAP Cloud Connector. The other five tag values are passed through from inputs. All five resource surfaces above receive the tag object; separately inherited tags on implicit disks are not established by this analysis.

[Resource deployment](../../deploy.json) emits `output` containing `availabilitySet`, `vm`, `nic1`, `nic2`, and `customScriptExtension` reference objects. [The core](../../azuredeploy.json) forwards that aggregate. Every operator-facing wrapper declares `outputs: {}`; there is no explicit wrapper output for a private IP, connection string, SAP URL, or readiness indicator.

## External Prerequisites

| Dependency | Observed binding and required capability |
|---|---|
| Subscription and resource group | Existing deployment target; validation accepts subscription display name `SAP Dev Test` and resource-group location `uksouth`. |
| Virtual network/subnets | Existing cross-resource-group subnet IDs listed above, with sufficient free private addresses. |
| Key Vault | `azsudsapstoragekeys` in `azsu-rg-sapdevtest-vmstorageaccounts`, in the current subscription. Must permit deployment-time secret retrieval. |
| Secret names | `StorageAcctKeyVMScripts` for script storage access and `PuppetPreSharedKey` for Puppet enrollment. No secret values are included in these documents. |
| Script artifacts | Existing account `azsudsapvmscripts`, container `suse-bootstrap-scripts-v1`, containing the six script filenames. Retrieval uses the account key, not a managed identity. |
| Boot diagnostics | Existing account exposed at `https://azsudsapvmdiags.blob.core.windows.net/`. |
| Corporate proxy | For the supported region, `http://proxy-azsu.azure.uk.centricaplc.com:8080`, with the checked-in bypass list. |
| Corporate DNS | For the supported region, `azsu-c-wdns-001.azure.uk.centricaplc.com`; must accept the script's DNS updates for the corporate zones. |
| SUSE Manager | `azsu-c-app-121.azure.uk.centricaplc.com`, serving the bootstrap configuration, client packages, and organization certificate, with activation key label `1-sles12-sp2`. |
| Puppet | `puppet.aws.uk.centricaplc.com`, the configured enrollment secret, external manifests, and a usable Puppet Labs package source. |
| Platform capacity/software | Available gallery images, VM/disk/NIC capacity and quota, legacy API support, Linux disk utilities, and the pinned guest packages. None was checked live. |

Some dictionaries contain `ukwest` values, some scripts also contain European region cases, and a template-storage SAS secret name is declared. These do not create additional working region support or a SAS-based template-download mechanism: the active validator and several other maps only accept/support UK South.

## Bootstrap Contract

[Extension settings](../../settings.customscriptextension.json) request publisher `Microsoft.Azure.Extensions`, type `CustomScript`, handler `2.0`, and automatic minor upgrades. They download six files from Blob storage and execute them using a hard-coded `/var/lib/waagent/custom-script/download/0/` path.

For each stage, the command waits until the file exists, sleeps ten seconds, and pipes the file into `sh -s --` with its arguments. The source scripts use Bash features; a Bash-compatible environment is therefore an assumption. Each stage ends with `;`, not a failure-gating `&&`. The storage account name/key are in extension `protectedSettings`, but sensitive values also travel through ordinary deployment outputs.

The files downloaded at runtime are **not** read directly from the local script directory. The following behavior describes the checked-in files with the matching names; the remotely uploaded copies were not inspected.

| Order | Local source | Arguments supplied by template | Observed actions |
|---:|---|---|---|
| 1 | [sles-bootstrap-lun0.sh](../../scripts/sles-bootstrap-lun0.sh) | Administrator username | Creates `vg0` on LUN 0; allocates 8 GB swap, 10 GB `/opt`, 2 GB `/tmp`, 10 GB `/home`; formats XFS, moves the administrator home, appends filesystem-table entries including `/var/tmp` bind mount, and mounts. Logs to `/root/bootstrap-lun0.log`. |
| 2 | [sles-bootstrap-diskconfig.sh](../../scripts/sles-bootstrap-diskconfig.sh) | Role-specific `-luns`, `-names`, `-paths`, `-sizes` | Resolves Azure SCSI LUNs, partitions/formats single disks or creates striped LVM volumes across groups, adds UUID-based filesystem-table entries, and mounts. Logs to `/var/log/sapconfigcreate`. |
| 3 | [sles-bootstrap-suseclient.sh](../../scripts/sles-bootstrap-suseclient.sh) | None | Downloads client configuration and CA material, installs/updates registration tooling, force-registers with SUSE Manager, disables unmanaged repositories and YaST automatic updates, and syncs the client profile. Full OS update, remote commands, and configuration actions are disabled by its flags. |
| 4 | [sles-bootstrap-proxy.sh](../../scripts/sles-bootstrap-proxy.sh) | Region | Writes `/etc/sysconfig/proxy`, sets Azure Linux agent proxy host/port, and enables agent auto-update. Logs to `/root/bootstrap-proxy.log`. |
| 5 | [sles-bootstrap-dns.sh](../../scripts/sles-bootstrap-dns.sh) | Region | Updates search suffixes, discovers the primary `eth0` IP, and submits A and PTR updates with TTL 3600. It does not register every NIC/IP. Logs to `/root/bootstrap-dns.log`. |
| 6 | [sles-bootstrap-puppet.sh](../../scripts/sles-bootstrap-puppet.sh) | `uksouth dev sap::app <secret>` or `uksouth dev sap::hana <secret>` | Writes enrollment CSR attributes, installs Puppet agent `1.8.3-1.sles12`, sets master and certificate name, enables the service, and launches a background `puppet agent -t`. Logs to `/root/bootstrap-puppet.log`. |

Puppet CSR metadata uses the default image string `SUSE:SLES-SAP:12-SP2:latest`, even if the actual selected image is BYOS SP1 or SP3. The role command does not pass an image argument to override it.

### Role Filesystem Commands Versus Actual Disks

The `#` separator denotes independent filesystem groups; commas join LUNs within a group. The `100` size values mean percentage of free extents for multi-disk LVM groups, not a 100 GB capacity.

| Role family | LUN groups requested after LUN 0 | Requested mount paths | Observed mismatch |
|---|---|---|---|
| All app mappings, including the misspelled PO key | `1` | `/usr/sap` | LUN 2 is provisioned but not configured by these local disk scripts. The valid PO role cannot reach its misspelled mapping. |
| DB NetWeaver Gateway, SAP PO, Gateway FES, SAP BW | `1 # 2,3,4 # 5,6 # 7 # 8` | `/usr/sap`, `/hana/data`, `/hana/log`, `/hana/shared`, `/hana/backup` | Only LUNs `0`-`5` are provisioned; required LUNs `6,7,8` do not exist. |
| DB S/4HANA Utilities | `1 # 2,3 # 4,5 # 6 # 7 # 8,9 # 10,11 # 12 # 13,14,15 # 16,17 # 18 # 19` | `/usr/sap`; data/log/shared/backup under `DE2`; data/log/shared under `CE2`; data/log/shared/backup under `HE2` | Only LUNs `0`-`5` are provisioned; required LUNs `6`-`19` do not exist. |
| DB S/4HANA Hybris Billing | `1 # 2,3,4 # 5,6 # 7 # 8` | `/usr/sap`, `/hana/data`, `/hana/log`, `/hana/shared`, `/hana/backup` | Provisioned LUNs `9`-`13` are not referenced. There is no local disk setup for all advertised multi-system storage. |

This records the mismatch without guessing a corrected disk count, swapping role commands, or treating the declared mounts as successfully configured.

## Observed Defects and Behavioral Limitations

| ID | Evidence | Consequence and interpretation |
|---|---|---|
| L-001 | [settings.json](../../settings.json) has a trailing comma after its last variable. | It is the sole strict-JSON parse failure: 46/47 JSON files parse. Azure acceptance was not tested; this is at least a blocker for strict tooling, not an issue introduced by this specification. |
| L-002 | [NetWeaver wrapper](../../azuredeploy.netweavergateway.json) sends `App - NetWeaver Gateway` and `DB - NetWeaver Gateway`. | Both omit `(IMOS)` and fail the core's allowed-role contract. Its app instance is `1`, unlike FULL's NetWeaver app instance `0`; the definition preserves that distinction. |
| L-003 | [Extension role map](../../settings.customscriptextension.json) contains `pp - SAP PO (IMOS)` instead of `App - SAP PO (IMOS)`. | The supported PO application role has no matching bootstrap lookup. SAP PO and FULL cannot be treated as fully working paths. |
| L-004 | [Data-disk catalogue](../../settings.vm.storageprofile.datadisks.json) and [filesystem arguments](../../settings.customscriptextension.json) disagree. | Four DB profiles reference absent LUNs `6`-`8`; Utilities references absent LUNs `6`-`19`. Storage preparation cannot satisfy those commands as declared. |
| L-005 | The same disk/argument comparison leaves app LUN `2` and Hybris LUNs `9`-`13` unused by local disk setup. | Attaching a disk is not proof that all intended SAP filesystems were configured. External Puppet behavior is unknown. |
| L-006 | [Data-disk catalogue](../../settings.vm.storageprofile.datadisks.json) differs from the [README](../../README.md). | PO's last disk is 31 GB, not 32 GB; Hybris has three 256 GB disks where the README says 512 GB. No corrected sizing is inferred. |
| L-007 | Only [OS-disk settings](../../settings.vm.storageprofile.osdisk.json) explicitly select premium storage. | README P-tier descriptions do not establish explicit premium SKUs for data disks. Do not silently document all disks as guaranteed Premium SSDs. |
| L-008 | [Secret helper](../../validate.keyvault.json) uses ordinary strings/outputs; [validation output](../../validate.json) includes the administrator password and retrieved secrets; settings return further sensitive configuration. Linked deployments enable request/response debug content. | The use of a secure input or extension protected settings does not make the whole pipeline secret-safe. This exposure is an observed limitation, not a requirement for a replacement. |
| L-009 | [Extension commands](../../settings.customscriptextension.json) concatenate scripts with semicolons, use unbounded file waits, and assume download directory `0`. | Earlier script failures need not determine final command success; waits can hang, and repeated execution/download-directory behavior is not robustly handled. |
| L-010 | [LUN 0](../../scripts/sles-bootstrap-lun0.sh) and [role disk setup](../../scripts/sles-bootstrap-diskconfig.sh) initialize disks and append filesystem entries without a replay-safe reconciliation design. | Incremental ARM mode does not make guest disk initialization idempotent. Rerunning scripts on populated disks is unsafe. |
| L-011 | [SUSE registration](../../scripts/sles-bootstrap-suseclient.sh) is fixed to the SP2 activation key label; [Puppet bootstrap](../../scripts/sles-bootstrap-puppet.sh) reports a default non-BYOS SP2 image and backgrounds the first run. | SP1/SP3 selection is not consistently reflected in onboarding; extension success does not prove configuration convergence. Legacy downloads also relax certificate checking in parts of SUSE bootstrap. |
| L-012 | [Validation](../../validate.json), [extension settings](../../settings.customscriptextension.json), and the bootstrap files hard-code the historical environment. Images and remote scripts are not content-pinned. | This is not a portable or reproducibly versioned generic SAP deployment. Extra region dictionary entries do not imply supported multi-region operation. |

Additional boundaries are intentional observations rather than proposed fixes: no custom-image path, no SAP installer, no cluster/replication configuration, no actual backup policy despite a backup mount path, no secondary guest-network setup, and no wrapper-level readiness output.

## Requirement-to-Source Traceability

| Specification requirements | Primary evidence |
|---|---|
| FR-001 to FR-006: context, inputs, role selection, naming, orchestration | Launch-profile entry points above; [core](../../azuredeploy.json), [validation](../../validate.json), [secret helper](../../validate.keyvault.json), [property assembly](../../settings.json), [resource orchestration](../../deploy.json) |
| FR-007 to FR-012: compute, images, storage, availability, diagnostics | [VM assembly](../../settings.vm.json), [storage assembly](../../settings.vm.storageprofile.json), and every leaf in the shared VM settings/role catalogue sections |
| FR-013 to FR-016: NIC attachments, subnets, address allocation, acceleration, DNS | [NIC 1 assembly](../../settings.nic1.json), [NIC 2 assembly](../../settings.nic2.json), [VM network profile](../../settings.vm.networkprofile.json), and all six NIC leaf templates linked in the network contract |
| FR-017 to FR-020: extension and operating-system onboarding | [Extension settings](../../settings.customscriptextension.json), [extension resource](../../deploy.customscriptextension.json), and all six local scripts linked in the bootstrap contract |
| FR-021: ownership | [Tags](../../tags.json) and all five directly created resource templates |
| FR-022: inspection and secret-handling boundaries | [Core outputs](../../azuredeploy.json), [aggregate outputs](../../deploy.json), wrapper empty outputs, [validation](../../validate.json), [secret helper](../../validate.keyvault.json) |

## Validation and Remaining Unknowns

Completed static checks:

- Enumerated 40 templates, seven matching parameter examples, and six bootstrap scripts.
- Strict-parsed all 47 JSON files; identified the one pre-existing syntax failure.
- Compared every literal wrapper role with the core's sixteen-role enumeration; identified both invalid NetWeaver strings.
- Compared all sixteen role profiles with bootstrap keys and provisioned/requested LUNs; identified the PO lookup error, missing DB LUNs, and unused app/Hybris LUNs.
- Calculated FULL's requested VM/NIC/disk counts directly from wrapper roles and disk arrays.
- Checked example parameter keys and required omissions without exposing password/secret values.

Not established by static inspection:

- Whether Azure currently accepts every legacy API/property shape, including the generated primary-flag strings and NIC DNS properties.
- Whether the historical subscription, dependencies, gallery SKUs, packages, and remotely stored scripts still exist or are usable.
- Whether a deployed extension completes, every intended filesystem mounts, DNS updates succeed, or management agents enroll and converge.
- Whether external Puppet code installs or configures SAP. No such manifests are included.

A future implementation plan should resolve these questions and explicitly choose repairs or modernization goals. They are not grounds to claim the unchanged deployment is currently working.
