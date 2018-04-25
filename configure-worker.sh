#!/bin/bash


k8sPodNetworkCidr=192.168.0.0/16
k8sServiceCidr=172.16.1.0/24
hostname=$(hostname)

set -o errexit
set -o pipefail

function usage() {
    echo "Usage: -m masterIp -t token -i interfaceName -g gatewayAddress [-p podNetwork] [-s serviceNetwork]"
    echo
    echo "Options:"
    echo "    -m, --master-ip        Required: The external IP address of the master node"
    echo "    -t, --token            Required: The Kubernetes API authentication token, or path to file containing the token"
    echo "    -i, --interface-name   Required: The interface in minions that will be the gateway interface."
    echo "    -g, --gateway-address  Required: The external default gateway which is used as a next hop by OVN gateway.  This is many times just the default gateway of the node in question."
    echo "    -p, --pod-network      Optional: Cluster wide IP subnet to use. (default ${k8sPodNetworkCidr})"
    echo "    -s, --service-network  Optional: A CIDR notation IP range from which k8s assigns service cluster IPs. This should be the same as the one provided for kube-apiserver \"-service-cluster-ip-range\" option. (default ${k8sServiceCidr})"
    echo "    -h, --help             display help"
    exit 1
}

function validateArgs() {
    if [ -z "${k8sPodNetworkCidr}" ] || [ -z "${k8sServiceCidr}" ]; then
        echo "Invalid arguments - flag with missing argument value";
        usage;
    fi

    if [ -z "${masterIp}" ]; then
        echo "Missing required parameter master-ip";
        usage;
    fi
    if [ -z "${token}" ]; then
        echo "Missing required parameter token";
        usage;
    fi
    if [ -z "${interfaceName}" ]; then
        echo "Missing required parameter interface-name";
        usage;
    fi
    if [ -z "${gatewayAddress}" ]; then
        echo "Missing required parameter gateway-address";
        usage;
    fi
}


while true; do
  case "$1" in
    -t | --token	        ) token="$2"; shift ;;
    -m | --master-ip        ) masterIp="$2"; shift ;;
    -i | --interface-name   ) interfaceName="$2"; shift ;;
    -g | --gateway-address  ) gatewayAddress="$2"; shift ;;
    -p | --pod-network      ) k8sPodNetworkCidr="$2"; shift ;;
    -s | --service-network  ) k8sServiceCidr="$2"; shift ;;
    -h |--help ) usage;;
    -- ) shift; break ;;
        -*) echo "ERROR: unrecognized option $1"; exit 1;;
    * ) break ;;
  esac
  shift
done


validateArgs

if [ -f ${token} ]; then
    token=$(cat ${token});
fi

#create the ovnkube service file
cat > /etc/systemd/system/ovnkube.service <<- END
[Unit]
Description=ovnkube
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/ovnkube -init-node ${hostname} \
                           -k8s-cacert /etc/kubernetes/pki/ca.crt \
                           -k8s-token "${token}" \
                           -nodeport \
                           -init-gateways \
                           -k8s-apiserver "https://${masterIp}:6443" \
                           -cluster-subnet "${k8sPodNetworkCidr}" \
                           -service-cluster-ip-range "${k8sServiceCidr}" \
                           -gateway-nexthop "${gatewayAddress}" \
                           -gateway-interface "${interfaceName}" \
                           -nb-address "tcp://${masterIp}:6641" \
                           -sb-address "tcp://${masterIp}:6642" \
                           -loglevel 5 \
                           -logfile /var/log/ovnkube.log

Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
END

#and enable the service
systemctl enable ovnkube.service
systemctl start ovnkube.service
