# Specification Quality Checklist: SAP HANA Dev/Test Infrastructure

**Created**: 2026-10-26

**Feature**: [spec.md](../spec.md)

**Evidence**: [research.md](../research.md)

## Content and Scope

- [x] Purpose distinguishes infrastructure preparation from SAP/HANA installation.
- [x] In-scope behavior and non-goals are explicit; no modernization is silently introduced.
- [x] Operator journeys are prioritized and include independent tests and Given/When/Then acceptance scenarios.
- [x] Functional requirements have unique identifiers and source traceability.
- [x] Key entities, assumptions, dependencies, and edge cases are defined.
- [x] Success criteria are measurable without inventing timing, availability, or production-certification promises.

## Legacy Coverage

- [x] All nine launch wrappers and the shared core are accounted for.
- [x] All sixteen role profiles and all three image choices are accounted for.
- [x] Compute, disk order/capacity, naming, tags, subnet selection, NIC allocation, and acceleration are recorded.
- [x] All six bootstrap stages are traced in their configured execution order.
- [x] All seven parameter examples are mapped to their wrappers; the required password omission is explicit.
- [x] Existing infrastructure and corporate-service prerequisites are separated from newly requested resources.
- [x] Wrapper outputs, core outputs, incremental behavior, and partial-failure boundaries are distinguished.

## Evidence Integrity

- [x] Intended behavior, checked-in behavior, and unverified runtime outcomes are kept separate.
- [x] Strict JSON checking records 46 valid files out of 47, not a false all-pass result.
- [x] Invalid NetWeaver roles, the PO bootstrap key typo, and disk/LUN mismatches are explicit.
- [x] README sizing discrepancies and non-explicit data-disk storage SKUs are recorded without guessing fixes.
- [x] Secret-handling and destructive/non-idempotent bootstrap limitations are documented without copying secret values.
- [x] Local script behavior is not claimed to prove the contents of the remotely downloaded artifacts.
- [x] No implementation plan, source fix, deployment, or SAP readiness result is implied by this definition.

## SAP VM Support Addendum

- [x] Modern SKU decisions are explicitly separated from the historical ARM requirements and compute catalogue.
- [x] Exact development/test and production defaults, permitted override subsets, and the production-only HANA certification decision are recorded.
- [x] Production OLTP and BW/OLAP selections link to distinct public SAP certification records with an evidence date.
- [x] Application/nonproduction candidates are not misrepresented as independently verified Note 1928533 listings.
- [x] SAP Notes 1928533 and 2235581 are linked with explicit access/verification status; no protected Note content or SAPS values are claimed read.
- [x] Addendum requirements and acceptance scenarios cover environment resolution, workload-specific overrides, support-review references and Azure capability checks.
- [x] Complete-system certification is distinguished from VM certification, including the unresolved production data/log storage restrictions.

### Outstanding SAP Support Reviews

These remain open prerequisites, not completed checks implied by documenting the selections.

- [ ] Obtain an authorized current Note 1928533 review for exact application/nonproduction SKUs, supported products and applicable SAPS/OS/kernel restrictions.
- [ ] Verify the target OS/HANA patch-level combination against Note 2235581 and the applicable product availability/component requirements.
- [ ] Qualify production HANA data/log storage, IOPS/throughput and guest filesystems; do not approve the retained all-`Premium_LRS` baseline merely because its VM is certified.
- [ ] Record the actual support-review evidence reference and verify current certificates plus target-region/subscription availability before deployment.

## Runtime Acceptance Not Performed

The following require a separately approved, prepared test environment. They are not completion claims for this documentation task.

- [ ] Validate the unchanged legacy templates against live Azure resource schemas and deployment validation.
- [ ] Verify current image, SKU, quota, Key Vault, storage, network, and corporate-service availability.
- [ ] Execute disposable single-role and landscape acceptance tests after resolving applicable source blockers.
- [ ] Verify guest storage, registration, DNS, proxy, and Puppet outcomes independently of extension exit status.
- [ ] Verify SAP/HANA installation and readiness through an external workflow, if required.
