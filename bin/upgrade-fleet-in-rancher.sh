

url_crd="https://github.com/rancher/fleet/releases/download/v0.4.1/fleet-crd-0.4.1.tgz"
helm upgrade fleet-crd "$url_crd" --wait -n cattle-fleet-system

url="https://github.com/rancher/fleet/releases/download/v0.4.1/fleet-0.4.1.tgz"
version="v0.4.1"
helm upgrade fleet "$url" \
  --wait -n cattle-fleet-system \
  --set image.tag="$version" \
  --set agentImage.tag="$version" \
  --reuse-values
