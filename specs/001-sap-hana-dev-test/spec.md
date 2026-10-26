# Feature Specification: Azure SAP HANA Dev/Test Infrastructure

**Feature Branch**: `001-sap-hana-dev-test` (logical feature identifier; no Git branch created)

**Created**: 2026-10-26

**Status**: Draft - historical baseline with SAP VM support addendum; not deployment-certified

**Input**: User description: "Analyse this old Azure SAP deployment ARM template and create a Spec Kit definition for what it is doing."

**Historical baseline**: This specification records the original manually launched ARM implementation. Its property-sized linked templates were an intentional composition choice, not a defect. The separately implemented [Bicep/AVM migration](../../infra/README.md) retains this definition for traceability. The [SAP VM support addendum](#sap-vm-support-addendum---bicepavm) below records the replacement's environment-specific SKU decisions without rewriting the original requirements.

## Purpose and Scope

Enable an infrastructure operator to request a single SAP application or HANA database VM, a predefined SAP landscape, or the complete dev/test landscape in an existing Azure environment.

The deployment provisions and configures infrastructure and attempts operating-system onboarding. It does **not** contain an SAP or HANA software installer. Any subsequent SAP configuration performed by external Puppet code is outside the available source.

The scope, FR-001 to FR-022, SC-001 to SC-006, and original user stories describe the as-is ARM baseline. The separately labelled SAP VM support addendum applies only to the Bicep/AVM replacement. The [supporting analysis](research.md) records exact legacy configuration, source evidence, and defects separately; those defects are not recommendations to reproduce unsafe or broken behavior.

### In Scope

- Nine operator-facing launch templates, backed by one shared per-VM pipeline.
- Sixteen application/database role profiles and three SUSE gallery image choices.
- Deterministic naming, ownership tags, role-based compute and disk configuration.
- Two private NICs per VM, using existing role-specific subnets.
- Availability-set membership and boot diagnostics.
- Retrieval of existing onboarding secrets and execution of six bootstrap stages.
- Deployment output behavior, prerequisites, failure boundaries, and known limitations.

### Out of Scope

- Creating subscriptions, resource groups, virtual networks, subnets, storage accounts, Key Vaults, or secrets.
- SAP/HANA binary installation, SAP system creation, licensing procurement, or functional application verification.
- Production sizing/certification, clustering, database replication, disaster recovery, backup scheduling, or restore.
- Public endpoints, load balancers, new network security groups, or new routing infrastructure.
- Modernizing images, APIs, identity, secret handling, or the infrastructure language.

## User Scenarios & Testing

Acceptance scenarios describe intended outcomes in a prepared, disposable environment. They have not been executed against Azure. Known source-level blockers in [research.md](research.md#observed-defects-and-behavioral-limitations) must not be mistaken for passing acceptance tests.

### User Story 1 - Provision One Role-Specific VM (Priority: P1)

As an infrastructure operator, I can select one supported application or database role and provide a deployment number, instance number, administrator credentials, and address preferences so that I receive consistently configured infrastructure for that role.

**Why this priority**: The single-VM pipeline is the reusable capability behind every landscape.

**Independent Test**: Submit one application role and, in a separate test, one database role. Inspect only their named resources and generated configuration; no complete SAP landscape is required.

**Acceptance Scenarios**:

1. **Given** the supported subscription, region, and external prerequisites, **When** one supported role is requested, **Then** the pipeline requests one VM, two NICs, the role/deployment availability set, its OS/data disks, and one bootstrap extension.
2. **Given** an application role or a database role, **When** its configuration is assembled, **Then** its compute size and ordered data-disk profile match the corresponding [role catalogue](research.md#role-catalogue).
3. **Given** a deployment number and instance number, **When** resources are named, **Then** names consistently distinguish application VMs from database VMs and use the same identity for the VM, NICs, disks, and extension.
4. **Given** a mixture of blank and nonblank NIC address entries, **When** NIC configuration is generated, **Then** blank entries request dynamic allocation, nonblank entries request static allocation, and the first configuration on each NIC is primary.

### User Story 2 - Request a Predefined Landscape (Priority: P2)

As an infrastructure operator, I can choose a named landscape instead of manually assembling its VM roles and instance numbers.

**Why this priority**: Landscape wrappers reduce repeated input and encode the intended application/database combinations.

**Independent Test**: Inspect or deploy each wrapper independently with a unique deployment number; compare its requested roles and counts with the [launch-profile catalogue](research.md#launch-profile-catalogue).

**Acceptance Scenarios**:

1. **Given** a NetWeaver Gateway, Gateway FES, SAP PO, SAP BW, or S/4HANA Utilities request, **When** its wrapper is expanded, **Then** it requests one application VM and one database VM. The checked-in NetWeaver wrapper currently fails the shared role contract; that exception is documented rather than silently corrected.
2. **Given** a Cloud Connector request, **When** its wrapper is expanded, **Then** it requests one application VM and no database VM.
3. **Given** a S/4HANA Hybris Billing request, **When** its wrapper is expanded, **Then** it requests Convergent Charging, Convergent Invoicing, SOM ABAP, and SOM JAVA application VMs plus one Hybris database VM.
4. **Given** a FULL request, **When** its wrapper is expanded, **Then** it requests all ten application roles and six database roles, with their fixed instance numbers.
5. **Given** one VM pipeline fails, **When** other wrapper pipelines are independent, **Then** their resources may remain or finish successfully; the deployment is not an all-or-nothing landscape transaction.

### User Story 3 - Prepare a VM for Corporate SAP Operations (Priority: P2)

As a platform operator, I can have a newly provisioned VM's storage prepared and its operating system onboarded to the existing corporate management environment.

**Why this priority**: Infrastructure alone is insufficient for the intended managed dev/test operating environment.

**Independent Test**: Use a disposable SUSE VM with blank disks and reachable management services. Verify each bootstrap stage's observable effects separately from SAP installation and Puppet convergence.

**Acceptance Scenarios**:

1. **Given** the configured script storage account and key, **When** the extension runs, **Then** it downloads the six configured script files and attempts them in this order: LUN 0, role disks, SUSE Manager, proxy, DNS, Puppet.
2. **Given** an empty LUN 0, **When** its bootstrap stage succeeds, **Then** it prepares swap, `/opt`, `/tmp`, `/home`, and a `/var/tmp` bind mount while moving the administrator's home directory.
3. **Given** all LUNs required by a role's disk command, **When** that stage succeeds, **Then** it prepares the configured XFS partitions or striped logical volumes and filesystem-table entries. Several checked-in database profiles do not supply those LUNs.
4. **Given** reachable corporate services and usable registration credentials, **When** onboarding succeeds, **Then** the VM is registered with SUSE Manager, has proxy settings, has a primary-address DNS registration, and has a Puppet agent configured for `sap::app` or `sap::hana` in environment `dev`.
5. **Given** the Puppet agent is launched asynchronously, **When** the extension command exits, **Then** that exit alone does not establish Puppet convergence or SAP/HANA readiness.

### User Story 4 - Identify and Inspect Deployed Resources (Priority: P3)

As a service owner, I can associate resources with their service and request metadata and inspect deployment state without relying on an application connection output.

**Why this priority**: Naming, tags, diagnostics, and deployment history support ownership and troubleshooting.

**Independent Test**: Inspect the five directly declared resource surfaces of one VM pipeline and compare their identity, tags, diagnostic settings, and output contracts.

**Acceptance Scenarios**:

1. **Given** ownership/request metadata, **When** the availability set, NICs, VM, and extension are deployed, **Then** each receives the seven defined tags.
2. **Given** a VM is provisioned, **When** its diagnostic configuration is inspected, **Then** boot diagnostics target the pre-existing diagnostics storage account.
3. **Given** the shared per-VM pipeline completes, **When** its output is inspected, **Then** its `output` object contains availability-set, VM, NIC 1, NIC 2, and extension references; the operator-facing wrappers themselves return no outputs.
4. **Given** the same resource identity is submitted again using incremental deployment, **When** the infrastructure is reconciled, **Then** unrelated resources are not intentionally pruned. Re-execution of the destructive bootstrap scripts is not guaranteed safe.

### Edge Cases

- The resource group's location is not `uksouth`, or the subscription display name is not exactly the permitted `SAP Dev Test` value: the validation stage rejects the request.
- A role string is absent from the shared enumeration or a required role lookup: parameter validation or configuration assembly fails. This affects the NetWeaver wrapper and the SAP PO application bootstrap mapping in different ways.
- Deployment and instance identifiers have valid lengths but contain nondigits: length constraints alone do not reject them; later naming/platform constraints may still fail.
- A wrapper NIC array is empty or contains more than four entries: wrapper parameter bounds reject it. The shared core template does not impose those same bounds.
- A nonblank IP is malformed, duplicated, outside its subnet, or already allocated: no custom IP validator exists; Azure networking determines acceptance.
- A different role reuses the same deployment number, role category, and instance number: VM/NIC/disk names can collide because they do not include the full role name.
- A referenced subnet, Key Vault secret, storage account, management server, package, or image is absent or inaccessible: deployment or onboarding can fail; these dependencies are not created here.
- A bootstrap command references a nonexistent LUN, or runs against already formatted disks: successful and safe storage preparation cannot be assumed.
- A script fails before the last command: semicolon-separated execution can mask an earlier failure, and the wait loops have no explicit timeout.
- Secondary NIC/IP configurations exist in Azure: local scripts do not establish all secondary guest addresses/routes or register every address in DNS.
- A previous deployment left resources behind, or one parallel branch fails: incremental execution does not provide cleanup or transactional rollback.

## Requirements

### Functional Requirements

#### Deployment Selection and Identity

- **FR-001**: The system MUST target an existing resource group and derive its deployment location and subscription display name from that Azure context.
- **FR-002**: Operators MUST be able to request a single role or one of the eight predefined landscape wrappers, with the role composition recorded in the launch-profile catalogue.
- **FR-003**: The request MUST carry a two-character deployment identifier; a single-VM request MUST also carry a one-character instance identifier and a supported role. The legacy validation is length-based, not numeric.
- **FR-004**: The system MUST accept an administrator username, required password, image choice, per-NIC address arrays, and five caller-supplied ownership/request metadata fields. The default username is `azureuser`; examples omit the required password.
- **FR-005**: The system MUST use the legacy application/database naming distinction and role/deployment availability-set grouping described in the naming contract.
- **FR-006**: Each VM MUST follow validation/normalization, tag and property assembly, and resource deployment, using linked incremental deployments. Peer VMs MUST NOT be assumed to run in application/database order.

#### Compute and Storage

- **FR-007**: Each role MUST select its configured compute size from the role catalogue.
- **FR-008**: Image selection MUST support the three SUSE SLES SAP BYOS 12 service-pack choices, using the gallery's `latest` version; operator-facing wrappers default to SP2.
- **FR-009**: The VM MUST use a Linux OS disk created from the selected image, with `Premium_LRS` storage and `ReadWrite` caching.
- **FR-010**: The VM MUST request the role-specific data-disk count, capacities, sequential LUNs starting at zero, and deterministic disk names. The exact as-is values are catalogued separately from README discrepancies; data-disk premium storage is not explicitly configured.
- **FR-011**: The VM MUST reference an aligned availability set configured for two fault domains and twenty update domains. Multiple instances of the same role/deployment share its availability-set identity; this is not a complete high-availability solution.
- **FR-012**: Boot diagnostics MUST be enabled against the configured existing diagnostics storage account.

#### Networking

- **FR-013**: Each VM MUST attach exactly two private NICs, with NIC 1 primary at the VM level and NIC 2 secondary.
- **FR-014**: NICs MUST reference the existing role-specific subnet pair: NIC 1 uses the `-an-001` subnet and NIC 2 the corresponding `-001` subnet.
- **FR-015**: Each NIC MUST request one IPv4 configuration for every supplied address entry, dynamically allocated for an empty string and statically allocated otherwise. Operator-facing arrays permit one to four entries, and configuration zero is primary on each NIC.
- **FR-016**: Both NICs MUST request accelerated networking for database roles and disable it for application roles. NIC settings MUST specify the legacy internal DNS suffix without explicit DNS-server overrides.

#### Operating-System Preparation

- **FR-017**: After VM deployment, the system MUST request the Custom Script extension and download the six bootstrap files from the configured existing script storage account using its retrieved account key.
- **FR-018**: The first bootstrap stage MUST attempt the LUN 0 layout: 8 GB swap, 10 GB `/opt`, 2 GB `/tmp`, and 10 GB `/home`, plus the `/var/tmp` bind mount and administrator-home move.
- **FR-019**: The second bootstrap stage MUST attempt the role-specific SAP/HANA filesystem command. Its required LUN groups, intended mount paths, and discrepancies with provisioned disks MUST remain explicit in the deployment definition.
- **FR-020**: Subsequent bootstrap stages MUST attempt SUSE Manager registration, corporate proxy configuration, DNS A/PTR updates for the primary `eth0` address, and Puppet agent configuration/launch. These attempts MUST NOT be represented as proof of application installation, complete guest-network setup, or configuration convergence.

#### Ownership and Inspection

- **FR-021**: The directly declared resources MUST receive `Environment`, `Service Name`, `Service Owner`, `Service Ticket Request ID`, `Source`, `Project Name`, and `Cost Code ID` tags. Environment/service values are derived; the other five values come from the request or legacy defaults.
- **FR-022**: The shared deployment MUST aggregate the five resource-reference outputs, while preserving the observed empty-output contract of the operator-facing wrappers. Secret retrieval and the legacy exposure of sensitive values MUST be documented, not interpreted as a safe design.

### Key Entities

- **Deployment Request**: Deployment identifier, optional caller-selected instance/role, credentials, image choice, NIC addresses, and ownership metadata.
- **Launch Profile**: A named single-VM or landscape entry point that selects one or more role/instance combinations.
- **Role Profile**: Compute size, ordered data disks, subnet family, acceleration policy, service classification, availability-set suffix, and bootstrap arguments.
- **VM Identity**: Derived VM, disk, NIC, extension, and deployment names; application/database category prevents cross-category collisions but not arbitrary same-category reuse.
- **Availability Grouping**: The role/deployment availability-set identity shared by instances of that role.
- **NIC Address Configuration**: NIC number, ordered IPv4 entries, allocation method, primary flag, and existing subnet reference.
- **External Dependency**: A network, secret, artifact store, diagnostics destination, or corporate service required but not provisioned.
- **Bootstrap Attempt**: Ordered guest configuration stages and their observable results, distinct from subsequent management convergence.

## Success Criteria

These are measurable acceptance targets inferred from the feature, not a claim that the unchanged legacy implementation passes them.

### Measurable Outcomes

- **SC-001**: A successful single-role request reconciles exactly one named VM with two NICs, one selected OS image, the catalogue's data-disk sequence, availability-set membership, and a bootstrap-extension request.
- **SC-002**: Landscape expansion produces the documented counts: two VMs for each paired landscape, one for Cloud Connector, five for Hybris Billing, and sixteen for FULL. FULL's requested infrastructure includes 32 NICs, 16 distinct availability sets, 16 OS disks, 74 data disks, and 16 extensions.
- **SC-003**: For every supplied NIC address entry, the generated configuration preserves its order and requested allocation mode; the first entry on each NIC and NIC 1 on the VM have the primary designation.
- **SC-004**: Each successfully executed bootstrap stage has independently inspectable effects: storage mounts, management registration, proxy files, primary-address DNS records, or Puppet configuration. Extension completion is reported separately from Puppet/SAP readiness.
- **SC-005**: All five directly declared resource surfaces per VM pipeline carry all seven specified tags, and the VM's boot diagnostic destination matches the configured dependency.
- **SC-006**: Tests for unsupported region, subscription display name, and role demonstrate rejection before the resource-deployment stage; documented source-level defects remain visible rather than being counted as successful provisioning.

Counts apply to the selected deployment's identities, not to all pre-existing resources in the resource group. No provisioning-time, uptime, recovery-time, or production performance target can be established from this source.

## Assumptions

- An operator already has permission to deploy into the target resource group and use all cross-resource-group dependencies.
- Existing subnets have sufficient free addresses; the chosen VM sizes support two NICs and the configured disk counts.
- The selected gallery images, VM sizes, API versions, and package versions remain usable in the target environment; this was not verified against live Azure.
- Key Vault permits deployment-time secret retrieval, and its named secrets and the existing storage accounts are valid.
- The uploaded bootstrap files correspond to the intended versions. The deployment downloads from Blob storage, not from the checked-in script directory.
- Corporate DNS, proxy, SUSE Manager, Puppet, and package endpoints are already reachable; initial SUSE Manager registration occurs before the proxy/DNS bootstrap stages.
- Bootstrap targets are disposable Linux VMs with blank data disks and a Bash-compatible shell environment. Repeated storage initialization is not assumed safe.
- External Puppet manifests, SAP media, licensing, system identifiers, and post-provisioning workflows are not available in this repository.

## SAP VM Support Addendum - Bicep/AVM

**Decision and evidence date**: 2026-10-26.

**Scope**: The active Bicep/AVM replacement only. The archived ARM sizes remain historical evidence; the replacement retains them as `legacyVmSize` in [the catalogue](../../infra/catalog.json).

**Confirmed decision**: Require workload-specific HANA-certified SKU selections for **production**, while retaining smaller development/test candidates. A family name, an Azure-supported size, a NetWeaver listing, and a HANA certification are not interchangeable support claims.

### Selected Exact SKUs

| Role group | Development/test default | Production default | Support evidence and outstanding checks |
|---|---|---|---|
| All ten application roles | `Standard_E4ds_v5` - 32 GiB | `Standard_E4ds_v5` - 32 GiB | Application candidate, **not independently verified** against the current Note 1928533. Confirm the exact SKU, SAP product/component, OS and kernel requirements through an authorized review. |
| HANA for NetWeaver Gateway, SAP PO and Gateway FES | `Standard_E8ds_v5` - 64 GiB | `Standard_E20ds_v5` - 160 GiB | Production: public SAP directory [record 2638](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2638), **OLTP single node**. The smaller nonproduction candidate still requires Note 1928533 confirmation. |
| HANA for SAP BW | `Standard_E16ds_v5` - 128 GiB | `Standard_M32ls` - 256 GiB | Production: public SAP directory [record 2008](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2008), **OLAP single node**. An OLTP-only E-series certificate does not qualify for this role. |
| HANA for S/4HANA Utilities and Hybris Billing | `Standard_E32ds_v5` - 256 GiB | `Standard_E32ds_v5` - 256 GiB | Production: public SAP directory [record 2639](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2639), **OLTP single node**. |

These are exact selected SKUs, not an exhaustive list of SAP-supported Azure sizes or a production-sizing recommendation. Production increases the smaller database footprints; confirm SAPS, CPU, memory growth, licensing and cost through workload sizing.

The implementation also restricts overrides to a local, reviewable subset:

- **Application candidates**: `Standard_E4ds_v5`, `Standard_E8ds_v5`, `Standard_E16ds_v5`, `Standard_E20ds_v5`, `Standard_E32ds_v5`. Inclusion is not a claim that the current protected SAP Note was read.
- **Nonproduction HANA candidates**: `Standard_E8ds_v5`, `Standard_E16ds_v5`, `Standard_E20ds_v5`, `Standard_E32ds_v5`, `Standard_M32ls`. Validate the exact Note 1928533 applicability before use.
- **Production HANA, OLTP**: `Standard_E20ds_v5`, `Standard_E32ds_v5`, or `Standard_M32ls`, with a matching public directory record. M32ls has a separately inspected [OLTP record 2278](https://www.sap.com/dmc/exp/2014-09-02-hana-hardware/enEN/#/solutions?filters=ve:24&id=s:2278).
- **Production HANA, OLAP/BW**: `Standard_M32ls`, based on record 2008. The inspected E20ds_v5 and E32ds_v5 records establish OLTP support, not OLAP support.

### SAP Notes, Sources and Verification Status

| Reference | Purpose in the support decision | Verification status |
|---|---|---|
| [SAP Note 1928533 - SAP Applications on Microsoft Azure: Supported Products and Azure VM types](https://me.sap.com/notes/1928533) | Supported SAP products, exact Azure VM types, SAPS and associated restrictions; required application/nonproduction review. | **Authentication required; contents not accessed.** The normal SAP for Me sign-in page was reached. No current SKU listing or SAPS value from this Note is claimed verified. |
| [SAP Note 2235581](https://me.sap.com/notes/2235581) | SAP HANA release/patch-level compatibility with the selected operating system. | **Required follow-up; contents not accessed.** Its role is identified by Microsoft's [HANA installation guidance](https://learn.microsoft.com/en-us/azure/sap/workloads/hana-get-started#step-by-step-before-deploying). |
| Public SAP HANA Hardware Directory records 2638, 2639, 2008 and 2278, linked above | Exact production HANA SKU, OLTP/OLAP single-node applicability, supported OS and storage restrictions. | Inspected on 2026-10-26; this is a dated evidence snapshot, not a permanent certification guarantee. |
| [Microsoft SAP support guidance](https://learn.microsoft.com/en-us/azure/sap/workloads/supported-product-on-azure) and [HANA VM operations](https://learn.microsoft.com/en-us/azure/sap/workloads/hana-vm-operations#choose-azure-vm-types) | Explain the distinction between NetWeaver support, nonproduction choices and production HANA certification. | Public guidance inspected; it does not replace the protected Note or product-specific checks. |
| [Microsoft HANA storage guidance](https://learn.microsoft.com/en-us/azure/sap/workloads/hana-vm-operations-storage) and the target SAP Product Availability Matrix | Validate storage and the supported product/OS/HANA combination. | Public storage guidance inspected; the target deployment's product/release matrix and complete storage design remain to be verified by an authorized operator. |

The support review must include applicable product/component requirements, including Cloud Connector where relevant, plus OS/kernel and HANA revisions. A SLES for SAP 15 image alone does not establish support for every HANA or application release.

### Addendum Requirements

These SAP-FR identifiers apply to the replacement only and do not change the archived ARM functional contract.

- **SAP-FR-001**: The replacement MUST select the environment-specific defaults above when no per-VM override is supplied; development/test MUST NOT silently inherit the larger production HANA defaults.
- **SAP-FR-002**: A production HANA override MUST match an exact recorded SKU and the role's `oltp` or `olap` single-node workload. Arbitrary `Standard_*` values and family-wide certification assumptions MUST be rejected.
- **SAP-FR-003**: Application and nonproduction candidates MUST remain explicitly distinguished from independently verified production HANA records. Additional SKUs MUST enter the local policy through a reviewed evidence-backed change.
- **SAP-FR-004**: Before authenticated planning/deployment, an operator MUST supply a nonempty, non-placeholder `sapSupportReviewReference` identifying the exact-SKU/product/OS/HANA/storage review. It MUST be retained in resource tags and the plan. This reference is an operator attestation, not automated SAP Note verification.
- **SAP-FR-005**: Planning MUST check actual regional/subscription SKU availability and restrictions, x64/Gen2 compatibility, two-NIC and data-disk limits, Premium storage, host encryption, and HANA accelerated-networking capability. Azure capability checks MUST NOT be represented as SAP certification or a capacity/quota guarantee.
- **SAP-FR-006**: VM certification MUST NOT be reported as certification of the complete deployment. The retained all-`Premium_LRS` disk baseline is **not** a certified production HANA storage design; resolve log/data storage, IOPS/throughput, guest filesystems and supported release combinations before installing a production workload. In particular, the selected E-series records do not grant blanket Premium SSD v1 approval for `/hana/log`.

### Addendum Acceptance Scenarios

1. **Given** FULL with no size overrides, **When** production selections are resolved, **Then** the ten app VMs use E4ds_v5, the Gateway/PO/FES databases use E20ds_v5, BW uses M32ls, and Utilities/Hybris databases use E32ds_v5.
2. **Given** the Gateway FES pair with no overrides, **When** it targets test, **Then** its database uses E8ds_v5 rather than the production E20ds_v5.
3. **Given** a production BW request overridden to E20ds_v5 or E32ds_v5, **When** preflight runs, **Then** the request is rejected because the recorded evidence is OLTP-only.
4. **Given** an arbitrary application/nonproduction SKU or a missing support-review reference, **When** preflight runs, **Then** the request is rejected before an authenticated Azure plan is attempted.
5. **Given** a policy-listed SKU that is regionally unavailable or lacks a required platform capability, **When** authenticated planning runs, **Then** it fails before ARM validation/deployment rather than treating catalogue inclusion as availability.

Implementation and evidence mapping: [catalogue](../../infra/catalog.json), [Bicep entry point](../../infra/main.bicep), [configuration preflight](../../pipelines/scripts/Test-Configuration.ps1), [Azure plan/apply checks](../../pipelines/scripts/Invoke-Deployment.ps1), and [supporting decision analysis](research.md#sap-vm-support-decision-evidence---bicepavm).

## Supporting Material

- [Reverse-engineered architecture, catalogues, source mapping, and limitations](research.md)
- [Specification completeness and validation checklist](checklists/requirements.md)
- [Bicep/AVM SAP VM support and deployment guide](../../infra/README.md#sap-support-and-vm-selection)

The structure follows the [Spec Kit feature specification template](https://github.com/github/spec-kit/blob/main/templates/spec-template.md). This change does not install Spec Kit tooling or create an implementation plan; a future plan should explicitly decide which legacy constraints to retain and which defects to correct.
