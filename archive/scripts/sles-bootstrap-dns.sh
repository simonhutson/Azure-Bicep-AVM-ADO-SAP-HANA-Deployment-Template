#!/bin/bash
# DNS settings bootstrap script for Azure Linux SLES instances
# Author: chouds27
exec > /root/bootstrap-dns.log 2>&1
set -ex

##############CHECK IF WE ARE RUNNING AS ROOT USER##############
[[ ${UID} -ne 0 ]] && { echo "[ERROR] $0 must be run as root. Exiting." >&2; exit 100; }

### Params ###
params_region=${1:-uksouth}

case $(echo $params_region | /usr/bin/awk '{print tolower($0)}') in
    uksouth)
        params_dnsserver="azsu-c-wdns-001.azure.uk.centricaplc.com"
        ;;
    ukwest)
        params_dnsserver="azsu-c-wdns-001.azure.uk.centricaplc.com"
        ;;
    westeurope)
        params_dnsserver="azwu-c-wdns-001.azure.uk.centricaplc.com"
        ;;
    northeurope)
        params_dnsserver="azwu-c-wdns-001.azure.uk.centricaplc.com"
        ;;
esac

params_vm_name=`/bin/hostname`
params_vm_ip=`ip addr list eth0 | /bin/grep "inet " | /usr/bin/cut -d' ' -f6 | cut -d/ -f1`

params_domainname='azure.uk.centricaplc.com'
params_dnssuffix='azure.uk.centricaplc.com aws.uk.centricaplc.com uk.centricaplc.com'

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

INSTANCE_ID=$vmId
INSTANCE_NAME=$params_vm_name

# Add DNS suffix
/bin/sed -i -e "s/^\(search\) \(.*\)/\1 $params_dnssuffix/" /etc/resolv.conf

# Forward entries
DNS_SERVER=$params_dnsserver
DNS_RECORD_NAME="$params_vm_name.$params_domainname"
DNS_RECORD_IP=$params_vm_ip
DNS_RECORD_TYPE="A"
DNS_RECORD_TTL="3600"

# Reverse entries
DNS_RECORD_TYPE_REV="PTR"
DNS_RECORD_TTL_REV="3600"
OCTET_1=`echo $DNS_RECORD_IP| cut -d "." -f 1`
OCTET_2=`echo $DNS_RECORD_IP| cut -d "." -f 2`
OCTET_3=`echo $DNS_RECORD_IP| cut -d "." -f 3`
OCTET_4=`echo $DNS_RECORD_IP| cut -d "." -f 4`
DNS_RECORD_NAME_REV="$OCTET_4.$OCTET_3.$OCTET_2.$OCTET_1.in-addr.arpa"

# Update DNS server
nsupdate -v <<EOF
server $DNS_SERVER
update del $DNS_RECORD_IP
update del $DNS_RECORD_NAME $DNS_RECORD_TYPE
update add $DNS_RECORD_NAME $DNS_RECORD_TTL $DNS_RECORD_TYPE $DNS_RECORD_IP
send
update del $DNS_RECORD_NAME_REV $DNS_RECORD_TYPE_REV
update add $DNS_RECORD_NAME_REV $DNS_RECORD_TTL_REV $DNS_RECORD_TYPE_REV $DNS_RECORD_NAME.
send
EOF

exit 0