#!/bin/bash -e
#
# Copyright (c) 2021 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, v. 2 except as noted otherwise in the LICENSE file
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function log() {
  echo "[$(date -u)]: $*"
}

trap 'exit' TERM SIGINT

openvpn_port="${OPENVPN_PORT:-8132}"

tcp_keepalive_time="${TCP_KEEPALIVE_TIME:-7200}"
tcp_keepalive_intvl="${TCP_KEEPALIVE_INTVL:-75}"
tcp_keepalive_probes="${TCP_KEEPALIVE_PROBES:-9}"
tcp_retries2="${TCP_RETRIES2:-5}"

ENDPOINT="${ENDPOINT}"

function set_value() {
  if [ -f $1 ] ; then
    log "Setting $2 on $1"
    echo "$2" > $1
  fi
}

function configure_tcp() {
  set_value /proc/sys/net/ipv4/tcp_keepalive_time $tcp_keepalive_time
  set_value /proc/sys/net/ipv4/tcp_keepalive_intvl $tcp_keepalive_intvl
  set_value /proc/sys/net/ipv4/tcp_keepalive_probes $tcp_keepalive_probes

  set_value /proc/sys/net/ipv4/tcp_retries2 $tcp_retries2
}

if [[ -z "$DO_NOT_CONFIGURE_KERNEL_SETTINGS" ]]; then
  configure_tcp

  # make sure forwarding is enabled
  echo 1 > /proc/sys/net/ipv4/ip_forward
fi

if [[ ! -z "$EXIT_AFTER_CONFIGURING_KERNEL_SETTINGS" ]]; then
  exit
fi

# for each cidr config, it looks first at its env var, then a local file (which may be a volume mount), then the default
baseConfigDir="/init-config"
fileServiceNetwork=
filePodNetwork=
fileNodeNetwork=
[ -e "${baseConfigDir}/serviceNetwork" ] && fileServiceNetwork=$(cat ${baseConfigDir}/serviceNetwork)
[ -e "${baseConfigDir}/podNetwork" ] && filePodNetwork=$(cat ${baseConfigDir}/podNetwork)
[ -e "${baseConfigDir}/nodeNetwork" ] && fileNodeNetwork=$(cat ${baseConfigDir}/nodeNetwork)

service_network="${SERVICE_NETWORK:-${fileServiceNetwork}}"
service_network="${service_network:-100.64.0.0/13}"
pod_network="${POD_NETWORK:-${filePodNetwork}}"
pod_network="${pod_network:-100.96.0.0/11}"
node_network="${NODE_NETWORK:-${fileNodeNetwork}}"
node_network="${node_network:-}"

reversed_vpn_header="${REVERSED_VPN_HEADER:-invalid-host}"

sed -e "s/\${SERVICE_NETWORK}/${service_network}/" \
    -e "s/\${POD_NETWORK}/${pod_network}/" \
    openvpn.config.template > openvpn.config

if [[ ! -z "$node_network" ]]; then
  for n in $(echo $node_network |  sed 's/[][]//g' | sed 's/,/ /g')
  do
      echo "pull-filter ignore \"route-ipv6 ${node_network}\"" >> openvpn.config
  done
fi

echo "pull-filter accept \"route-ipv6 2001:db8:0:123::/64\"" >> openvpn.config
echo "pull-filter ignore \"route\"" >> openvpn.config
echo "pull-filter ignore redirect-gateway" >> openvpn.config
echo "pull-filter ignore route-ipv6" >> openvpn.config
echo "pull-filter ignore redirect-gateway-ipv6" >> openvpn.config

# enable forwarding and NAT
iptables --append FORWARD --in-interface tun0 -j ACCEPT
iptables --append POSTROUTING --out-interface eth0 --table nat -j MASQUERADE

while : ; do
    if [[ ! -z $ENDPOINT ]]; then
        openvpn --remote ${ENDPOINT} --port ${openvpn_port} --http-proxy ${ENDPOINT} ${openvpn_port} --http-proxy-option CUSTOM-HEADER Reversed-VPN "${reversed_vpn_header}" --config openvpn.config
    else
        log "No tunnel endpoint found"
    fi
    sleep 1
done
