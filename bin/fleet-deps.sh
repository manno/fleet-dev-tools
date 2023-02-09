#!/bin/bash
set -x

grep wrangler go.mod
grep wrangler pkg/apis/go.mod
grep gitjob go.mod
grep appVersion charts/fleet/charts/gitjob/Chart.yaml
grep -1 gitjob charts/fleet/charts/gitjob/values.yaml
grep -1 tekton -1 charts/fleet/charts/gitjob/values.yaml
