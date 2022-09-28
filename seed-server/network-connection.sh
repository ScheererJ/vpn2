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

sed -e "s/\${SERVICE_NETWORK}/${service_network}/" \
    -e "s/\${POD_NETWORK}/${pod_network}/" \
    openvpn.config.template > openvpn.config

sed -e "s/\${SERVICE_NETWORK}/${service_network}/" \
    -e "s/\${POD_NETWORK}/${pod_network}/" \
    /client-config-dir/vpn-shoot-client.template > /client-config-dir/vpn-shoot-client

if [[ ! -z "$node_network" ]]; then
    for n in $(echo $node_network |  sed 's/[][]//g' | sed 's/,/ /g')
    do
        echo "route-ipv6 \"${node_network}\"" >> openvpn.config
        echo "iroute-ipv6 \"${node_network}\"" >> /client-config-dir/vpn-shoot-client
    done
fi

local_node_ip="${LOCAL_NODE_IP:-255.255.255.255}"

# filter log output to remove readiness/liveness probes from local node
openvpn --config openvpn.config | grep -v -E "TCP connection established with \[AF_INET\]${local_node_ip}|${local_node_ip}:[0-9]{1,5} Connection reset, restarting"
