<h1>Azure SAP Infrastructure</h1>
<h2>Bicep, Azure Verified Modules and Azure DevOps</h2>
<p>The <a href="infra/main.bicep">Bicep entry point</a> replaces property-by-property linked deployments with resource-sized Azure Verified Modules and a shared role catalogue. Separate <a href="infra/environments">environment parameter files</a> configure development, test and production. The <a href="azure-pipelines.yml">CI pipeline</a> builds and tests without Azure credentials; the <a href="pipelines/deploy.yml">deployment pipeline</a> validates, previews and applies the selected environment using federated service connections and protected-environment checks.</p>
<p>Start with the <a href="infra/README.md">migration and configuration guide</a> and <a href="pipelines/README.md">Azure DevOps setup guide</a>. Replace all <code>REQUIRED_</code> placeholders before deployment. The new baseline uses SLES for SAP 15, SSH-only administration and managed boot diagnostics. Legacy guest scripts are disabled; production sizing, HA, guest configuration and SAP/HANA readiness require separate review.</p>
<p>The <a href="infra/README.md#sap-support-and-vm-selection">SAP VM selection policy</a> distinguishes application/nonproduction candidates from exact-workload-certified production HANA SKUs, including an OLAP-specific BW choice. SAP Note 1928533 requires authorized login and was not accessed; a recorded operator support review is required before deployment. Certified VM selection does not certify the retained storage layout or the complete SAP system.</p>
<h2>Historical manual ARM deployment</h2>
<p>The original ARM templates, parameter examples and bootstrap scripts are preserved unchanged in <a href="archive/">archive/</a>. Their relative template layout is retained for historical reference and catalogue-parity testing.</p>
<p>This template takes a minimum amount of parameters and deploys one or more VMs, customized for use with 2-tier SAP HANA, using a variety of custom and gallery operating system images. Each VM is configured with two NICs, each with multiple IP addresses.</p>
<h2>Spec Kit definition</h2>
<p>The <a href="specs/001-sap-hana-dev-test/spec.md">reverse-engineered feature specification</a> defines the legacy deployment's scope, operator scenarios, requirements, and acceptance criteria. The <a href="specs/001-sap-hana-dev-test/research.md">supporting analysis</a> records the template flow, role and landscape catalogues, external prerequisites, bootstrap behavior, and known defects. A <a href="specs/001-sap-hana-dev-test/checklists/requirements.md">requirements checklist</a> distinguishes completed static analysis from unperformed runtime acceptance.</p>
<p>This is an as-is definition, not a deployment certification or modernization. The checked-in templates prepare infrastructure and attempt operating-system onboarding; they do not themselves install SAP/HANA. Known source-level blockers are documented, and the deployment templates and scripts are unchanged.</p>
<h2>Manual development deployment (Azure portal)</h2>
<p>Use these entry points for the separate, archived ARM development workflow. The buttons load templates from this repository's <code>main/archive/</code> directory directly into Azure portal; they do not queue Azure DevOps pipelines or require pipeline service connections or approvals. They do not use the Bicep environment files, current VM catalogue or pipeline validation checks.</p>
<ol>
    <li>Review the <a href="specs/001-sap-hana-dev-test/research.md#external-prerequisites">archived external prerequisites</a> and known defects before deploying. The unchanged validator accepts only the subscription display name <code>SAP Dev Test</code> and resource-group location <code>uksouth</code>. Existing networks, Key Vault secrets, script storage, diagnostic storage and guest-service endpoints must be available.</li>
    <li>Select a button, sign in to Azure and choose a dedicated development resource group. Supply the deployment number, instance/role for a single VM, image, administrator credentials, NIC address arrays and ownership tags. Blank NIC address entries request dynamic allocation.</li>
    <li>Review portal validation, quota and costs before selecting <strong>Create</strong>. This workflow provisions infrastructure and attempts legacy guest bootstrap; it does not install SAP/HANA and is not a production deployment path.</li>
</ol>
<p><strong>Legacy limitations:</strong> The archive still uses SLES for SAP 12 images, password administration and known role/bootstrap defects documented in the <a href="specs/001-sap-hana-dev-test/research.md">source analysis</a>. Updating these links does not resolve those defects or verify that the old images and external services remain available. For another subscription or region, adapt and publish a separate copy of the complete archived bundle first.</p>
<p>Azure must be able to retrieve the entry template and its sibling linked templates over HTTPS. Keep the archived directory layout intact; if using a fork or another branch, update the repository and branch in the button URLs. These buttons load the published branch, not files from a local checkout.</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.single.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a SINGLE development VM (one selected application or database role)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.full.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy the FULL development landscape (10xApp, 6xDB; 16 VMs)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.netweavergateway.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a NetWeaver Gateway Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.gatewayfes.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a Gateway FES Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.sappo.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a SAP PO Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.sapbw.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a SAP BW Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.s4hanautilities.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a S/4HANA Utilities Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.cloudconnector.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a Cloud Connector Environment (1xApp)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Farchive%2Fazuredeploy.s4hanahybrisbilling.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a S/4HANA Hybris Billing Environment (4xApp, 1xDB)</p>
<h2>VM sizes and data disks</h2>
<p>The manual portal defaults come from the <a href="archive/settings.vm.hardwareprofile.json">archived hardware profiles</a>; the current Bicep defaults come from <a href="infra/catalog.json">the role catalogue</a>. Portal deployments do not inherit Bicep sizes. Each VM-size cell includes RAM in GiB. Data disks are requested capacities in LUN order, shared by both sets of role profiles, not a production storage recommendation. See the <a href="infra/README.md#sap-support-and-vm-selection">SAP support policy</a> before using or overriding any size.</p>
<table>
	<tr>
		<th>VM Role</th>
		<th>Manual ARM dev size / RAM</th>
		<th>Bicep dev/test size / RAM</th>
		<th>Bicep production size / RAM</th>
		<th>Data disks (GiB, LUN order)</th>
	</tr>
	<tr>
		<td>App - NetWeaver Gateway (IMOS)</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SAP PO (IMOS)</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - NetWeaver Gateway FES</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SAP BW</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - S/4HANA Utilities</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - Convergent Charging</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - Convergent Invoicing</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SOM (CRM ABAP)</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SOM (CRM JAVA)</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - Cloud Connector</td>
		<td>Standard_E4s_v3 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>DB - NetWeaver Gateway (IMOS)</td>
		<td>Standard_E8s_v3 / 64</td>
		<td>Standard_E8ds_v5 / 64</td>
		<td>Standard_E20ds_v5 / 160</td>
		<td>32, 32, 64, 128, 64, 32</td>
	</tr>
	<tr>
		<td>DB - SAP PO (IMOS)</td>
		<td>Standard_E8s_v3 / 64</td>
		<td>Standard_E8ds_v5 / 64</td>
		<td>Standard_E20ds_v5 / 160</td>
		<td>32, 32, 64, 128, 64, 31</td>
	</tr>
	<tr>
		<td>DB - NetWeaver Gateway FES</td>
		<td>Standard_E8s_v3 / 64</td>
		<td>Standard_E8ds_v5 / 64</td>
		<td>Standard_E20ds_v5 / 160</td>
		<td>32, 32, 64, 128, 64, 32</td>
	</tr>
	<tr>
		<td>DB - SAP BW</td>
		<td>Standard_E16s_v3 / 128</td>
		<td>Standard_E16ds_v5 / 128</td>
		<td>Standard_M32ls / 256</td>
		<td>32, 32, 128, 512, 128, 64</td>
	</tr>
	<tr>
		<td>DB - S/4HANA Utilities</td>
		<td>Standard_E32s_v3 / 256</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>32, 32, 128, 512, 128, 64</td>
	</tr>
	<tr>
		<td>DB - S/4HANA Hybris Billing</td>
		<td>Standard_E32s_v3 / 256</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>32, 32, 128, 256, 128, 64,<br>128, 256, 128, 64,<br>128, 256, 128, 64</td>
	</tr>
</table>
