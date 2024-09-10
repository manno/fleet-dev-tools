echo -n "start deleting: "
date

time kubectl delete --wait -n fleet-default gitrepo lots-a lots-b lots-c lots-d lots-e lots-f lots-g lots-h lots-i lots-j
while [ $(kubectl -n fleet-default get clusters.fleet.cattle.io -o jsonpath='{range .items[*]}{.status.display.readyBundles}{"\n"}{end}' | grep '1/1' | wc -l) -ne 10 ]; do
  sleep 1
done

echo -n "done deleting: "
date
