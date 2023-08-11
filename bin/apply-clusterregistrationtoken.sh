kubectl apply -f - <<EOF
apiVersion: "fleet.cattle.io/v1alpha1"
kind: ClusterRegistrationToken
metadata:
  name: second-token
  namespace: fleet-local
spec:
  ttl: 12h
EOF

{ grep -q -m 1 "second-token"; kill $!; } < <(kubectl get secrets -n fleet-local -l "fleet.cattle.io/managed=true" -w)
