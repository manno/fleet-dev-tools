#!/bin/bash

#set -x

# Fleet Resource Monitor
# Continuously monitors Fleet resources to diagnose bundle deployment issues
# Outputs JSON for easy parsing and analysis
#
# Monitors:
# - Fleet controller pod (name, restarts, status, startTime) to detect restarts
# - GitRepos (generation, commit, forceSyncGeneration, conditions, observedGeneration)
# - Bundles (generation, commit from labels/status, forceSyncGeneration, conditions, finalizers, deletionTimestamp, observedGeneration, resourcesSHA256Sum)
# - BundleDeployments (generation, commit from labels, forceSyncGeneration, deploymentID, appliedDeploymentID, conditions, finalizers)
# - Bundle lifecycle secrets (fleet.cattle.io/bundle-values/v1alpha1 and fleet.cattle.io/bundle-deployment/v1alpha1)
#   with commit hashes from labels
# - Orphaned/stale secrets (deletion timestamps, missing owners)
# - API server consistency (detects "time travel" issues with resourceVersions)
# - Fleet events (recent events related to bundles and bundledeployments)
# - Stuck resources (generation mismatches, deletion timestamps, not ready conditions)
#
# Usage: ./monitor-fleet-resources.sh [interval_seconds]
# Example: ./monitor-fleet-resources.sh 5  # Check every 5 seconds

set -euo pipefail

# Configuration
INTERVAL=${1:-5}  # Check interval in seconds (default: 5)
NAMESPACE=${FLEET_NAMESPACE:-cattle-fleet-system}
OUTPUT_FORMAT="json"

# Colors for terminal output (optional)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

# Function to get controller pod info
get_controller_info() {
    local pod_name=$(kubectl get pods -n "$NAMESPACE" -l app=fleet-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    local pod_restarts=$(kubectl get pods -n "$NAMESPACE" -l app=fleet-controller -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    local pod_status=$(kubectl get pods -n "$NAMESPACE" -l app=fleet-controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    local pod_start_time=$(kubectl get pods -n "$NAMESPACE" -l app=fleet-controller -o jsonpath='{.items[0].status.startTime}' 2>/dev/null || echo "")

    jq -n \
        --arg name "$pod_name" \
        --arg restarts "$pod_restarts" \
        --arg status "$pod_status" \
        --arg start_time "$pod_start_time" \
        '{
            name: $name,
            restarts: ($restarts | tonumber),
            status: $status,
            startTime: $start_time
        }'
}

# Function to get GitRepo information
get_gitrepos() {
    local gitrepos=$(kubectl get gitrepos -A -o json 2>/dev/null || echo '{"items":[]}')

    echo "$gitrepos" | jq -c '[.items[] | {
        namespace: .metadata.namespace,
        name: .metadata.name,
        generation: .metadata.generation,
        resourceVersion: .metadata.resourceVersion,
        deletionTimestamp: .metadata.deletionTimestamp,
        finalizers: .metadata.finalizers,
        forceSyncGeneration: .spec.forceSyncGeneration,
        commit: .status.commit,
        readyClusters: .status.readyClusters,
        desiredReadyClusters: .status.desiredReadyClusters,
        observedGeneration: .status.observedGeneration,
        conditions: [.status.conditions[]? | {
            type: .type,
            status: .status,
            reason: .reason,
            message: .message,
            lastUpdateTime: .lastUpdateTime
        }],
        display: .status.display,
        summary: .status.summary
    }]'
}

# Function to get Bundle information
get_bundles() {
    local bundles=$(kubectl get bundles -A -o json 2>/dev/null || echo '{"items":[]}')

    echo "$bundles" | jq -c '[.items[] | {
        namespace: .metadata.namespace,
        name: .metadata.name,
        uid: .metadata.uid,
        generation: .metadata.generation,
        resourceVersion: .metadata.resourceVersion,
        creationTimestamp: .metadata.creationTimestamp,
        deletionTimestamp: .metadata.deletionTimestamp,
        finalizers: .metadata.finalizers,
        labels: .metadata.labels,
        commit: (.metadata.labels["fleet.cattle.io/commit"] // .status.commit),
        forceSyncGeneration: .spec.forceSyncGeneration,
        observedGeneration: .status.observedGeneration,
        conditions: [.status.conditions[]? | {
            type: .type,
            status: .status,
            reason: .reason,
            message: .message,
            lastUpdateTime: .lastUpdateTime
        }],
        summary: .status.summary,
        display: .status.display,
        resourcesSHA256Sum: .status.resourcesSHA256Sum,
        targetCustomizations: .spec.targetCustomizations,
        resourceErrors: [.status.resourceErrors[]?]
    }]'
}

# Function to get BundleDeployment information
get_bundledeployments() {
    local bds=$(kubectl get bundledeployments -A -o json 2>/dev/null || echo '{"items":[]}')

    echo "$bds" | jq -c '[.items[] | {
        namespace: .metadata.namespace,
        name: .metadata.name,
        uid: .metadata.uid,
        generation: .metadata.generation,
        resourceVersion: .metadata.resourceVersion,
        creationTimestamp: .metadata.creationTimestamp,
        deletionTimestamp: .metadata.deletionTimestamp,
        finalizers: .metadata.finalizers,
        labels: .metadata.labels,
        commit: .metadata.labels["fleet.cattle.io/commit"],
        deploymentID: .spec.deploymentID,
        stagedDeploymentID: .spec.stagedDeploymentID,
        contentName: ((.spec.deploymentID // "") | split(":")[0]),
        stagedContentName: ((.spec.stagedDeploymentID // "") | split(":")[0]),
        forceSyncGeneration: .spec.forceSyncGeneration,
        observedGeneration: .status.observedGeneration,
        conditions: [.status.conditions[]? | {
            type: .type,
            status: .status,
            reason: .reason,
            message: .message,
            lastUpdateTime: .lastUpdateTime
        }],
        ready: .status.ready,
        nonReadyStatus: [.status.nonReadyStatus[]?],
        modifiedStatus: [.status.modifiedStatus[]?],
        display: .status.display,
        appliedDeploymentID: .status.appliedDeploymentID,
        appliedContentName: ((.status.appliedDeploymentID // "") | split(":")[0]),
        release: .status.release
    }]'
}

# Function to get Content resources
get_contents() {
    local contents=$(kubectl get contents -A -o json 2>/dev/null || echo '{"items":[]}')

    echo "$contents" | jq -c '[.items[] | {
        name: .metadata.name,
        resourceVersion: .metadata.resourceVersion,
        creationTimestamp: .metadata.creationTimestamp,
        deletionTimestamp: .metadata.deletionTimestamp,
        finalizers: .metadata.finalizers,
        sha256sum: .metadata.name
    }]'
}

# Function to detect missing or problematic content resources
check_content_issues() {
    # Get all bundledeployments
    local all_bds=$(kubectl get bundledeployments -A -o json 2>/dev/null || echo '{"items":[]}')

    # Get all contents
    local all_contents=$(kubectl get contents -A -o json 2>/dev/null || echo '{"items":[]}')

    # Combine and process using stdin to avoid argument length limits
    jq -sc '
        .[0] as $contents_data |
        .[1] as $bds_data |
        # Create content map
        ($contents_data.items | map({key: .metadata.name, value: {deletionTimestamp: .metadata.deletionTimestamp, finalizers: .metadata.finalizers, resourceVersion: .metadata.resourceVersion}}) | from_entries) as $contents |
        # Process bundledeployments
        $bds_data.items | map(
            (.spec.deploymentID // "" | split(":")[0]) as $contentName |
            (.spec.stagedDeploymentID // "" | split(":")[0]) as $stagedContentName |
            (.status.appliedDeploymentID // "" | split(":")[0]) as $appliedContentName |
            {
                namespace: .metadata.namespace,
                name: .metadata.name,
                contentName: $contentName,
                stagedContentName: $stagedContentName,
                appliedContentName: $appliedContentName,
                contentExists: ($contents[$contentName] != null),
                contentDeletionTimestamp: ($contents[$contentName].deletionTimestamp // null),
                contentFinalizers: ($contents[$contentName].finalizers // []),
                stagedContentExists: (if $stagedContentName != "" and $stagedContentName != $contentName then ($contents[$stagedContentName] != null) else null end),
                appliedContentExists: (if $appliedContentName != "" and $appliedContentName != $contentName then ($contents[$appliedContentName] != null) else null end),
                issues: [
                    (if $contentName != "" and ($contents[$contentName] == null) then "content_not_found" else empty end),
                    (if $contentName != "" and ($contents[$contentName].deletionTimestamp != null) then "content_has_deletion_timestamp" else empty end),
                    (if $stagedContentName != "" and $stagedContentName != $contentName and ($contents[$stagedContentName] == null) then "staged_content_not_found" else empty end),
                    (if $appliedContentName != "" and $appliedContentName != $contentName and ($contents[$appliedContentName] == null) then "applied_content_not_found" else empty end)
                ]
            } | select(.issues | length > 0)
        )
    ' <(echo "$all_contents") <(echo "$all_bds")
}

# Function to get bundle lifecycle secrets (values and deployment)
get_bundle_secrets() {
    # Get bundle-values secrets
    local values_secrets=$(kubectl get secrets -A --field-selector type=fleet.cattle.io/bundle-values/v1alpha1 -o json 2>/dev/null || echo '{"items":[]}')

    # Get bundle-deployment secrets
    local deployment_secrets=$(kubectl get secrets -A --field-selector type=fleet.cattle.io/bundle-deployment/v1alpha1 -o json 2>/dev/null || echo '{"items":[]}')

    # Combine both types
    echo "$values_secrets" "$deployment_secrets" | jq -sc '
        (.[0].items // []) + (.[1].items // []) | map({
            namespace: .metadata.namespace,
            name: .metadata.name,
            resourceVersion: .metadata.resourceVersion,
            creationTimestamp: .metadata.creationTimestamp,
            deletionTimestamp: .metadata.deletionTimestamp,
            finalizers: .metadata.finalizers,
            labels: .metadata.labels,
            commit: .metadata.labels["fleet.cattle.io/commit"],
            type: .type,
            dataKeys: (.data | keys),
            ownerReferences: .metadata.ownerReferences
        })'
}

# Function to check for orphaned/stale secrets
get_orphaned_secrets() {
    # Get bundle-values secrets
    local values_secrets=$(kubectl get secrets -A --field-selector type=fleet.cattle.io/bundle-values/v1alpha1 -o json 2>/dev/null || echo '{"items":[]}')

    # Get bundle-deployment secrets
    local deployment_secrets=$(kubectl get secrets -A --field-selector type=fleet.cattle.io/bundle-deployment/v1alpha1 -o json 2>/dev/null || echo '{"items":[]}')

    # Get all bundles
    local all_bundles=$(kubectl get bundles -A -o json 2>/dev/null || echo '{"items":[]}')

    # Get all bundledeployments
    local all_bds=$(kubectl get bundledeployments -A -o json 2>/dev/null || echo '{"items":[]}')

    # Combine and process using stdin to avoid argument length limits
    jq -sc '
        .[0] as $values_data |
        .[1] as $deployment_data |
        .[2] as $bundles_data |
        .[3] as $bds_data |
        # Create UID maps
        ($bundles_data.items | map({key: (.metadata.namespace + "/" + .metadata.name), value: .metadata.uid}) | from_entries) as $bundles |
        ($bds_data.items | map({key: (.metadata.namespace + "/" + .metadata.name), value: .metadata.uid}) | from_entries) as $bds |
        # Process secrets
        (($values_data.items // []) + ($deployment_data.items // [])) | map(
            .metadata.ownerReferences[0] as $owner |
            (
                if .type == "fleet.cattle.io/bundle-values/v1alpha1" then
                    ($bundles[.metadata.namespace + "/" + $owner.name] // null)
                else
                    ($bds[.metadata.namespace + "/" + $owner.name] // null)
                end
            ) as $expectedUID |
            select(
                .metadata.deletionTimestamp != null or
                $owner == null or
                $expectedUID == null or
                $owner.uid != $expectedUID
            ) | {
                namespace: .metadata.namespace,
                name: .metadata.name,
                type: .type,
                deletionTimestamp: .metadata.deletionTimestamp,
                finalizers: .metadata.finalizers,
                resourceVersion: .metadata.resourceVersion,
                labels: .metadata.labels,
                ownerReferences: .metadata.ownerReferences,
                ownerKind: $owner.kind,
                ownerName: $owner.name,
                ownerUID: $owner.uid,
                expectedUID: $expectedUID,
                reason: (
                    if .metadata.deletionTimestamp != null then "has_deletion_timestamp"
                    elif $owner == null then "no_owner_reference"
                    elif $expectedUID == null then "owner_not_found"
                    elif $owner.uid != $expectedUID then "owner_uid_mismatch"
                    else "unknown"
                    end
                )
            }
        )
    ' <(echo "$values_secrets") <(echo "$deployment_secrets") <(echo "$all_bundles") <(echo "$all_bds")
}

# Function to check API server consistency
check_api_consistency() {
    # Make multiple requests to the same resource and check if we get different versions
    local test_resource="bundles"
    local namespace="fleet-local"

    # Get the resource 3 times in quick succession
    local v1=$(kubectl get "$test_resource" -n "$namespace" -o json 2>/dev/null | jq -r '.metadata.resourceVersion // "unknown"')
    sleep 0.1
    local v2=$(kubectl get "$test_resource" -n "$namespace" -o json 2>/dev/null | jq -r '.metadata.resourceVersion // "unknown"')
    sleep 0.1
    local v3=$(kubectl get "$test_resource" -n "$namespace" -o json 2>/dev/null | jq -r '.metadata.resourceVersion // "unknown"')

    # Check if all versions are the same
    local consistent="true"
    if [ "$v1" != "$v2" ] || [ "$v2" != "$v3" ]; then
        consistent="false"
    fi

    jq -n \
        --arg v1 "$v1" \
        --arg v2 "$v2" \
        --arg v3 "$v3" \
        --arg consistent "$consistent" \
        '{
            consistent: ($consistent == "true"),
            versions: [$v1, $v2, $v3]
        }'
}

# Function to get events related to fleet resources
get_fleet_events() {
    # Get recent events related to bundles and bundledeployments
    local events=$(kubectl get events -A --field-selector involvedObject.apiVersion=fleet.cattle.io/v1alpha1 \
        --sort-by='.lastTimestamp' -o json 2>/dev/null || echo '{"items":[]}')

    echo "$events" | jq -c '[.items[] | {
        namespace: .metadata.namespace,
        type: .type,
        reason: .reason,
        message: .message,
        involvedObject: {
            kind: .involvedObject.kind,
            name: .involvedObject.name,
            namespace: .involvedObject.namespace
        },
        count: .count,
        firstTimestamp: .firstTimestamp,
        lastTimestamp: .lastTimestamp
    }] | .[-20:]'
}

# Function to detect stuck bundles
detect_stuck_bundles() {
    local bundles=$(kubectl get bundles -A -o json 2>/dev/null || echo '{"items":[]}')

    echo "$bundles" | jq -c '[.items[] |
        select(
            (.status.conditions[]? | select(.type == "Ready" and .status != "True")) or
            (.metadata.deletionTimestamp != null) or
            (.status.observedGeneration != .metadata.generation)
        ) | {
            namespace: .metadata.namespace,
            name: .metadata.name,
            generation: .metadata.generation,
            observedGeneration: .status.observedGeneration,
            deletionTimestamp: .metadata.deletionTimestamp,
            age: .metadata.creationTimestamp,
            readyCondition: (.status.conditions[]? | select(.type == "Ready")),
            reasons: [
                (if .metadata.deletionTimestamp != null then "deletion_timestamp_set" else empty end),
                (if .status.observedGeneration != .metadata.generation then "generation_mismatch" else empty end),
                (if (.status.conditions[]? | select(.type == "Ready" and .status != "True")) then "not_ready" else empty end)
            ]
        }
    ]'
}

# Function to detect stuck bundledeployments
detect_stuck_bundledeployments() {
    local bds=$(kubectl get bundledeployments -A -o json 2>/dev/null || echo '{"items":[]}')

    echo "$bds" | jq -c '[.items[] |
        select(
            (.status.conditions[]? | select(.type == "Ready" and .status != "True")) or
            (.metadata.deletionTimestamp != null) or
            (.status.observedGeneration != .metadata.generation) or
            (.spec.deploymentID != .status.appliedDeploymentID)
        ) | {
            namespace: .metadata.namespace,
            name: .metadata.name,
            generation: .metadata.generation,
            observedGeneration: .status.observedGeneration,
            deploymentID: .spec.deploymentID,
            appliedDeploymentID: .status.appliedDeploymentID,
            deletionTimestamp: .metadata.deletionTimestamp,
            age: .metadata.creationTimestamp,
            readyCondition: (.status.conditions[]? | select(.type == "Ready")),
            reasons: [
                (if .metadata.deletionTimestamp != null then "deletion_timestamp_set" else empty end),
                (if .status.observedGeneration != .metadata.generation then "generation_mismatch" else empty end),
                (if .spec.deploymentID != .status.appliedDeploymentID then "deployment_id_mismatch" else empty end),
                (if (.status.conditions[]? | select(.type == "Ready" and .status != "True")) then "not_ready" else empty end)
            ]
        }
    ]'
}

# Function to detect inconsistencies between GitRepos and Bundles
detect_gitrepo_bundle_inconsistencies() {
    local gitrepos=$(kubectl get gitrepos -A -o json 2>/dev/null || echo '{"items":[]}')
    local bundles=$(kubectl get bundles -A -o json 2>/dev/null || echo '{"items":[]}')

    jq -sc '
        .[0] as $gitrepos_data |
        .[1] as $bundles_data |
        # Create GitRepo map by repo name
        ($gitrepos_data.items | map({
            key: (.metadata.namespace + "/" + .metadata.name),
            value: {
                commit: .status.commit,
                forceSyncGeneration: .spec.forceSyncGeneration,
                generation: .metadata.generation
            }
        }) | from_entries) as $gitrepos |
        # Check bundles against their gitrepos
        $bundles_data.items | map(
            select(.metadata.labels["fleet.cattle.io/repo-name"] != null) |
            .metadata.labels["fleet.cattle.io/repo-name"] as $repoName |
            ($gitrepos[.metadata.namespace + "/" + $repoName] // null) as $gitrepo |
            select(
                $gitrepo != null and (
                    (.metadata.labels["fleet.cattle.io/commit"] != $gitrepo.commit) or
                    (.spec.forceSyncGeneration != $gitrepo.forceSyncGeneration)
                )
            ) | {
                namespace: .metadata.namespace,
                name: .metadata.name,
                repoName: $repoName,
                bundleCommit: (.metadata.labels["fleet.cattle.io/commit"] // "none"),
                gitrepoCommit: ($gitrepo.commit // "none"),
                commitMismatch: (.metadata.labels["fleet.cattle.io/commit"] != $gitrepo.commit),
                bundleForceSyncGen: .spec.forceSyncGeneration,
                gitrepoForceSyncGen: $gitrepo.forceSyncGeneration,
                forceSyncGenMismatch: (.spec.forceSyncGeneration != $gitrepo.forceSyncGeneration),
                issues: [
                    (if .metadata.labels["fleet.cattle.io/commit"] != $gitrepo.commit then "commit_mismatch" else empty end),
                    (if .spec.forceSyncGeneration != $gitrepo.forceSyncGeneration then "force_sync_gen_mismatch" else empty end)
                ]
            }
        )
    ' <(echo "$gitrepos") <(echo "$bundles")
}

# Function to validate ownerReferences on secrets
validate_secret_owners() {
    # Get bundle-values secrets
    local values_secrets=$(kubectl get secrets -A --field-selector type=fleet.cattle.io/bundle-values/v1alpha1 -o json 2>/dev/null || echo '{"items":[]}')

    # Get bundle-deployment secrets
    local deployment_secrets=$(kubectl get secrets -A --field-selector type=fleet.cattle.io/bundle-deployment/v1alpha1 -o json 2>/dev/null || echo '{"items":[]}')

    # Get all bundles and bundledeployments
    local all_bundles=$(kubectl get bundles -A -o json 2>/dev/null || echo '{"items":[]}')
    local all_bds=$(kubectl get bundledeployments -A -o json 2>/dev/null || echo '{"items":[]}')

    # Combine and process using stdin to avoid argument length limits
    jq -sc '
        .[0] as $values_data |
        .[1] as $deployment_data |
        .[2] as $bundles_data |
        .[3] as $bds_data |
        # Create UID maps
        ($bundles_data.items | map({key: (.metadata.namespace + "/" + .metadata.name), value: .metadata.uid}) | from_entries) as $bundles |
        ($bds_data.items | map({key: (.metadata.namespace + "/" + .metadata.name), value: .metadata.uid}) | from_entries) as $bds |
        # Process secrets
        (($values_data.items // []) + ($deployment_data.items // [])) | map(
            select(.metadata.ownerReferences != null and (.metadata.ownerReferences | length) > 0) |
            .metadata.ownerReferences[0] as $owner |
            {
                namespace: .metadata.namespace,
                name: .metadata.name,
                type: .type,
                ownerKind: $owner.kind,
                ownerName: $owner.name,
                ownerUID: $owner.uid,
                expectedUID: (
                    if $owner.kind == "Bundle" then
                        $bundles[.metadata.namespace + "/" + $owner.name]
                    elif $owner.kind == "BundleDeployment" then
                        $bds[.metadata.namespace + "/" + $owner.name]
                    else
                        null
                    end
                ),
                valid: (
                    if $owner.kind == "Bundle" then
                        ($bundles[.metadata.namespace + "/" + $owner.name] == $owner.uid)
                    elif $owner.kind == "BundleDeployment" then
                        ($bds[.metadata.namespace + "/" + $owner.name] == $owner.uid)
                    else
                        false
                    end
                ),
                issue: (
                    if $owner.kind == "Bundle" and ($bundles[.metadata.namespace + "/" + $owner.name] == null) then
                        "owner_not_found"
                    elif $owner.kind == "BundleDeployment" and ($bds[.metadata.namespace + "/" + $owner.name] == null) then
                        "owner_not_found"
                    elif $owner.kind == "Bundle" and ($bundles[.metadata.namespace + "/" + $owner.name] != $owner.uid) then
                        "uid_mismatch"
                    elif $owner.kind == "BundleDeployment" and ($bds[.metadata.namespace + "/" + $owner.name] != $owner.uid) then
                        "uid_mismatch"
                    else
                        null
                    end
                )
            }
        ) | map(select(.valid == false))
    ' <(echo "$values_secrets") <(echo "$deployment_secrets") <(echo "$all_bundles") <(echo "$all_bds")
}

# Main monitoring function
monitor_fleet() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log_info "Collecting Fleet resource data at $timestamp"

    # Collect all data
    local controller_info=$(get_controller_info)
    local gitrepos=$(get_gitrepos)
    local bundles=$(get_bundles)
    local bundledeployments=$(get_bundledeployments)
    local contents=$(get_contents)
    local bundle_secrets=$(get_bundle_secrets)
    local orphaned_secrets=$(get_orphaned_secrets)
    local content_issues=$(check_content_issues)
    local api_consistency=$(check_api_consistency)
    local fleet_events=$(get_fleet_events)
    local stuck_bundles=$(detect_stuck_bundles)
    local stuck_bundledeployments=$(detect_stuck_bundledeployments)
    local gitrepo_bundle_inconsistencies=$(detect_gitrepo_bundle_inconsistencies)
    local invalid_secret_owners=$(validate_secret_owners)

    # Validate JSON before combining
    echo "$controller_info" | jq . >/dev/null 2>&1 || controller_info='{}'
    echo "$gitrepos" | jq . >/dev/null 2>&1 || gitrepos='[]'
    echo "$bundles" | jq . >/dev/null 2>&1 || bundles='[]'
    echo "$bundledeployments" | jq . >/dev/null 2>&1 || bundledeployments='[]'
    echo "$contents" | jq . >/dev/null 2>&1 || contents='[]'
    echo "$bundle_secrets" | jq . >/dev/null 2>&1 || bundle_secrets='[]'
    echo "$orphaned_secrets" | jq . >/dev/null 2>&1 || orphaned_secrets='[]'
    echo "$content_issues" | jq . >/dev/null 2>&1 || content_issues='[]'
    echo "$api_consistency" | jq . >/dev/null 2>&1 || api_consistency='{}'
    echo "$fleet_events" | jq . >/dev/null 2>&1 || fleet_events='[]'
    echo "$stuck_bundles" | jq . >/dev/null 2>&1 || stuck_bundles='[]'
    echo "$stuck_bundledeployments" | jq . >/dev/null 2>&1 || stuck_bundledeployments='[]'
    echo "$gitrepo_bundle_inconsistencies" | jq . >/dev/null 2>&1 || gitrepo_bundle_inconsistencies='[]'
    echo "$invalid_secret_owners" | jq . >/dev/null 2>&1 || invalid_secret_owners='[]'

    # Combine into single JSON output
    jq -n \
        --arg timestamp "$timestamp" \
        --argjson controller "$controller_info" \
        --argjson gitrepos "$gitrepos" \
        --argjson bundles "$bundles" \
        --argjson bundledeployments "$bundledeployments" \
        --argjson contents "$contents" \
        --argjson secrets "$bundle_secrets" \
        --argjson orphaned "$orphaned_secrets" \
        --argjson content_issues "$content_issues" \
        --argjson api "$api_consistency" \
        --argjson events "$fleet_events" \
        --argjson stuck_bundles "$stuck_bundles" \
        --argjson stuck_bds "$stuck_bundledeployments" \
        --argjson gitrepo_inconsistencies "$gitrepo_bundle_inconsistencies" \
        --argjson invalid_owners "$invalid_secret_owners" \
        '{
            timestamp: $timestamp,
            controller: $controller,
            gitrepos: $gitrepos,
            bundles: $bundles,
            bundledeployments: $bundledeployments,
            contents: $contents,
            bundleSecrets: $secrets,
            orphanedSecrets: $orphaned,
            contentIssues: $content_issues,
            apiConsistency: $api,
            recentEvents: $events,
            diagnostics: {
                stuckBundles: $stuck_bundles,
                stuckBundleDeployments: $stuck_bds,
                gitrepoBundleInconsistencies: $gitrepo_inconsistencies,
                invalidSecretOwners: $invalid_owners,
                contentIssues: $content_issues,
                orphanedSecretsCount: ($orphaned | length),
                invalidSecretOwnersCount: ($invalid_owners | length),
                contentIssuesCount: ($content_issues | length),
                gitrepoBundleInconsistenciesCount: ($gitrepo_inconsistencies | length),
                bundlesWithDeletionTimestamp: ($bundles | map(select(.deletionTimestamp != null)) | length),
                bundleDeploymentsWithDeletionTimestamp: ($bundledeployments | map(select(.deletionTimestamp != null)) | length),
                contentsWithDeletionTimestamp: ($contents | map(select(.deletionTimestamp != null)) | length)
            }
        }'
}

# Main loop
main() {
    log_info "Fleet Resource Monitor started"
    log_info "Monitoring interval: ${INTERVAL}s"
    log_info "Fleet namespace: ${NAMESPACE}"
    log_info "Press Ctrl+C to stop"
    echo ""

    while true; do
        monitor_fleet
        sleep "$INTERVAL"
    done
}

# Handle interrupts gracefully
trap 'log_info "Stopping Fleet Resource Monitor"; exit 0' INT TERM

main
