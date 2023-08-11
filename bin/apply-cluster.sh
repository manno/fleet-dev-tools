kubectl apply -v 9 -f - <<EOF
apiVersion: "fleet.cattle.io/v1alpha1"
kind: Cluster
metadata:
  name: cl$1
  namespace: fleet-local
  labels:
    env: test
    more:
spec:
  clientID: "fake-random"
EOF
