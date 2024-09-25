#!/bin/bash
ns=fleet-local

echo -n "start creating: "
date
time kubectl apply -n "$ns" --wait -f gitrepo-lots.yaml
sleep 10
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-a
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-b
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-c
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-d
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-e
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-f
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-g
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-h
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-i
kubectl wait --for=condition=Ready=True --timeout=2m -n "$ns" gitrepo lots-j

# 10 repos on 10 clusters with 10 resources each
while [ $(kubectl -n "$ns" get gitrepo -o jsonpath='{range .items[*]}{.status.display.readyBundleDeployments}{"\n"}{end}' | grep '10/10' | wc -l) -ne 10 ]; do
  kubectl -n "$ns" get gitrepo -o jsonpath='{range .items[*]}{.status.display.readyBundleDeployments}{"\n"}{end}'
  sleep 1
done

echo -n "done creating: "
date

