<h1>Azure SAP Infrastructure</h1>
<h2>Bicep, Azure Verified Modules and Azure DevOps</h2>
<p>The <a href="infra/main.bicep">Bicep entry point</a> composes resource-sized Azure Verified Modules and a shared role catalogue. Separate <a href="infra/environments">environment parameter files</a> configure development, test and production. The <a href="azure-pipelines.yml">CI pipeline</a> builds and tests without Azure credentials; the <a href="pipelines/deploy.yml">deployment pipeline</a> validates, previews and applies the selected environment using federated service connections and protected-environment checks. The portal options below deploy development environments independently of Azure DevOps.</p>
<p>Start with the <a href="infra/README.md">configuration guide</a> and <a href="pipelines/README.md">Azure DevOps setup guide</a>. Replace all <code>REQUIRED_</code> placeholders before using pipeline parameter examples. The baseline uses SLES for SAP 15, SSH-only administration and managed boot diagnostics. Guest bootstrap is disabled by default; production sizing, HA, guest configuration and SAP/HANA readiness require separate review.</p>
<p>The <a href="infra/README.md#sap-support-and-vm-selection">SAP VM selection policy</a> distinguishes application/nonproduction candidates from exact-workload-certified production HANA SKUs, including an OLAP-specific BW choice. SAP Note 1928533 requires authorized login and was not accessed; a recorded operator support review is required before deployment. Certified VM selection does not certify the retained storage layout or the complete SAP system.</p>
<h2>Deploy development with Bicep/AVM (Azure portal)</h2>
<p>Choose one of nine development profiles built from the current Bicep/AVM implementation. No Azure DevOps pipeline, service connection or approval is required. Every option uses SLES for SAP 15 SP6 BYOS Gen2, SSH-only administration, managed boot diagnostics, host encryption and two private NICs per VM. These templates provision infrastructure, not SAP/HANA software.</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fsingle.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a SINGLE development VM (one selected application or database role)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Ffull.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy the FULL development landscape (10xApp, 6xDB; 16 VMs)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fnetweaver-gateway.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a NetWeaver Gateway Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fgateway-fes.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a Gateway FES Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fsap-po.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a SAP PO Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fsap-bw.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a SAP BW Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fs4hana-utilities.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a S/4HANA Utilities Environment (1xApp, 1xDB)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fdevelopment.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a Cloud Connector Environment (1xApp)</p>
<p><a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimonhutson%2FAzure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template%2Fmain%2Finfra%2Fportal%2Fs4hana-hybris-billing.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton" alt="Deploy to Azure" />
</a>
Deploy a S/4HANA Hybris Billing Environment (4xApp, 1xDB)</p>
<h3>Portal inputs and prerequisites</h3>
<ol>
    <li>Choose a dedicated development resource group and a region matching an existing VNet in the same subscription. Supply its resource group, VNet name and two subnet names. All selected VMs share this pair: NIC 1 uses the first subnet and NIC 2 uses the second. IP configurations use dynamic allocation. No networking or public IP is created; use existing private connectivity such as VPN, ExpressRoute or Bastion.</li>
    <li>For SINGLE, select <code>singleRole</code> from the sixteen application/database roles and <code>singleInstanceNumber</code> from 0 to 9. It creates one VM with four dynamic IPv4 configurations per NIC. The other buttons use the catalogue's roles, instance numbers and NIC address counts; the single-VM fields are ignored.</li>
    <li>Supply an OpenSSH public key and a non-root administrator username. Select an available <code>SUSE:sles-sap-15-sp6-byos:gen2</code> image and enter its numeric major, minor and build version components; <code>latest</code> is not accepted. If image metadata requires a purchase plan, fill the optional <code>marketplacePlan</code> object with its <code>name</code>, <code>product</code> and <code>publisher</code>, and accept marketplace terms separately.</li>
    <li>Supply ownership, cost-code and change-request details plus a non-secret SAP support review reference. Choose a unique deployment number from 0 to 99, rendered as two digits in resource names. Confirm host-encryption support, permissions, subnet capacity and VM/disk quota for the entire selected profile. FULL creates 16 VMs, 32 NICs and 74 data disks.</li>
    <li>Review portal validation and costs before selecting <strong>Create</strong>. Each button fixes its development profile, uses development/test VM sizes and disables bootstrap. Production, arbitrary SKU overrides and custom disk overrides are not exposed.</li>
</ol>
<p><strong>Manual deployment boundary:</strong> Portal deployments do not run the pipeline's PowerShell preflight, Azure capability checks, what-if comparison or approval gates. Verify the <a href="infra/README.md#sap-support-and-vm-selection">SAP support policy</a>, pinned image availability, network capacity and applicable Azure policies yourself. ARM validation and a successful VM deployment do not establish SAP/HANA readiness.</p>
<p>Each button loads a self-contained <a href="infra/portal/">generated ARM JSON template</a> produced from <a href="infra/portal/development.bicep">the shared portal entry point</a> and <a href="infra/main.bicep">the shared Bicep implementation</a>. Azure portal does not deploy remote Bicep files or automatically read Bicep parameter files. Publish the JSON files to <code>main</code> before using the buttons; for a fork or another branch, update their URLs. No credentials are embedded in these templates.</p>
<p>Maintainers: run <code>.\pipelines\scripts\Build-IaC.ps1 -UpdatePortalTemplate</code> with the <a href="pipelines/tools.psd1">pinned Bicep compiler</a> and commit all generated JSON with its source changes. Generation changes only the launch-profile default, allowed value and generation metadata. CI checks all nine files against the current build and verifies their topology and README labels.</p>
<h2>VM sizes and data disks</h2>
<p>Defaults come from <a href="infra/catalog.json">the Bicep role catalogue</a>. All portal options use the development/test column; production defaults apply only to separately configured production deployments. Each VM-size cell includes RAM in GiB. Data disks are requested capacities in LUN order, not a production storage recommendation. See the <a href="infra/README.md#sap-support-and-vm-selection">SAP support policy</a> before using or overriding any size.</p>
<table>
	<tr>
		<th>VM Role</th>
		<th>Bicep dev/test size / RAM</th>
		<th>Bicep production size / RAM</th>
		<th>Data disks (GiB, LUN order)</th>
	</tr>
	<tr>
		<td>App - NetWeaver Gateway (IMOS)</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SAP PO (IMOS)</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - NetWeaver Gateway FES</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SAP BW</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - S/4HANA Utilities</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - Convergent Charging</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - Convergent Invoicing</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SOM (CRM ABAP)</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - SOM (CRM JAVA)</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>App - Cloud Connector</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>Standard_E4ds_v5 / 32</td>
		<td>32, 32, 64</td>
	</tr>
	<tr>
		<td>DB - NetWeaver Gateway (IMOS)</td>
		<td>Standard_E8ds_v5 / 64</td>
		<td>Standard_E20ds_v5 / 160</td>
		<td>32, 32, 64, 128, 64, 32</td>
	</tr>
	<tr>
		<td>DB - SAP PO (IMOS)</td>
		<td>Standard_E8ds_v5 / 64</td>
		<td>Standard_E20ds_v5 / 160</td>
		<td>32, 32, 64, 128, 64, 31</td>
	</tr>
	<tr>
		<td>DB - NetWeaver Gateway FES</td>
		<td>Standard_E8ds_v5 / 64</td>
		<td>Standard_E20ds_v5 / 160</td>
		<td>32, 32, 64, 128, 64, 32</td>
	</tr>
	<tr>
		<td>DB - SAP BW</td>
		<td>Standard_E16ds_v5 / 128</td>
		<td>Standard_M32ls / 256</td>
		<td>32, 32, 128, 512, 128, 64</td>
	</tr>
	<tr>
		<td>DB - S/4HANA Utilities</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>32, 32, 128, 512, 128, 64</td>
	</tr>
	<tr>
		<td>DB - S/4HANA Hybris Billing</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>Standard_E32ds_v5 / 256</td>
		<td>32, 32, 128, 256, 128, 64,<br>128, 256, 128, 64,<br>128, 256, 128, 64</td>
	</tr>
</table>
