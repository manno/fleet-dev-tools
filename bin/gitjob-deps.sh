#!/bin/bash
set -x
grep wrangler go.mod
grep -1 tekton chart/values.yaml
