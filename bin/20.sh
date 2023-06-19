#!/bin/bash
# Description: setup 20 fleet downstreams
#

k3d cluster create upstream --servers 3 --api-port 6443 -p '80:80@server:0' -p '443:443@server:0' --network fleet
kubectl config use-context k3d-upstream

helm -n cattle-fleet-system upgrade --install --create-namespace fleet-crd "https://github.com/rancher/fleet/releases/download/v0.7.0-rc.4/fleet-crd-0.7.0-rc.4.tgz"
host=$( docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3d-upstream-server-0 )
ca=$( kubectl config view --flatten -o jsonpath='{.clusters[?(@.name == "k3d-upstream")].cluster.certificate-authority-data}' | base64 -d )
server="https://$host:6443"
helm -n cattle-fleet-system upgrade --install \
  --set apiServerCA="$ca" \
  --set apiServerURL="$server" \
  --set debug=true --set debugLevel=99 \
  fleet "https://github.com/rancher/fleet/releases/download/v0.7.0-rc.4/fleet-0.7.0-rc.4.tgz"

{ grep -E -q -m 1 "fleet-agent-local.*1/1"; kill $!; } < <(kubectl get bundles -n fleet-local -w)

# network needs to be created first
# only 50 k3ds per network?
seq 1 10 | xargs -I{} -n1 -P6 ../dev/20-k3d "perf{}" "{}" fleet #"k3d-perfnet1"

kubectl config use-context k3d-upstream
# multiple networks -> expose ports on host 10.4.4.40:$((36443 + i))
seq 1 10 | xargs -I{} -n1 -P6 ../dev/20-managed-clusters "perf{}" 36443 {}

seq 2 4 | xargs -I{} -n1 kubectl patch clusters.fleet.cattle.io -n "fleet-default" "perf{}" --type=json -p '[{"op": "add", "path": "/metadata/labels/env", "value": "dev" }]'
seq 5 7 | xargs -I{} -n1 kubectl patch clusters.fleet.cattle.io -n "fleet-default" "perf{}" --type=json -p '[{"op": "add", "path": "/metadata/labels/env", "value": "test" }]'
seq 8 10 | xargs -I{} -n1 kubectl patch clusters.fleet.cattle.io -n "fleet-default" "perf{}" --type=json -p '[{"op": "add", "path": "/metadata/labels/env", "value": "prod" }]'

# cleanup() {
#   k3d cluster delete --all
#   seq 1 10 | xargs -I{} -n1 -P6 k3d cluster delete "perf{}"
# }
