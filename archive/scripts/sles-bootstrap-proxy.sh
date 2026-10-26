#!/bin/bash
# Proxy settings bootstrap script for Azure Linux SLES instances
# Author: chouds27
exec > /root/bootstrap-proxy.log 2>&1
set -ex

##############CHECK IF WE ARE RUNNING AS ROOT USER##############
[[ ${UID} -ne 0 ]] && { echo "[ERROR] $0 must be run as root. Exiting." >&2; exit 100; }

### Params ###
params_region=${1:-uksouth}

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

### Configure /etc/sysconfig/proxy ###
/bin/sed -i "s|^PROXY_ENABLED=.*|PROXY_ENABLED=\"yes\"|" /etc/sysconfig/proxy
/bin/sed -i "s|^HTTP_PROXY=.*|HTTP_PROXY=\"$params_proxy\"|" /etc/sysconfig/proxy
/bin/sed -i "s|^HTTPS_PROXY=.*|HTTPS_PROXY=\"$params_proxy\"|" /etc/sysconfig/proxy
/bin/sed -i "s|^NO_PROXY=.*|NO_PROXY=\"$params_no_proxy\"|" /etc/sysconfig/proxy

### Extract proxy server by stripping out protocol and port ###
proxy_server=`echo $params_proxy | /bin/sed -e 's|http[s]*:\/\/||' | /bin/sed -e 's|\(.*\):\(.*\)|\1|'`

if [[ $proxy_server != *['!':@#\$%^\&*()\|\/,\=+]* ]]; then #Check for special characters

    proxy_port=`echo $params_proxy | /bin/sed -e 's|http[s]*:\/\/||' | /bin/sed -e 's|\(.*\):\([0-9]*\)|\2|'`

    #Special case where protocol or port are not specified
    if [[ $proxy_server != $proxy_port ]]; then
        [[ ! $proxy_port =~ ^[0-9]+$ ]] && { echo "[ERROR] Proxy port $proxy_port not a valid number. Exiting." >&2; exit 142; }
    else
        proxy_port=""
    fi

else
    echo '[ERROR] Proxy server $proxy_server contains invalid characters (!:@#$%^&*()|/,=+). Exiting.' >&2; exit 141;
fi

### Configure Azure Linux agent to use proxy server ###
/bin/sed -i -e "s|.*HttpProxy.Host=None|HttpProxy.Host=$proxy_server|" /etc/waagent.conf
[[ ! -z "${proxy_port// }" ]] && /bin/sed -i -e "s|.*HttpProxy.Port=None|HttpProxy.Port=$proxy_port|" /etc/waagent.conf
/bin/sed -i -e "s|.*AutoUpdate.Enabled=n|AutoUpdate.Enabled=y|" /etc/waagent.conf

exit 0