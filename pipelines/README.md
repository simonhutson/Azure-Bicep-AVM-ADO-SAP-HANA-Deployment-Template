# Azure DevOps IaC pipelines

Use Azure DevOps Services, an existing resource group per environment, and the [Bicep configuration guide](../infra/README.md). These files automate infrastructure delivery only.

## Register Two Pipelines

1. Create the CI pipeline from [../azure-pipelines.yml](../azure-pipelines.yml).
2. Create the infrastructure deployment pipeline from [deploy.yml](deploy.yml).
3. Configure all target settings in [environments/](environments/) and matching [Bicep parameter files](../infra/environments/).
4. Queue the deployment pipeline from protected `main`, choosing `development`, `test` or `production`.

CI runs builds/linting, catalogue parity tests, automation guard tests and YAML parsing without a service connection or Azure resource operations. For GitHub repositories, YAML `pr` triggers validate pull requests. **Azure Repos Git does not implement YAML PR triggers**: configure a build-validation branch policy on `main` for the CI pipeline instead.

Deployment is intentionally not triggered by a pull request or every commit. A single run targets one environment; there is no automatic dev-to-production promotion. Each target is independently configured and authorized.

## Identity and Permissions

Create separate Azure Resource Manager service connections for **plan** and **deploy** in each environment, using **workload identity federation**, not client secrets.

Do not enable "Grant access permission to all pipelines." Authorize only the deployment pipeline, and protect the service connections against unreviewed pipeline changes.

| Identity | Intended permissions |
|---|---|
| Plan connection | Resource reads plus `Microsoft.Resources/deployments/validate/action` and `Microsoft.Resources/deployments/whatIf/action` on the target scope. Uses `ProviderNoRbac` validation, so it need not be a resource writer. |
| Deploy connection | Contributor on the target VM resource group, plus read/join permissions for the existing VNet/subnets. Uses `Provider` validation before applying. It does not create role assignments, so Owner is unnecessary. |
| Both | Read the shared VNet and selected image metadata. Planning also reads regional VM SKUs/capabilities and subscription restrictions. Subscription-level SKU/feature/image reads may need additional narrowly scoped permission; an RG-only assignment does not automatically cover those APIs. |
| Deploy, if bootstrap enabled | Managed Identity Operator, or equivalent assign permission, on the existing bootstrap identity. |
| Guest bootstrap identity | Storage Blob Data Reader on the approved artifact container/blob, and only the runtime secret/service access required by the reviewed script. |

Prefer custom roles and narrow scopes consistent with organizational policy. Do not use subscription-wide Contributor or Owner to make a validation error disappear. The pipeline checks the authenticated subscription ID and never silently switches to a different subscription. Target resource groups, networks, identities and artifacts must already exist.

## Protected Environments: Required External Setup

Create these Azure DevOps Environments **before** authorizing deployment:

- `sap-development`
- `sap-test`
- `sap-production`

Apply **Approvals and checks** in Azure DevOps, not just YAML:

1. Add **Exclusive lock** to every environment. The YAML's `lockBehavior: sequential` has no locking effect without this external check.
2. Add designated approvers for test and production. Disable self-approval for production.
3. Add **Branch control** allowing only protected `refs/heads/main`; fail closed when branch protection is unknown.
4. Restrict environment administration, pipeline permissions and creation rights. Do not let a deployment author bypass approval by creating an unprotected replacement environment.
5. Protect `main`, the pipeline templates, environment configuration and service connections through required reviewers and branch policies.

Approval checks are deliberately managed by resource owners outside YAML, so a code change cannot simply remove them. **The repository cannot create or prove those checks. Without this setup, merely referencing `sap-production` in YAML does not enforce approval.**

If networks/artifact services are private, use a hardened self-hosted pool with the necessary private connectivity. The examples use `ubuntu-24.04` Microsoft-hosted agents; change the pool through a reviewed edit if organizational connectivity/policy requires it. Azure control-plane access is not proof that guests can reach package, DNS or management endpoints.

## Execution and Artifacts

```text
Build (no Azure identity)
  -> Plan (plan WIF connection)
       -> protected Environment checks and exclusive lock
            -> Deploy (deploy WIF connection)
```

### Build

- Restores pinned Bicep, Pester and YAML-parser versions from [tools.psd1](tools.psd1) when missing.
- Builds/lints Bicep and compiles all three environment parameter files.
- Runs [the test suite](../tests/) and publishes test results.
- Publishes the `iac` artifact containing the compiled template, compiled parameters, catalogue and a SHA-256/source-commit manifest.

### Plan

- Rejects altered artifacts, a mismatched commit/environment, placeholders, missing SAP support review references, invalid image versions, invalid identifiers/IPs, duplicate VM names and unsafe bootstrap input.
- Resolves role/environment VM defaults; rejects out-of-policy SKU overrides and requires exact-workload certification records for production HANA (OLTP versus BW/OLAP). Application/nonproduction candidates still require an authorized Note 1928533 review; the pipeline does not read that Note.
- Verifies the connection's subscription and the existing target resource group.
- Checks image availability and Gen2 metadata, any required purchase plan, host-encryption feature registration, VNet location and selected subnet existence.
- Checks actual regional/subscription VM SKU availability and restrictions, x64/Gen2 capability, two-NIC and disk-count limits, Premium storage, encryption-at-host support and database accelerated networking. Azure capabilities are not a SAP certificate or deploy-time capacity guarantee.
- Runs Azure provider validation and full-payload what-if.
- Fails on failed/incomplete/unknown changes, `Ignore`, `Unsupported` or `Delete`; it does not convert an uninspectable preview into an approval.
- Publishes `plan-<environment>` with `what-if.json` and a plan record binding target, commit, artifact hash and normalized change digest, plus resolved VM selections and the SAP support review reference.

Review the raw change set, especially VM image, disk, NIC and placement updates, before approving the protected environment. What-if is a preview, not a guarantee of regional capacity or deployment success.

### Deploy

- Downloads `iac` and the plan from **the same run**, not "latest successful."
- Enters the protected environment's lock and rechecks artifact identity.
- Validates using the deployment connection's permissions and reruns what-if inside the lock.
- Compares the current change digest to the approved plan. Drift requires a fresh plan and approval, not a bypass switch.
- Applies exactly the compiled template/parameters in incremental mode.
- Verifies successful ARM state, VM count, each VM's provisioning state and actual SKU, two NICs, SSH-only login, and ordered data-disk capacities.
- Publishes `deployment-<environment>` with non-secret infrastructure outputs, explicitly marking SAP readiness as unverified.

The lock serializes cooperating deployments, not every external Azure writer. There is still a small race between the last what-if and ARM's apply; enforce organizational change controls and restrict out-of-band writes. ARM deployments are not transactional and do not provide automatic rollback.

## Operating Notes

- Do not add credentials to the parameter files, tags, custom-script command, build logs, plan files or artifacts. Only public SSH keys are expected here.
- Retain pipeline artifacts and approval history according to organizational audit policy. Full what-if payloads contain internal topology/IP information, even though this baseline has no credential values.
- Rotate SSH keys through a separate operational process; changing the initial administrator key on an existing VM may require an explicit access-extension workflow.
- A failed deployment can leave successful sibling resources behind. Inspect its operations and resolve the cause before retrying.
- Removing a role from the desired VM list does not delete it. Decommission resources through a separately approved cleanup/data-retention workflow.
- Never run the archived destructive disk scripts as an automatic "repair" step.
- Promote tested commits through environments using reviewed configuration. Do not treat these independent samples as already sized for production.
- Production HANA VM certification is workload-specific and does not approve the retained all-Premium-SSD-v1 disk layout. Resolve the HANA log/data storage restrictions and guest configuration described in the [VM selection guide](../infra/README.md#sap-support-and-vm-selection) before installing a production workload.
- Pipeline YAML was parsed and behavior-tested locally. Azure DevOps authorization, full template expansion, Azure provider validation and an actual run require your organization and configured resources.

## Official References

- [Workload identity federation service connections](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure)
- [Environment approvals, branch control and exclusive locks](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals)
- [Bicep what-if](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-what-if)
- [Azure Repos build-validation policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies#build-validation)
