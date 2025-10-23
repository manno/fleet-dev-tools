#!/bin/sh

if [ ! -f audit.yaml ]; then
  cat <<EOF > audit.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
- "RequestReceived"
rules:
# Don't log requests to a configmap called "controller-leader"
- level: None
  resources:
  - group: ""
    resources: ["configmaps"]
    resourceNames: ["controller-leader"]
# Don't log authenticated requests to certain non-resource URL paths.
- level: None
  userGroups: ["system:authenticated"]
  nonResourceURLs:
  - "/api*" # Wildcard matching.
  - "/version"
# Don't log deployments in kube-system
- level: None
  resources:
  - group: "apps"
    resources: ["deployments"]
  namespaces: ["kube-system"]
# Log metadata for fleet pods
- level: Metadata
  resources:
  - group: ""
    resources: ["pods"]
  namespaces: ["cattle-fleet-system"]
# Log configmap and secret changes in all other namespaces at the Metadata level.
- level: Metadata
  resources:
  - group: "" # core API group
    resources: ["secrets", "configmaps"]
# Log Rancher resources
- level: RequestResponse
  resources:
  - group: "management.cattle.io"
# Log Fleet resources
- level: RequestResponse
  resources:
  - group: "fleet.cattle.io"
# Don't log anything else
- level: None
EOF
fi

mkdir -p audit

name=${1-upstream}
offs=${2-0}
args=${k3d_args---network fleet}
unique_api_port=${unique_api_port-36443}
unique_tls_port=${unique_tls_port-443}

k3d cluster create "$name" \
  --servers 3 \
  --api-port "$unique_api_port" \
  -p "$(( 8080 + offs )):8080@server:0" \
  -p "$(( 8081 + offs )):8081@server:0" \
  -p "$(( 8082 + offs )):8082@server:0" \
  -p "$(( 4343 + offs )):4343@server:0" \
  -p "$unique_tls_port:443@server:0" \
  --k3s-arg '--tls-san=k3d-upstream-server-0@server:0' \
  --k3s-arg '--kube-apiserver-arg=audit-policy-file=/var/lib/rancher/k3s/server/manifests/audit.yaml@server:*' \
  --k3s-arg '--kube-apiserver-arg=audit-log-path=/var/log/kubernetes/audit/audit.log@server:*' \
  --volume "$(pwd)/audit.yaml:/var/lib/rancher/k3s/server/manifests/audit.yaml" \
  --volume "$(pwd)/audit:/var/log/kubernetes/audit" \
  $args

# k3d cluster create upstream --servers 1 --api-port 36443  -p '80:80@server:0' -p '443:443@server:0' \
#   --k3s-arg '--kube-apiserver-arg=audit-policy-file=/var/lib/rancher/k3s/server/manifests/audit.yaml@server:*' \
#   --k3s-arg '--kube-apiserver-arg=audit-log-path=/var/log/kubernetes/audit/audit.log@server:*' \
#   --volume "$(pwd)/audit.yaml:/var/lib/rancher/k3s/server/manifests/audit.yaml"
#
# kubectl config use-context k3d-upstream
#
# docker exec k3d-upstream-server-0 tail -f /var/log/kubernetes/audit/audit.log | tee redeploy.$$
