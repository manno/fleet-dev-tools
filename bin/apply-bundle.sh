kubectl apply -f - <<EOF
apiVersion: "fleet.cattle.io/v1alpha1"
kind: Bundle
metadata:
  name: cl$1
  namespace: fleet-local
EOF
