<h1>Azure SAP Infrastructure</h1>
<h2>Bicep, Azure Verified Modules and Azure DevOps</h2>
<p>The <a href="infra/main.bicep">Bicep entry point</a> replaces property-by-property linked deployments with resource-sized Azure Verified Modules and a shared role catalogue. Separate <a href="infra/environments">environment parameter files</a> configure development, test and production. The <a href="azure-pipelines.yml">CI pipeline</a> builds and tests without Azure credentials; the <a href="pipelines/deploy.yml">deployment pipeline</a> validates, previews and applies the selected environment using federated service connections and protected-environment checks.</p>
<p>Start with the <a href="infra/README.md">migration and configuration guide</a> and <a href="pipelines/README.md">Azure DevOps setup guide</a>. Replace all <code>REQUIRED_</code> placeholders before deployment. The new baseline uses SLES for SAP 15, SSH-only administration and managed boot diagnostics. Legacy guest scripts are disabled; production sizing, HA, guest configuration and SAP/HANA readiness require separate review.</p>
<p>The <a href="infra/README.md#sap-support-and-vm-selection">SAP VM selection policy</a> distinguishes application/nonproduction candidates from exact-workload-certified production HANA SKUs, including an OLAP-specific BW choice. SAP Note 1928533 requires authorized login and was not accessed; a recorded operator support review is required before deployment. Certified VM selection does not certify the retained storage layout or the complete SAP system.</p>
<h2>Historical manual ARM deployment</h2>
<p>The original ARM templates, parameter examples, bootstrap scripts and diagram are preserved unchanged in <a href="archive/">archive/</a>. Their relative template layout is retained for historical reference and catalogue-parity testing.</p>
<p>This template takes a minimum amount of parameters and deploys one or more VMs, customized for use with 2-tier SAP HANA, using a variety of custom and gallery operating system images. Each VM is configured with two NICs, each with multiple IP addresses.</p>
<h2>Spec Kit definition</h2>
<p>The <a href="specs/001-sap-hana-dev-test/spec.md">reverse-engineered feature specification</a> defines the legacy deployment's scope, operator scenarios, requirements, and acceptance criteria. The <a href="specs/001-sap-hana-dev-test/research.md">supporting analysis</a> records the template flow, role and landscape catalogues, external prerequisites, bootstrap behavior, and known defects. A <a href="specs/001-sap-hana-dev-test/checklists/requirements.md">requirements checklist</a> distinguishes completed static analysis from unperformed runtime acceptance.</p>
<p>This is an as-is definition, not a deployment certification or modernization. The checked-in templates prepare infrastructure and attempt operating-system onboarding; they do not themselves install SAP/HANA. Known source-level blockers are documented, and the deployment templates and scripts are unchanged.</p>
<h2>Archived portal deployment entry points</h2>
<p>The following buttons and sizing table describe the original manual ARM workflow, not the new Bicep pipeline. The buttons retain their historical externally hosted URLs; they do not deploy the local archived files.</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.single.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploly SINGLE SAP VM</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.full.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploly FULL SAP VMs</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.netweavergateway.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploy a NetWeaver Gateway Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.gatewayfes.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploy a Gateway FES Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.sappo.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploy a SAP PO Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.sapbw.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploy a SAP BW Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.s4hanautilities.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploy a S/4HANA Utilities Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.cloudconnector.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploy a Cloud Connector Environment (1xApp)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdesmcguire%2FAzure-SAP-HANA-Dev-Test-Deployment-Templates%2Fmaster%2Fazuredeploy.s4hanahybrisbilling.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
Deploy a S/4HANA Hybris Billing Environment (4xApp, 1xDB)</p>
</p>
<p>The VMs are configured using the following sizes and data disk configurations</p>
<table>
	<tr>
		<th>VM Role</th>
		<th>VM Size</th>
		<th>VM Memory</th>
		<th>Data Disks</th>
	</tr>
	<tr>
		<td>App - NetWeaver Gateway</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - SAP PO</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - Gateway FES</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - SAP BW</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - S/4HANA Utilities</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - Convergent Charging</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - Convergent Invoicing</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - SOM (CRM ABAP)</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - SOM (CRM JAVA)</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>App - Cloud Connector</td>
		<td>E4s_v3</td>
		<td>32GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>DB - NetWeaver Gateway</td>
		<td>E8s_v3</td>
		<td>64GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB)<br>1xP6 (64GB), 1xP10 (128GB), 1xP6 (64GB), 1xP4 (32GB)</td>
	</tr>
	<tr>
		<td>DB - SAP PO</td>
		<td>E8s_v3</td>
		<td>64GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB)<br>1xP6 (64GB), 1xP10 (128GB), 1xP6 (64GB), 1xP4 (32GB)</td>
	</tr>
	<tr>
		<td>DB - Gateway FES</td>
		<td>E8s_v3</td>
		<td>64GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB)<br>1xP6 (64GB), 1xP10 (128GB), 1xP6 (64GB), 1xP4 (32GB)</td>
	</tr>
	<tr>
		<td>DB - SAP BW</td>
		<td>E16s_v3</td>
		<td>128GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB)<br>1xP10 (128GB), 1xP20 (512GB), 1xP10 (128GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>DB - S/4HANA Utilities</td>
		<td>E32s_v3</td>
		<td>256GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB)<br>1xP10 (128GB), 1xP20 (512GB), 1xP10 (128GB), 1xP6 (64GB)</td>
	</tr>
	<tr>
		<td>DB - S/4HANA Hybris Billing</td>
		<td>E32s_v3</td>
		<td>256GB</td>
		<td>1xP4 (32GB), 1xP4 (32GB)<br>1xP10 (128GB), 1xP20 (512GB), 1xP10 (128GB), 1xP6 (64GB)<br>1xP10 (128GB), 1xP20 (512GB), 1xP10 (128GB), 1xP6 (64GB)<br>1xP10 (128GB), 1xP20 (512GB), 1xP10 (128GB), 1xP6 (64GB)</td>
	</tr>
</table>
<p>
	<span>
		<img src="archive/SAP HANA Dev Test.png"/>
	</span>
<p>
