#!/bin/bash

ns=${ns:-fleet-local}

# if no cluster has this clientID, a cluster will be created
id=${1:-rlbvttvhm4m8jvrflc66vtwjvwgnjpmf9c4dbpd9hcfv57jdm8p4r6}

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

# for id in $(kubectl get clusters.fleet.cattle.io -n fleet-default -o="jsonpath={.items[*].spec.clientID}"); do seq 1 100 | xargs -n1 -P5 ./apply-clusterregistration.sh $id; done
