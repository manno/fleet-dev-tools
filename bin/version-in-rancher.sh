#!/bin/bash

VER=${1-v2.7.9}

if ! echo "$VER" | grep "^v"; then
  VER="v$VER"
fi

echo "Query Fleet images in Rancher $VER (images.txt):"
wget https://github.com/rancher/rancher/releases/download/"$VER"/rancher-images.txt -qO- | grep -E "fleet|gitjob|tekton-utils|/kubectl"
# url?
#wget https://github.com/rancher/rancher/raw/"$VER"/package/Dockerfile -qO- | grep CATTLE_FLEET_MIN_VERSION


echo "Query Rancher $VER (Dockerfile):"
wget https://raw.githubusercontent.com/rancher/rancher/"$VER"/package/Dockerfile -qO- | grep -E "FLEET|ARG CHART_DEFAULT_BRANCH"
wget https://raw.githubusercontent.com/rancher/rancher/"$VER"/build.yaml -qO- | grep -E "fleet|FLEET"
