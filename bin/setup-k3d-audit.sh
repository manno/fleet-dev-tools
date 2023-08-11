#!/bin/sh

if [ ! -f audit.yaml ]; then
  cat <<EOF > audit.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
- "RequestReceived"
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["pods"]
  namespaces: ["cattle-fleet-system"]
- level: None
  resources:
  - group: "apps"
    resources: ["deployments"]
  namespaces: ["kube-system"]
- level: RequestResponse
  resources:
  - group: "apps"
    resources: ["deployments"]
- level: None
EOF
fi


k3d cluster create upstream --servers 1 --api-port 36443  -p '80:80@server:0' -p '443:443@server:0' \
  --k3s-arg '--kube-apiserver-arg=audit-policy-file=/var/lib/rancher/k3s/server/manifests/audit.yaml@server:*' \
  --k3s-arg '--kube-apiserver-arg=audit-log-path=/var/log/kubernetes/audit/audit.log@server:*' \
  --volume "$(pwd)/audit.yaml:/var/lib/rancher/k3s/server/manifests/audit.yaml"

kubectl config use-context k3d-upstream

# docker exec k3d-upstream-server-0 tail -f /var/log/kubernetes/audit/audit.log | tee redeploy.$$
