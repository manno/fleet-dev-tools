#!/bin/bash

export name="demo"
export upstream_ctx="k3d-demo"
export public_hostname=mm-local-rancher.ngrok.app
# export rancher_version=v2.8.3
export password=$(cat ~/.rancherpassword)

export unique_api_port=6443
export unique_tls_port=7443
# cannot overlap with other installations
export downstream_start=20
export downstream_end=29
export downstream_prefix=demo

run-parts --regex 'prime' ../dev/rancher-demo

# ../dev/rancher-demo/10-k3d-primehead
# ../dev/rancher-demo/20-cert-manager-primehead
# ../dev/rancher-demo/30-rancher-prime
# ../dev/rancher-demo/35-downstream-k3ds-primehead
#../dev/rancher-demo/40-downstreams-primehead
#../dev/rancher-demo/50-downstream-labels-primehead
