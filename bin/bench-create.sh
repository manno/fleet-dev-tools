echo -n "start creating: "
date
time kubectl apply --wait -f gitrepo-lots.yaml
sleep 10
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-a
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-b
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-c
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-d
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-e
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-f
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-g
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-h
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-i
kubectl wait --for=condition=Ready=True --timeout=2m -n fleet-default gitrepo lots-j

# 10 repos on 10 clusters with 10 resources each
while [ $(kubectl -n fleet-default get gitrepo -o jsonpath='{range .items[*]}{.status.display.readyBundleDeployments}{"\n"}{end}' | grep '100/100' | wc -l) -ne 10 ]; do
  kubectl -n fleet-default get gitrepo -o jsonpath='{range .items[*]}{.status.display.readyBundleDeployments}{"\n"}{end}'
  sleep 1
done

echo -n "done creating: "
date

