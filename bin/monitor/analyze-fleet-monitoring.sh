#!/bin/bash

# Fleet Monitoring Analysis Script
# Analyzes JSON output from monitor-fleet-resources.sh
# Can process single snapshots or multiple snapshots to detect changes over time
#
# Usage:
#   # Analyze single snapshot
#   cat monitoring-output.json | ./analyze-fleet-monitoring.sh
#
#   # Analyze from file
#   ./analyze-fleet-monitoring.sh monitoring-output.json
#
#   # Live analysis
#   ./monitor-fleet-resources.sh 5 | ./analyze-fleet-monitoring.sh --live
#
#   # Compare two snapshots
#   ./analyze-fleet-monitoring.sh --compare snapshot1.json snapshot2.json

set -euo pipefail

MODE="${1:-summary}"
INPUT_FILE="${2:-}"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Summary analysis - high-level overview
summary_analysis() {
    jq -r '
        "┌─────────────────────────────────────────────────────────────┐",
        "│ FLEET MONITORING SUMMARY - \(.timestamp)     │",
        "└─────────────────────────────────────────────────────────────┘",
        "",
        "CONTROLLER STATUS:",
        "  Pod: \(.controller.name)",
        "  Restarts: \(.controller.restarts)",
        "  Uptime: \(.controller.startTime)",
        "",
        "RESOURCE COUNTS:",
        "  GitRepos: \(.gitrepos | length)",
        "  Bundles: \(.bundles | length)",
        "  BundleDeployments: \(.bundledeployments | length)",
        "  Contents: \(.contents | length)",
        "  Bundle Secrets: \(.bundleSecrets | length)",
        "",
        "DIAGNOSTICS:",
        "  Stuck Bundles: \(.diagnostics.stuckBundles | length) \(if (.diagnostics.stuckBundles | length) > 0 then "⚠" else "✓" end)",
        "  Stuck BundleDeployments: \(.diagnostics.stuckBundleDeployments | length) \(if (.diagnostics.stuckBundleDeployments | length) > 0 then "⚠" else "✓" end)",
        "  GitRepo/Bundle Inconsistencies: \(.diagnostics.gitrepoBundleInconsistenciesCount) \(if .diagnostics.gitrepoBundleInconsistenciesCount > 0 then "⚠ STALE BUNDLES" else "✓" end)",
        "  Content Issues: \(.diagnostics.contentIssuesCount) \(if .diagnostics.contentIssuesCount > 0 then "⚠" else "✓" end)",
        "  Orphaned Secrets: \(.diagnostics.orphanedSecretsCount) \(if .diagnostics.orphanedSecretsCount > 0 then "⚠" else "✓" end)",
        "  Invalid Secret Owners: \(.diagnostics.invalidSecretOwnersCount) \(if .diagnostics.invalidSecretOwnersCount > 0 then "⚠" else "✓" end)",
        "  Bundles with Deletion Timestamp: \(.diagnostics.bundlesWithDeletionTimestamp) \(if .diagnostics.bundlesWithDeletionTimestamp > 0 then "⚠" else "✓" end)",
        "  BundleDeployments with Deletion Timestamp: \(.diagnostics.bundleDeploymentsWithDeletionTimestamp) \(if .diagnostics.bundleDeploymentsWithDeletionTimestamp > 0 then "⚠" else "✓" end)",
        "  Contents with Deletion Timestamp: \(.diagnostics.contentsWithDeletionTimestamp) \(if .diagnostics.contentsWithDeletionTimestamp > 0 then "⚠" else "✓" end)",
        "  API Consistency: \(if .apiConsistency.consistent then "✓ CONSISTENT" else "✗ INCONSISTENT - TIME TRAVEL DETECTED" end)",
        "",
        "GITREPOS:",
        (.gitrepos[] | "  \(.name): Commit: \((.commit // "none")[0:8]) | Gen: \(.generation)/\(.observedGeneration) | ForceSync: \(.forceSyncGeneration // "N/A") | Ready: \(if ((.conditions[] | select(.type == "Ready") | .status) // "Unknown") == "True" then "✓" else "✗" end)"),
        "",
        "BUNDLES:",
        (.bundles[] | "  \(.name): Commit: \(((.commit // "none")[0:8]) // "N/A") | UID: \(.uid[0:13]) | Gen: \(.generation)/\(.observedGeneration) | ForceSync: \(.forceSyncGeneration // "N/A") | Ready: \(if ((.conditions[] | select(.type == "Ready") | .status) // "Unknown") == "True" then "✓" else "✗" end) | DelTime: \(if .deletionTimestamp then "SET ⚠" else "none" end)"),
        "",
        "BUNDLEDEPLOYMENTS:",
        (.bundledeployments[] | "  \(.name): Commit: \(((.commit // "none")[0:8]) // "N/A") | UID: \(.uid[0:13]) | Content: \(.contentName[0:20])... | Gen: \(.generation)/\(.observedGeneration // "N/A") | ForceSync: \(.forceSyncGeneration // "N/A") | DepID Match: \(if .deploymentID == .appliedDeploymentID then "✓" else "✗ MISMATCH" end) | DelTime: \(if .deletionTimestamp then "SET ⚠" else "none" end)"),
        "",
        "CONTENTS:",
        (.contents[] | "  \(.name[0:30])...: Finalizers: \(.finalizers | length) | DelTime: \(if .deletionTimestamp then "SET ⚠" else "none" end)"),
        "",
        "BUNDLE SECRETS:",
        (.bundleSecrets[] | "  \(.name) (\(if .type == "fleet.cattle.io/bundle-values/v1alpha1" then "values" else "deployment" end)): Commit: \(((.commit // "none")[0:8]) // "N/A") | Owner: \(.ownerReferences[0].kind)/\(.ownerReferences[0].name) | OwnerUID: \(.ownerReferences[0].uid[0:13]) | DelTime: \(if .deletionTimestamp then "SET ⚠" else "none" end)"),
        ""
    '
}

# Detailed analysis - show everything including issues
detailed_analysis() {
    jq -r '
        def format_commit(c):
            if c == null or c == "none" then "N/A"
            else c[0:8]
            end;

        "════════════════════════════════════════════════════════════════",
        "DETAILED FLEET ANALYSIS - \(.timestamp)",
        "════════════════════════════════════════════════════════════════",
        "",
        "╔═══ CONTROLLER ═══╗",
        "  Name: \(.controller.name)",
        "  Status: \(.controller.status)",
        "  Restarts: \(.controller.restarts) \(if .controller.restarts > 0 then "⚠ RESTARTED" else "" end)",
        "  Started: \(.controller.startTime)",
        "",
        (if (.diagnostics.stuckBundles | length) > 0 then
            "╔═══ STUCK BUNDLES ⚠ ═══╗",
            (.diagnostics.stuckBundles[] |
                "  Bundle: \(.namespace)/\(.name)",
                "    Generation: \(.generation) / Observed: \(.observedGeneration)",
                "    Deletion Timestamp: \(.deletionTimestamp // "none")",
                "    Reasons: \(.reasons | join(", "))",
                "    Ready Condition: \(.readyCondition.status // "N/A") - \(.readyCondition.message // "")",
                ""
            ),
            ""
        else "" end),
        (if (.diagnostics.stuckBundleDeployments | length) > 0 then
            "╔═══ STUCK BUNDLEDEPLOYMENTS ⚠ ═══╗",
            (.diagnostics.stuckBundleDeployments[] |
                "  BundleDeployment: \(.namespace)/\(.name)",
                "    Generation: \(.generation) / Observed: \(.observedGeneration // "N/A")",
                "    DeploymentID: \(.deploymentID[0:50])...",
                "    AppliedID:    \(.appliedDeploymentID[0:50])...",
                "    Match: \(if .deploymentID == .appliedDeploymentID then "YES" else "NO ⚠" end)",
                "    Deletion Timestamp: \(.deletionTimestamp // "none")",
                "    Reasons: \(.reasons | join(", "))",
                "    Ready Condition: \(.readyCondition.status // "N/A") - \(.readyCondition.message // "")",
                ""
            ),
            ""
        else "" end),
        (if .diagnostics.orphanedSecretsCount > 0 then
            "╔═══ ORPHANED SECRETS ⚠ ═══╗",
            (.orphanedSecrets[] |
                "  Secret: \(.namespace)/\(.name)",
                "    Type: \(.type)",
                "    Reason: \(.reason)",
                "    Deletion Timestamp: \(.deletionTimestamp // "none")",
                "    Owner: \(.ownerReferences[0].kind)/\(.ownerReferences[0].name) (UID: \(.ownerReferences[0].uid[0:13]))",
                ""
            ),
            ""
        else "" end),
        (if .diagnostics.invalidSecretOwnersCount > 0 then
            "╔═══ INVALID SECRET OWNERS ⚠ ═══╗",
            (.diagnostics.invalidSecretOwners[] |
                "  Secret: \(.namespace)/\(.name)",
                "    Type: \(.type)",
                "    Issue: \(.issue)",
                "    Owner: \(.ownerKind)/\(.ownerName)",
                "    Owner UID: \(.ownerUID[0:13])",
                "    Expected UID: \((.expectedUID // "NOT FOUND")[0:13])",
                ""
            ),
            ""
        else "" end),
        (if (.diagnostics.bundlesWithDeletionTimestamp + .diagnostics.bundleDeploymentsWithDeletionTimestamp) > 0 then
            "╔═══ RESOURCES WITH DELETION TIMESTAMPS ⚠ ═══╗",
            (.bundles[] | select(.deletionTimestamp != null) |
                "  Bundle: \(.namespace)/\(.name)",
                "    Deletion Timestamp: \(.deletionTimestamp)",
                "    Finalizers: \(.finalizers | join(", "))",
                ""
            ),
            (.bundledeployments[] | select(.deletionTimestamp != null) |
                "  BundleDeployment: \(.namespace)/\(.name)",
                "    Deletion Timestamp: \(.deletionTimestamp)",
                "    Finalizers: \(.finalizers | join(", "))",
                ""
            ),
            ""
        else "" end),
        (if .apiConsistency.consistent == false then
            "╔═══ API CONSISTENCY ISSUES ⚠ ═══╗",
            "  API Server returned different resource versions!",
            "  Versions: \(.apiConsistency.versions | join(", "))",
            "  This indicates the API server may be returning stale data.",
            ""
        else "" end),
        (if (.recentEvents | length) > 0 then
            "╔═══ RECENT EVENTS ═══╗",
            (.recentEvents[] |
                "  [\(.type)] \(.involvedObject.kind)/\(.involvedObject.name)",
                "    Reason: \(.reason)",
                "    Message: \(.message)",
                "    Count: \(.count) | Last: \(.lastTimestamp)",
                ""
            ),
            ""
        else "" end),
        "╔═══ COMMIT TRACKING ═══╗",
        "GitRepos:",
        (.gitrepos[] | "  \(.name): \(.commit | format_commit)"),
        "",
        "Bundles:",
        (.bundles[] | select(.commit != null) | "  \(.name): \(.commit | format_commit) (UID: \(.uid[0:13]))"),
        "",
        "BundleDeployments:",
        (.bundledeployments[] | select(.commit != null) | "  \(.name): \(.commit | format_commit) (UID: \(.uid[0:13]))"),
        "",
        "Bundle Secrets:",
        (.bundleSecrets[] | "  \(.name) (\(if .type == "fleet.cattle.io/bundle-values/v1alpha1" then "values" else "deployment" end)): \((.commit | format_commit) // "N/A")"),
        ""
    '
}

# Issues-only analysis - only show problems
issues_only() {
    jq -r '
        def format_commit(c):
            if c == null or c == "none" then "N/A"
            else c[0:8]
            end;

        "════════════════════════════════════════════════════════════════",
        "FLEET ISSUES REPORT - \(.timestamp)",
        "════════════════════════════════════════════════════════════════",
        "",
        (if .controller.restarts > 0 then
            "⚠ CONTROLLER RESTARTED:",
            "  Restarts: \(.controller.restarts)",
            "  Current Start Time: \(.controller.startTime)",
            ""
        else "" end),
        (if (.diagnostics.stuckBundles | length) > 0 then
            "✗ STUCK BUNDLES (\(.diagnostics.stuckBundles | length)):",
            (.diagnostics.stuckBundles[] |
                "  • \(.namespace)/\(.name)",
                "    Reasons: \(.reasons | join(", "))",
                "    Gen: \(.generation)/\(.observedGeneration) | DelTime: \(.deletionTimestamp // "none")",
                ""
            )
        else "" end),
        (if (.diagnostics.stuckBundleDeployments | length) > 0 then
            "✗ STUCK BUNDLEDEPLOYMENTS (\(.diagnostics.stuckBundleDeployments | length)):",
            (.diagnostics.stuckBundleDeployments[] |
                "  • \(.namespace)/\(.name)",
                "    Reasons: \(.reasons | join(", "))",
                "    Gen: \(.generation)/\(.observedGeneration // "N/A") | DepID Match: \(if .deploymentID == .appliedDeploymentID then "YES" else "NO" end)",
                ""
            )
        else "" end),
        (if .diagnostics.gitrepoBundleInconsistenciesCount > 0 then
            "✗ GITREPO/BUNDLE INCONSISTENCIES (\(.diagnostics.gitrepoBundleInconsistenciesCount)):",
            (.diagnostics.gitrepoBundleInconsistencies[] |
                "  • Bundle: \(.namespace)/\(.name) (repo: \(.repoName))",
                "    Bundle Commit: \(.bundleCommit[0:8]) | GitRepo Commit: \(.gitrepoCommit[0:8]) \(if .commitMismatch then "⚠ MISMATCH" else "" end)",
                "    Bundle ForceSyncGen: \(.bundleForceSyncGen // "null") | GitRepo ForceSyncGen: \(.gitrepoForceSyncGen // "null") \(if .forceSyncGenMismatch then "⚠ MISMATCH" else "" end)",
                "    Issues: \(.issues | join(", "))",
                ""
            )
        else "" end),
        (if .diagnostics.contentIssuesCount > 0 then
            "✗ CONTENT RESOURCE ISSUES (\(.diagnostics.contentIssuesCount)):",
            (.contentIssues[] |
                "  • BundleDeployment: \(.namespace)/\(.name)",
                "    Content: \(.contentName[0:30])...",
                "    Issues: \(.issues | join(", "))",
                "    Content Exists: \(.contentExists) | DeletionTimestamp: \(.contentDeletionTimestamp // "none")",
                "    Finalizers: \(.contentFinalizers | join(", "))",
                ""
            )
        else "" end),
        (if .diagnostics.orphanedSecretsCount > 0 then
            "⚠ ORPHANED SECRETS (\(.diagnostics.orphanedSecretsCount)):",
            (.orphanedSecrets[] |
                "  • \(.namespace)/\(.name)",
                "    Type: \(.type) | Reason: \(.reason)",
                "    DelTime: \(.deletionTimestamp // "none")",
                ""
            )
        else "" end),
        (if .diagnostics.invalidSecretOwnersCount > 0 then
            "✗ INVALID SECRET OWNERS (\(.diagnostics.invalidSecretOwnersCount)):",
            (.diagnostics.invalidSecretOwners[] |
                "  • \(.namespace)/\(.name)",
                "    Issue: \(.issue) | Owner: \(.ownerKind)/\(.ownerName)",
                "    UID Mismatch: \(.ownerUID[0:13]) vs \((.expectedUID // "N/A")[0:13])",
                ""
            )
        else "" end),
        (if .diagnostics.bundlesWithDeletionTimestamp > 0 then
            "⚠ BUNDLES WITH DELETION TIMESTAMP (\(.diagnostics.bundlesWithDeletionTimestamp)):",
            (.bundles[] | select(.deletionTimestamp != null) |
                "  • \(.namespace)/\(.name)",
                "    DelTime: \(.deletionTimestamp)",
                "    Finalizers: \(.finalizers | join(", "))",
                ""
            )
        else "" end),
        (if .diagnostics.bundleDeploymentsWithDeletionTimestamp > 0 then
            "⚠ BUNDLEDEPLOYMENTS WITH DELETION TIMESTAMP (\(.diagnostics.bundleDeploymentsWithDeletionTimestamp)):",
            (.bundledeployments[] | select(.deletionTimestamp != null) |
                "  • \(.namespace)/\(.name)",
                "    DelTime: \(.deletionTimestamp)",
                "    Finalizers: \(.finalizers | join(", "))",
                ""
            )
        else "" end),
        (if .diagnostics.contentsWithDeletionTimestamp > 0 then
            "⚠ CONTENTS WITH DELETION TIMESTAMP (\(.diagnostics.contentsWithDeletionTimestamp)):",
            (.contents[] | select(.deletionTimestamp != null) |
                "  • \(.name[0:40])...",
                "    DelTime: \(.deletionTimestamp)",
                "    Finalizers: \(.finalizers | join(", "))",
                ""
            )
        else "" end),
        (if .apiConsistency.consistent == false then
            "✗ API CONSISTENCY FAILURE:",
            "  Different resource versions returned: \(.apiConsistency.versions | join(", "))",
            "  This indicates the API server is returning stale cached data!",
            ""
        else "" end),
        (if (.diagnostics.stuckBundles | length) == 0 and
            (.diagnostics.stuckBundleDeployments | length) == 0 and
            .diagnostics.gitrepoBundleInconsistenciesCount == 0 and
            .diagnostics.contentIssuesCount == 0 and
            .diagnostics.orphanedSecretsCount == 0 and
            .diagnostics.invalidSecretOwnersCount == 0 and
            .diagnostics.bundlesWithDeletionTimestamp == 0 and
            .diagnostics.bundleDeploymentsWithDeletionTimestamp == 0 and
            .diagnostics.contentsWithDeletionTimestamp == 0 and
            .apiConsistency.consistent == true and
            .controller.restarts == 0 then
            "✓ NO ISSUES DETECTED - All systems healthy!",
            ""
        else "" end)
    '
}

# Compare two snapshots
compare_snapshots() {
    local file1="$1"
    local file2="$2"

    jq -n --slurpfile before "$file1" --slurpfile after "$file2" '
        def format_commit(c):
            if c == null or c == "none" then "N/A"
            else c[0:8]
            end;

        $before[0] as $b | $after[0] as $a |

        "════════════════════════════════════════════════════════════════",
        "FLEET CHANGES COMPARISON",
        "════════════════════════════════════════════════════════════════",
        "Before: \($b.timestamp)",
        "After:  \($a.timestamp)",
        "",
        "╔═══ CONTROLLER CHANGES ═══╗",
        (if $b.controller.name != $a.controller.name then
            "  Pod Changed: \($b.controller.name) → \($a.controller.name) ⚠ POD RESTARTED!"
        else
            "  Pod: \($a.controller.name) (unchanged)"
        end),
        (if $b.controller.restarts != $a.controller.restarts then
            "  Restarts: \($b.controller.restarts) → \($a.controller.restarts) ⚠ INCREASED!"
        else
            "  Restarts: \($a.controller.restarts) (unchanged)"
        end),
        "",
        "╔═══ GITREPO CHANGES ═══╗",
        ([$a.gitrepos[] | .name] - [$b.gitrepos[] | .name] | if length > 0 then
            "  New GitRepos: \(. | join(", "))"
        else "" end),
        ([$b.gitrepos[] | .name] - [$a.gitrepos[] | .name] | if length > 0 then
            "  Deleted GitRepos: \(. | join(", "))"
        else "" end),
        ($b.gitrepos[] | . as $bg | $a.gitrepos[] | select(.name == $bg.name) | . as $ag |
            if $bg.commit != $ag.commit or $bg.generation != $ag.generation or $bg.forceSyncGeneration != $ag.forceSyncGeneration then
                "  \($ag.name):",
                (if $bg.commit != $ag.commit then "    Commit: \($bg.commit | format_commit) → \($ag.commit | format_commit)" else "" end),
                (if $bg.generation != $ag.generation then "    Generation: \($bg.generation) → \($ag.generation)" else "" end),
                (if $bg.observedGeneration != $ag.observedGeneration then "    ObservedGen: \($bg.observedGeneration) → \($ag.observedGeneration)" else "" end),
                (if $bg.forceSyncGeneration != $ag.forceSyncGeneration then "    ForceSyncGen: \($bg.forceSyncGeneration // "N/A") → \($ag.forceSyncGeneration // "N/A")" else "" end)
            else "" end
        ),
        "",
        "╔═══ BUNDLE CHANGES ═══╗",
        ([$a.bundles[] | .name] - [$b.bundles[] | .name] | if length > 0 then
            "  New Bundles: \(. | join(", "))"
        else "" end),
        ([$b.bundles[] | .name] - [$a.bundles[] | .name] | if length > 0 then
            "  Deleted Bundles: \(. | join(", "))"
        else "" end),
        ($b.bundles[] | . as $bb | $a.bundles[] | select(.name == $bb.name) | . as $ab |
            if $bb.commit != $ab.commit or $bb.generation != $ab.generation or $bb.uid != $ab.uid or $bb.deletionTimestamp != $ab.deletionTimestamp then
                "  \($ab.name):",
                (if $bb.commit != $ab.commit then "    Commit: \(($bb.commit | format_commit) // "N/A") → \(($ab.commit | format_commit) // "N/A")" else "" end),
                (if $bb.generation != $ab.generation then "    Generation: \($bb.generation) → \($ab.generation)" else "" end),
                (if $bb.observedGeneration != $ab.observedGeneration then "    ObservedGen: \($bb.observedGeneration) → \($ab.observedGeneration)" else "" end),
                (if $bb.uid != $ab.uid then "    UID CHANGED: \($bb.uid[0:13]) → \($ab.uid[0:13]) ⚠ RECREATED!" else "" end),
                (if $bb.deletionTimestamp != $ab.deletionTimestamp then "    DeletionTimestamp: \($bb.deletionTimestamp // "none") → \($ab.deletionTimestamp // "none")" else "" end)
            else "" end
        ),
        "",
        "╔═══ BUNDLEDEPLOYMENT CHANGES ═══╗",
        ([$a.bundledeployments[] | .name] - [$b.bundledeployments[] | .name] | if length > 0 then
            "  New BundleDeployments: \(. | join(", "))"
        else "" end),
        ([$b.bundledeployments[] | .name] - [$a.bundledeployments[] | .name] | if length > 0 then
            "  Deleted BundleDeployments: \(. | join(", "))"
        else "" end),
        ($b.bundledeployments[] | . as $bbd | $a.bundledeployments[] | select(.name == $bbd.name) | . as $abd |
            if $bbd.commit != $abd.commit or $bbd.deploymentID != $abd.deploymentID or $bbd.uid != $abd.uid or $bbd.deletionTimestamp != $abd.deletionTimestamp then
                "  \($abd.name):",
                (if $bbd.commit != $abd.commit then "    Commit: \(($bbd.commit | format_commit) // "N/A") → \(($abd.commit | format_commit) // "N/A")" else "" end),
                (if $bbd.deploymentID != $abd.deploymentID then "    DeploymentID changed" else "" end),
                (if $bbd.appliedDeploymentID != $abd.appliedDeploymentID then "    AppliedDeploymentID changed" else "" end),
                (if $bbd.uid != $abd.uid then "    UID CHANGED: \($bbd.uid[0:13]) → \($abd.uid[0:13]) ⚠ RECREATED!" else "" end),
                (if $bbd.deletionTimestamp != $abd.deletionTimestamp then "    DeletionTimestamp: \($bbd.deletionTimestamp // "none") → \($abd.deletionTimestamp // "none")" else "" end)
            else "" end
        ),
        "",
        "╔═══ DIAGNOSTICS CHANGES ═══╗",
        "  Stuck Bundles: \($b.diagnostics.stuckBundles | length) → \($a.diagnostics.stuckBundles | length) \(if ($a.diagnostics.stuckBundles | length) > ($b.diagnostics.stuckBundles | length) then "⚠ INCREASED" else "" end)",
        "  Stuck BundleDeployments: \($b.diagnostics.stuckBundleDeployments | length) → \($a.diagnostics.stuckBundleDeployments | length) \(if ($a.diagnostics.stuckBundleDeployments | length) > ($b.diagnostics.stuckBundleDeployments | length) then "⚠ INCREASED" else "" end)",
        "  Orphaned Secrets: \($b.diagnostics.orphanedSecretsCount) → \($a.diagnostics.orphanedSecretsCount) \(if $a.diagnostics.orphanedSecretsCount > $b.diagnostics.orphanedSecretsCount then "⚠ INCREASED" else "" end)",
        "  Invalid Secret Owners: \($b.diagnostics.invalidSecretOwnersCount) → \($a.diagnostics.invalidSecretOwnersCount) \(if $a.diagnostics.invalidSecretOwnersCount > $b.diagnostics.invalidSecretOwnersCount then "⚠ INCREASED" else "" end)",
        ""
    '
}

# JSON output for programmatic use
json_output() {
    jq '{
        timestamp,
        summary: {
            controllerRestarts: .controller.restarts,
            gitrepoCount: (.gitrepos | length),
            bundleCount: (.bundles | length),
            bundleDeploymentCount: (.bundledeployments | length),
            secretCount: (.bundleSecrets | length),
            stuckBundlesCount: (.diagnostics.stuckBundles | length),
            stuckBundleDeploymentsCount: (.diagnostics.stuckBundleDeployments | length),
            orphanedSecretsCount: .diagnostics.orphanedSecretsCount,
            invalidSecretOwnersCount: .diagnostics.invalidSecretOwnersCount,
            apiConsistent: .apiConsistency.consistent,
            hasIssues: (
                (.diagnostics.stuckBundles | length) > 0 or
                (.diagnostics.stuckBundleDeployments | length) > 0 or
                .diagnostics.orphanedSecretsCount > 0 or
                .diagnostics.invalidSecretOwnersCount > 0 or
                .diagnostics.bundlesWithDeletionTimestamp > 0 or
                .diagnostics.bundleDeploymentsWithDeletionTimestamp > 0 or
                .apiConsistency.consistent == false
            )
        },
        issues: {
            stuckBundles: .diagnostics.stuckBundles,
            stuckBundleDeployments: .diagnostics.stuckBundleDeployments,
            orphanedSecrets: .orphanedSecrets,
            invalidSecretOwners: .diagnostics.invalidSecretOwners
        },
        commits: {
            gitrepos: [.gitrepos[] | {name, commit: .commit[0:8]}],
            bundles: [.bundles[] | select(.commit != null) | {name, commit: .commit[0:8], uid: .uid[0:13]}],
            bundledeployments: [.bundledeployments[] | select(.commit != null) | {name, commit: .commit[0:8], uid: .uid[0:13]}]
        }
    }'
}

# Main execution
case "$MODE" in
    --compare)
        if [ -z "$INPUT_FILE" ] || [ -z "$3" ]; then
            echo "Usage: $0 --compare <file1> <file2>"
            exit 1
        fi
        compare_snapshots "$INPUT_FILE" "$3"
        ;;
    --json)
        if [ -n "$INPUT_FILE" ]; then
            cat "$INPUT_FILE" | json_output
        else
            json_output
        fi
        ;;
    --detailed|-d)
        if [ -n "$INPUT_FILE" ]; then
            cat "$INPUT_FILE" | detailed_analysis
        else
            detailed_analysis
        fi
        ;;
    --issues|-i)
        if [ -n "$INPUT_FILE" ]; then
            cat "$INPUT_FILE" | issues_only
        else
            issues_only
        fi
        ;;
    --live|-l)
        while IFS= read -r line; do
            echo "$line" | summary_analysis
            echo ""
            echo "────────────────────────────────────────────────────────────"
            echo ""
        done
        ;;
    --summary|-s|summary|*)
        if [ -n "$INPUT_FILE" ]; then
            cat "$INPUT_FILE" | summary_analysis
        else
            summary_analysis
        fi
        ;;
esac
