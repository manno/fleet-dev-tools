#!/bin/bash

ns=${1:-fleet-local}
name=${2:-local}
kubectl patch clusters.fleet.cattle.io -n "$ns" "$name" --type=json -p '[{"op": "add", "path": "/spec/redeployAgentGeneration", "value": '$RANDOM'}]'
