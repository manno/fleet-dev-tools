#!/bin/bash
# Setup k3d with a bind mount
#dev/setup-k3ds

#
# export args="--network fleet --volume $HOME/co/fleet:/workspace"
# docker_mirror=${docker_mirror-}
# if [ -n "$docker_mirror" ]; then
#   TMP_CONFIG="$(mktemp)"
#   trap "rm -f $TMP_CONFIG" EXIT

#   cat << EOF > "$TMP_CONFIG"
# mirrors:
#   "docker.io":
#       endpoint:
#             - $docker_mirror
# EOF
#   args="$args --registry-config $TMP_CONFIG"
# fi

# k3d cluster create upstream --servers 1 --api-port 36443 -p '80:80@server:0' -p '443:443@server:0' $args
# k3d cluster create downstream --servers 1 --api-port 36444 -p '5080:80@server:0' -p '3444:443@server:0' $args
# kubectl config use-context k3d-upstream

# After building the devcontainer in vscode, note the image name from "docker ps"
k3d image import vsc-fleet-407a925de0f33438083c8d1880a1de009517c4281d6ec9ecaba4d575adc4e878-features -c upstream

# ...
#./dev/setup-fleet


# After installing fleet
kubectl apply -f devcontainer-k8s.yaml

# use vscode kubernetes extension to open a new vscode window by attaching to the pod

# Store it to a file:
#   docker save vsc-fleet-407a925de0f33438083c8d1880a1de009517c4281d6ec9ecaba4d575adc4e878-features > devcontainer-k8s.img.tar
# Can be loaded after image reset:
#   docker load -i ./devcontainer-k8s.img.tar
# Or directly  imported into k3d:
#   k3d image import ./devcontainer-k8s.img.tar -c upstream

