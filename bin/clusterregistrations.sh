#!/bin/bash

ns=${ns:-fleet-default}
regspercluster=${regspercluster:-100}

k() {
  ns=$1
  id=$2
kubectl create -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: ClusterRegistration
metadata:
  generateName: request-
  generation: 1
  namespace: $ns
spec:
  clientID: "$id"
  clientRandom: "$RANDOM"
  clusterLabels:
    name: local
EOF
}
export -f k

for id in $(kubectl get clusters.fleet.cattle.io -n "$ns" -o="jsonpath={.items[*].spec.clientID}"); do
  seq 1 "$regspercluster" | xargs -n1 -P5 bash -c "k $ns $id"
done

# remove all clusters:
# kubectl get clusters.fleet.cattle.io -n $ns -o=name | grep -v local | xargs -P2 kubectl delete -n $ns
