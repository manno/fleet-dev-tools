#!/bin/bash

export name="head"
export upstream_ctx="k3d-$name"
export public_hostname=rancher.manno.name
export password=$(cat ~/.rancherpassword)

export unique_api_port=6843
export unique_tls_port=8443
# cannot overlap with other installations
export downstream_start=3
export downstream_end=6
export downstream_prefix="$name"

run-parts --regex 'head' ../dev/rancher-demo

# ../dev/rancher-demo/10-k3d-primehead
# ../dev/rancher-demo/20-cert-manager-primehead
# ../dev/rancher-demo/30-rancher-head
# ../dev/rancher-demo/35-downstream-k3ds-primehead
# ../dev/rancher-demo/40-downstreams-primehead
# ../dev/rancher-demo/50-downstream-labels-primehead
