#!/bin/bash
# Puppet bootstrap script for Azure Linux SLES instances
# Author: chouds27
exec > /root/bootstrap-puppet.log 2>&1
set -ex

##############CHECK IF WE ARE RUNNING AS ROOT USER##############
[[ ${UID} -ne 0 ]] && { echo "[ERROR] $0 must be run as root. Exiting." >&2; exit 100; }

### Params ###
params_region=${1:-ukusouth}

case $(echo $params_region | /usr/bin/awk '{print tolower($0)}') in
    uksouth)
        params_proxy="http://proxy-azsu.azure.uk.centricaplc.com:8080"
            ;;
    ukwest)
        params_proxy="http://proxy-azwu.azure.uk.centricaplc.com:8080"
            ;;
    westeurope)
        params_proxy="http://proxy.azure.uk.centricaplc.com:8080"
            ;;
    northeurope)
        params_proxy="http://proxy.azure.uk.centricaplc.com:8080"
            ;;
esac

params_no_proxy='localhost,127.0.0.1,169.254.169.254,168.63.129.16,194.176.222.243,62.60.15.82,puppet.aws.uk.centricaplc.com,puppet.azure.uk.centricaplc.com,.centricaplc.com,.uk.centricaplc.com,.azure.uk.centricaplc.com,.ce.centricaplc.com,ce-sts.centricaplc.com,.centricadev.com,connect.centricaplc.com,connect-uat.centricaplc.com,gateway.centricaplc.com,Sts.centricaplc.com,.centrica.geodata.co.uk,.verisign.com'

### Export proxy environment variables ###
export http_proxy=$params_proxy
export https_proxy=$params_proxy
export no_proxy=$params_no_proxy

params_puppet_environment=${2:-core}
params_puppet_role=${3:-core::acn::syslog}
params_puppet_preshared_key=${4:-}

puppet_default_imagename="SUSE:SLES-SAP:12-SP2:latest"
params_puppet_imagename=${5:-$puppet_default_imagename}

params_vm_name=`/bin/hostname`
params_vm_ip=`ip addr list eth0 | /bin/grep "inet " | /usr/bin/cut -d' ' -f6 | cut -d/ -f1`
params_puppet_master="puppet.aws.uk.centricaplc.com"
params_puppet_cloudplatform="azure"
params_puppet_rpmlocation='https://yum.puppetlabs.com/puppetlabs-release-pc1-sles-12.noarch.rpm'

# Get the VM instance GUID and format it due to big endian encoding
vmIdLine=$(dmidecode | grep UUID)
echo "---- VMID ----"
echo $vmIdLine
vmId=${vmIdLine:6:37}
echo "---- VMID ----"
echo $vmId

# For the first 3 sections of the GUID, the hex codes need to be reversed
vmIdCorrectParts=${vmId:20}
vmIdPart1=${vmId:0:9}
vmIdPart2=${vmId:10:4}
vmIdPart3=${vmId:15:4}
vmId=${vmIdPart1:7:2}${vmIdPart1:5:2}${vmIdPart1:3:2}${vmIdPart1:1:2}-${vmIdPart2:2:2}${vmIdPart2:0:2}-${vmIdPart3:2:2}${vmIdPart3:0:2}-$vmIdCorrectParts
vmId=${vmId,,}
echo "---- VMID fixed ----"
echo $vmId

### Puppet boostrapping ###
mkdir -p /etc/puppetlabs/puppet

cat > /etc/puppetlabs/puppet/csr_attributes.yaml << YAML
extension_requests:
  pp_instance_id: $vmId
  pp_image_name: $params_puppet_imagename
  pp_preshared_key: $params_puppet_preshared_key
  pp_hostname: $params_vm_name
  pp_cloudplatform: $params_puppet_cloudplatform
  pp_region: $params_region
  pp_role: $params_puppet_role
  pp_environment: $params_puppet_environment
YAML

chmod 600 /etc/puppetlabs/puppet/csr_attributes.yaml
rpm -ivh $params_puppet_rpmlocation
zypper -n --gpg-auto-import-keys install puppet-agent-1.8.3-1.sles12
PUPPET='/opt/puppetlabs/bin/puppet'
$PUPPET config set server $params_puppet_master --section agent
$PUPPET config set certname $params_vm_name --section agent
systemctl enable puppet

# Run puppet
nohup sh -c '(/opt/puppetlabs/bin/puppet agent -t)' > /dev/null &

exit 0