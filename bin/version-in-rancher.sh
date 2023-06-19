#!/bin/bash

VER=${1-v2.6.7}

if ! echo "$VER" | grep "^v"; then
  VER="v$VER"
fi

echo "Rancher $VER"
wget https://github.com/rancher/rancher/releases/download/"$VER"/rancher-images.txt -qO- | grep -E "fleet|gitjob|tekton-utils|/kubectl"
