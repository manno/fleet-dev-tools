# uses https://github.com/clamoriniere/crd-to-markdown
~/bin/crd-to-markdown \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/bundle_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/bundledeployment_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/bundlenamespacemapping_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/cluster_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/clustergroup_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/clusterregistration_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/clusterregistrationtoken_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/content_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/gitrepo_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/gitreporestriction_types.go" \
  -f "pkg/apis/fleet.cattle.io/v1alpha1/imagescan_types.go" \
  -n Bundle -n BundleDeployment -n GitRepo -n GitRepoRestriction -n BundleNamespaceMapping -n Content \
  -n Cluster -n ClusterRegistration -n ClusterRegistrationToken -n ClusterGroup -n ImageScan \
  | sed -e 's/\[\]\[/\\[\\]\[/' \
  | sed -e '1 s/### Custom Resources/# Custom Resources Spec/; t' -e '1,// s//# Custom Resources Spec/' \
  | sed -e '1 s/### Sub Resources/# Sub Resources/; t' -e '1,// s//# Sub Resources/' \
  | tail -n +2 \
  > ../docs/docs/ref-crds.md
