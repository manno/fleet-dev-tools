#!/bin/bash

set -euxo pipefail

url="${url-172.18.0.1.omg.howdoi.website}"
cluster="${cluster-k3d-upstream}"

version="${1-}"
if [ -z "$version" ]; then
  version=$(curl -s https://api.github.com/repos/rancher/rancher/releases | jq -r "sort_by(.tag_name) | [ .[] | select(.draft | not) ] | .[-1].tag_name")
fi

# kubectl config use-context "$cluster"
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.4/cert-manager.yaml
kubectl wait --for=condition=Available deployment --timeout=2m -n cert-manager --all

# helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update rancher-latest

# set CATTLE_SERVER_URL and CATTLE_BOOTSTRAP_PASSWORD to get rancher out of "bootstrap" mode
helm upgrade rancher rancher-latest/rancher --version "$version" \
  --devel \
  --install --wait \
  --create-namespace \
  --namespace cattle-system \
  --set hostname="$url" \
  --set bootstrapPassword=admin \
  --set "extraEnv[0].name=CATTLE_SERVER_URL" \
  --set "extraEnv[0].value=https://$url" \
  --set "extraEnv[1].name=CATTLE_BOOTSTRAP_PASSWORD" \
  --set "extraEnv[1].value=rancherpassword"

# upgrade
# helm upgrade rancher rancher-latest/rancher --version v1.7.0 --devel --install --wait --set hostname="$url"

# wait for deployment of rancher
kubectl -n cattle-system rollout status deploy/rancher
# wait for rancher to create fleet namespace, deployment and controller
{ grep -q -m 1 "fleet"; kill $!; } < <(kubectl get deployments -n cattle-fleet-system -w)
kubectl -n cattle-fleet-system rollout status deploy/fleet-controller

helm list -A
