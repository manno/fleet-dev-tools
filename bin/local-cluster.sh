# Description: setup local cluster like rancher if bootstrap.enabled is false

set -euxo pipefail

if [ ! -d ./charts/fleet ]; then
  echo "please change the current directory to the fleet repo checkout"
  exit 1
fi

# fetching from local kubeconfig
host=$( docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3d-upstream-server-0 )
ca=$( kubectl config view --flatten -o jsonpath='{.clusters[?(@.name == "k3d-upstream")].cluster.certificate-authority-data}' )
client_cert=$( kubectl config view --flatten -o jsonpath='{.users[?(@.name == "admin@k3d-upstream")].user.client-certificate-data}' )
token=$( kubectl config view --flatten -o jsonpath='{.users[?(@.name == "admin@k3d-upstream")].user.client-key-data}' )
server="https://$host:6443"

value=$(cat <<EOF
apiVersion: v1
kind: Config
current-context: default
clusters:
- cluster:
    certificate-authority-data: $ca
    server: $server
  name: cluster
contexts:
- context:
    cluster: cluster
    user: user
  name: default
preferences: {}
users:
- name: user
  user:
    client-certificate-data: $client_cert
    client-key-data: $token
EOF
)

kubectl create ns fleet-local || true
kubectl delete secret -n fleet-local kbcfg-local || true
kubectl create secret generic -n fleet-local kbcfg-local --from-literal=token="$token" --from-literal=value="$value"

kubectl apply -n fleet-local -f - <<EOF
apiVersion: "fleet.cattle.io/v1alpha1"
kind: Cluster
metadata:
  name: local
  labels:
    name: local
spec:
  kubeConfigSecret: kbcfg-local
EOF
