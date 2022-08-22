#!/bin/bash

VER=${1-v2.6.7}

echo "Rancher $VER"
wget https://github.com/rancher/rancher/releases/download/v2.6.6/rancher-images.txt -qO- | grep -E "fleet|gitjob|tekton-utils|/kubectl"
