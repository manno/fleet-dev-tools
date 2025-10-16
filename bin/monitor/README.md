# Fleet Resource Monitoring Tools - Complete Guide

Comprehensive documentation for Fleet monitoring scripts that diagnose bundle deployment issues, specifically designed to detect why bundles get stuck during the targeting phase.

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Scripts Overview](#scripts-overview)
- [Requirements Coverage](#requirements-coverage)
- [Common Workflows](#common-workflows)
- [What the Tools Detect](#what-the-tools-detect)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Output Formats](#output-formats)
- [Usage Examples](#usage-examples)
- [Tips & Best Practices](#tips--best-practices)
- [Performance & Limitations](#performance--limitations)
- [Architecture](#architecture)
- [Troubleshooting the Scripts](#troubleshooting-the-scripts)
- [Support](#support)

---

## Requirements

### System Requirements
- **kubectl**: v1.20+ (tested with v1.34.1)
- **jq**: v1.6+ (tested with v1.8.1)  
- **bash**: v4.0+ (works with v3.2+, but v4.0+ recommended for better process substitution support)

### Kubernetes Access
- Access to a Kubernetes cluster running Fleet
- Appropriate RBAC permissions to read:
  - GitRepos, Bundles, BundleDeployments, Contents (fleet.cattle.io resources)
  - Secrets (for bundle lifecycle secrets)
  - Pods (to check controller status)
  - Events

### Installation
```bash
# Ensure scripts are executable
chmod +x monitor-fleet-resources.sh analyze-fleet-monitoring.sh

# Verify dependencies
kubectl version --client
jq --version
bash --version
```

---

## Quick Start

### Basic Monitoring
```bash
# Monitor every 5 seconds and save to file
./monitor-fleet-resources.sh 5 > monitoring.json

# Analyze the results (after pressing Ctrl+C)
./analyze-fleet-monitoring.sh --issues monitoring.json
```

### Live Analysis
```bash
# Monitor and analyze in real-time
./monitor-fleet-resources.sh 5 2>/dev/null | ./analyze-fleet-monitoring.sh --live
```

### Compare Before/After
```bash
# Capture before making changes
./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > before.json

# Make your changes (e.g., update GitRepo)

# Capture after
./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > after.json

# Compare
./analyze-fleet-monitoring.sh --compare before.json after.json
```

---

## Scripts Overview

### 1. `monitor-fleet-resources.sh` - Data Collection

Continuously monitors Fleet resources and outputs JSON snapshots.

**What It Tracks:**

**Core Resources:**
- **Controller Pod**: Name, restarts, status, uptime (detects cache clearing)
- **GitRepos**: Generation, commit, forceSyncGeneration, conditions, observedGeneration
- **Bundles**: UID, commit, generation, forceSyncGeneration, conditions, finalizers, deletionTimestamp, observedGeneration
- **BundleDeployments**: UID, commit, generation, forceSyncGeneration, deploymentID, appliedDeploymentID, conditions, finalizers, deletionTimestamp
- **Contents**: SHA256 names, finalizers, deletionTimestamp
- **Bundle Lifecycle Secrets**: 
  - `fleet.cattle.io/bundle-values/v1alpha1` (owned by Bundles)
  - `fleet.cattle.io/bundle-deployment/v1alpha1` (owned by BundleDeployments)

**Diagnostics:**
- Orphaned/stale secrets (UID validation)
- Missing or problematic Content resources
- API server consistency (time travel detection)
- Recent Fleet events
- Stuck resources with reasons
- GitRepo/Bundle inconsistencies

**Usage:**
```bash
# Monitor every 5 seconds
./monitor-fleet-resources.sh 5

# Monitor every 10 seconds and save to file
./monitor-fleet-resources.sh 10 > monitoring-$(date +%Y%m%d-%H%M%S).json

# Monitor and analyze live
./monitor-fleet-resources.sh 5 2>/dev/null | ./analyze-fleet-monitoring.sh --live
```

### 2. `analyze-fleet-monitoring.sh` - Data Analysis

Processes monitoring output to extract insights.

**Analysis Modes:**

```bash
# Summary view (default) - High-level overview
./analyze-fleet-monitoring.sh monitoring.json
./analyze-fleet-monitoring.sh --summary monitoring.json

# Issues only - Show problems only
./analyze-fleet-monitoring.sh --issues monitoring.json
./analyze-fleet-monitoring.sh -i monitoring.json

# Detailed view - Everything including events
./analyze-fleet-monitoring.sh --detailed monitoring.json
./analyze-fleet-monitoring.sh -d monitoring.json

# JSON output - For programmatic use
./analyze-fleet-monitoring.sh --json monitoring.json | jq .

# Compare two snapshots
./analyze-fleet-monitoring.sh --compare before.json after.json

# Live analysis - Continuously analyze streaming output
./monitor-fleet-resources.sh 5 2>/dev/null | ./analyze-fleet-monitoring.sh --live
```

---

## Requirements Coverage

The scripts detect all critical issues that cause bundles to get stuck during the targeting phase.

| Requirement | Status | Function | Output Field |
|-------------|--------|----------|--------------|
| API Time Travel | ✅ | `check_api_consistency()` | `apiConsistency.consistent` |
| Old forceSyncGeneration | ✅ | `detect_gitrepo_bundle_inconsistencies()` | `diagnostics.gitrepoBundleInconsistencies` |
| UID Mismatches | ✅ | `validate_secret_owners()` | `diagnostics.invalidSecretOwners` |
| Deletion Timestamps | ✅ | All resource functions | `*WithDeletionTimestamp` counters |
| Blocking Finalizers | ✅ | All resource functions | `.finalizers` on each resource |
| Stale Commit Hashes | ✅ | `detect_gitrepo_bundle_inconsistencies()` | `diagnostics.gitrepoBundleInconsistencies` |
| DeploymentID Mismatch | ✅ | `detect_stuck_bundledeployments()` | `diagnostics.stuckBundleDeployments` |

---

## Common Workflows

### Continuous Monitoring

Monitor every 5 seconds and show summary when interrupted:
```bash
./monitor-fleet-resources.sh 5 > monitoring-session.json
# Press Ctrl+C when done
./analyze-fleet-monitoring.sh --summary monitoring-session.json
```

### Capture During Issue

When bundles get stuck, capture snapshots:
```bash
# Start monitoring
./monitor-fleet-resources.sh 3 > stuck-bundles-$(date +%Y%m%d-%H%M%S).json

# Let it run for a few minutes while the issue occurs
# Press Ctrl+C

# Analyze what happened
./analyze-fleet-monitoring.sh --issues stuck-bundles-*.json
```

### Compare Before/After GitRepo Update

```bash
# Capture before update
./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > before.json

# Update the GitRepo
kubectl edit gitrepo/my-repo -n fleet-local

# Wait a moment, then capture after
./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > after.json

# Compare
./analyze-fleet-monitoring.sh --compare before.json after.json
```

### Track Multiple Snapshots

```bash
# Capture snapshot every 30 seconds for 5 minutes
for i in {1..10}; do
  ./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > snapshot-$i.json
done

# Analyze each
for f in snapshot-*.json; do
  echo "=== $f ==="
  ./analyze-fleet-monitoring.sh --issues "$f"
done
```

---

## What the Tools Detect

### Critical Issues for Stuck Bundles

#### 1. ✅ API Server "Time Travel"
**Problem:** API server returns old/stale cached versions of resources  
**Detection:** `check_api_consistency()` makes multiple requests and compares resourceVersions  
**Output:** `apiConsistency.consistent` (false if time travel detected)  
**Impact:** Causes controller to work with outdated data, leading to incorrect decisions

**Example:**
```json
{
  "apiConsistency": {
    "consistent": false,
    "versions": ["12345", "12340", "12345"]
  }
}
```

**How to Check:**
```bash
cat monitoring.json | jq '.apiConsistency'
```

---

#### 2. ✅ Bundles with Outdated forceSyncGeneration
**Problem:** Bundle hasn't updated to match GitRepo's forceSyncGeneration  
**Detection:** `detect_gitrepo_bundle_inconsistencies()` compares Bundle vs GitRepo  
**Output:** `diagnostics.gitrepoBundleInconsistencies[]`  
**Impact:** Bundle won't trigger deployment update even after GitRepo change

**Example:**
```json
{
  "name": "my-bundle",
  "bundleForceSyncGen": 1,
  "gitrepoForceSyncGen": 3,
  "forceSyncGenMismatch": true,
  "issues": ["force_sync_gen_mismatch"]
}
```

**How to Check:**
```bash
cat monitoring.json | jq '.diagnostics.gitrepoBundleInconsistencies'
```

---

#### 3. ✅ UID Mismatches in Owner References
**Problem:** Secret references a Bundle/BundleDeployment that was recreated (UID changed)  
**Detection:** `validate_secret_owners()` compares secret ownerUID with actual resource UID  
**Output:** `diagnostics.invalidSecretOwners[]`, `orphanedSecrets[]`  
**Impact:** Secrets block garbage collection, cause duplicate resources, prevent updates

**Validates:**
- `fleet.cattle.io/bundle-values/v1alpha1` → Bundle UID
- `fleet.cattle.io/bundle-deployment/v1alpha1` → BundleDeployment UID

**Example:**
```json
{
  "name": "my-bundle-values",
  "type": "fleet.cattle.io/bundle-values/v1alpha1",
  "ownerUID": "old-uid-abc123",
  "expectedUID": "new-uid-def456",
  "reason": "owner_uid_mismatch"
}
```

**How to Check:**
```bash
cat monitoring.json | jq '.diagnostics.invalidSecretOwners'
```

---

#### 4. ✅ Deletion Timestamps Blocking Updates
**Problem:** Resources marked for deletion but stuck due to finalizers  
**Detection:** Tracked on all resources (Bundles, BundleDeployments, Contents, Secrets)  
**Output:** `*WithDeletionTimestamp` counters, individual resource `deletionTimestamp` fields  
**Impact:** Prevents new versions from being created, blocks targeting phase

**Example:**
```json
{
  "name": "stuck-bundle",
  "deletionTimestamp": "2025-10-16T08:00:00Z",
  "finalizers": ["fleet.cattle.io/bundle-finalizer"],
  "reasons": ["deletion_timestamp_set"]
}
```

**How to Check:**
```bash
cat monitoring.json | jq '{
  bundles: (.bundles[] | select(.deletionTimestamp != null) | .name),
  bundledeployments: (.bundledeployments[] | select(.deletionTimestamp != null) | .name),
  contents: (.contents[] | select(.deletionTimestamp != null) | .name)
}'
```

---

#### 5. ✅ Finalizers Not Removed
**Problem:** Finalizers prevent resource deletion and block cleanup  
**Detection:** Tracked on all resources  
**Output:** `.finalizers[]` on each resource  
**Impact:** Resources can't be deleted, updates can't proceed

**Tracked on:**
- GitRepos, Bundles, BundleDeployments, Contents, Secrets

**Example:**
```json
{
  "name": "my-content",
  "finalizers": ["my-bundle-name"],
  "deletionTimestamp": "2025-10-16T08:00:00Z"
}
```

---

#### 6. ✅ Bundles Not Updating to Current Commit
**Problem:** Bundle hasn't updated to GitRepo's latest commit  
**Detection:** `detect_gitrepo_bundle_inconsistencies()` compares commit hashes  
**Output:** `diagnostics.gitrepoBundleInconsistencies[]`  
**Impact:** Deployments use old manifests, changes aren't applied

**Example:**
```json
{
  "name": "my-bundle",
  "bundleCommit": "abc12345",
  "gitrepoCommit": "def67890",
  "commitMismatch": true,
  "issues": ["commit_mismatch"]
}
```

**How to Check:**
```bash
cat monitoring.json | jq '.diagnostics.gitrepoBundleInconsistencies[] | select(.commitMismatch)'
```

---

#### 7. ✅ deploymentID and appliedDeploymentID Not Converging
**Problem:** BundleDeployment hasn't applied the target deployment  
**Detection:** `detect_stuck_bundledeployments()` compares spec vs status  
**Output:** `diagnostics.stuckBundleDeployments[]`  
**Impact:** Target cluster not updated with new manifests

**Also detects:**
- Missing Content resources referenced by deploymentIDs
- Content resources with deletion timestamps

**Example:**
```json
{
  "name": "my-bundle",
  "deploymentID": "s-newcontent123:options456",
  "appliedDeploymentID": "s-oldcontent789:options456",
  "reasons": ["deployment_id_mismatch"]
}
```

**How to Check:**
```bash
cat monitoring.json | jq '.diagnostics.stuckBundleDeployments[] | select(.reasons | contains(["deployment_id_mismatch"]))'
```

---

### Additional Detections

#### Stuck Bundles
- Generation vs observedGeneration mismatch
- Not Ready conditions
- Deletion timestamp set (finalizer blocking)

#### Stuck BundleDeployments
- Generation vs observedGeneration mismatch
- DeploymentID vs appliedDeploymentID mismatch
- Not Ready conditions
- Deletion timestamp set

#### Content Resource Issues
- Missing content resources
- Content with deletion timestamps
- Staged content not found
- Applied content not found

#### Controller Issues
- Pod restarts (cache cleared)
- Pod name change (full restart)

#### Generation Mismatches
- Bundle generation vs observedGeneration
- BundleDeployment generation vs observedGeneration

---

## Troubleshooting Guide

### Scenario: Bundles Getting Stuck During Targeting

This is the primary use case the tools were designed for.

**Symptoms:**
- GitRepo shows Ready but bundles aren't updating
- BundleDeployments not applying new deploymentIDs
- Resources stuck with old commits or forceSyncGeneration

**Diagnosis Steps:**

1. **Start monitoring before the update:**
   ```bash
   ./monitor-fleet-resources.sh 5 > monitoring.json
   ```

2. **In another terminal, update the GitRepo:**
   ```bash
   kubectl edit gitrepo/myrepo -n fleet-local
   # Or trigger force sync:
   kubectl annotate gitrepo/myrepo -n fleet-local "fleet.cattle.io/force-sync=$(date +%s)"
   ```

3. **Wait for the issue to occur, then stop monitoring (Ctrl+C)**

4. **Analyze what happened:**
   ```bash
   # Check for issues
   ./analyze-fleet-monitoring.sh --issues monitoring.json
   
   # See full details
   ./analyze-fleet-monitoring.sh --detailed monitoring.json
   ```

5. **Look for specific problems - see examples above in "What the Tools Detect"**

**Common Root Causes and Fixes:**

| Issue Detected | Root Cause | Fix |
|----------------|------------|-----|
| API time travel | K8s API server cache issues | Restart kube-apiserver or wait for cache refresh |
| forceSyncGen mismatch | Bundle controller not reconciling | Check controller logs, restart if needed |
| UID mismatch in secrets | Resource was deleted and recreated | Delete orphaned secrets manually |
| Deletion timestamp stuck | Finalizer not removed | Remove finalizer: `kubectl patch ... --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'` |
| Commit mismatch | GitJob hasn't run or failed | Check GitJob status: `kubectl get gitjobs -A` |
| deploymentID not converging | Content missing or agent stuck | Check content exists, check fleet-agent logs |
| Missing content | Content GC'd prematurely | Check content finalizers, may need to retrigger |

### Scenario: Comparing Two Time Points

Track how the system evolves to find when things went wrong.

```bash
# Capture state now
./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > before.json

# Wait or make changes

# Capture state later  
./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > after.json

# See what changed
./analyze-fleet-monitoring.sh --compare before.json after.json
```

**What to look for:**
- Controller pod restarted (cache cleared)
- Resources recreated (UID changed)
- Commits progressing or stuck
- Generation numbers increasing but observedGeneration not following
- DeploymentIDs changing but not being applied

### Scenario: Continuous Monitoring During Issue

Capture multiple snapshots to track progression:

```bash
# Capture snapshot every 30 seconds for 5 minutes
for i in {1..10}; do
  ./monitor-fleet-resources.sh 30 2>/dev/null | head -1 > snapshot-$i.json
done

# Analyze each
for f in snapshot-*.json; do
  echo "=== $f ==="
  ./analyze-fleet-monitoring.sh --issues "$f"
done

# Or compare consecutive snapshots
for i in {1..9}; do
  echo "=== Changes from snapshot-$i to snapshot-$((i+1)) ==="
  ./analyze-fleet-monitoring.sh --compare snapshot-$i.json snapshot-$((i+1)).json
done
```

---

## Output Formats

### Summary Output
- High-level overview
- Resource counts
- Diagnostics summary
- Quick commit tracking

### Issues Output
- Only shows problems
- Good for focusing on failures
- Compact format

### Detailed Output
- Everything including healthy resources
- Full error messages
- Event history
- Useful for deep debugging

### JSON Output
- Machine-readable format
- For scripting and automation
- Easy to pipe to `jq` for custom queries

---

## Usage Examples

### JSON Processing Examples

Extract specific information:
```bash
# Get all commits
./analyze-fleet-monitoring.sh --json monitoring.json | jq '.commits'

# Check if there are issues
./analyze-fleet-monitoring.sh --json monitoring.json | jq '.summary.hasIssues'

# Get stuck bundle names
./analyze-fleet-monitoring.sh --json monitoring.json | jq '.issues.stuckBundles[].name'

# Get controller restart count over time
for f in snapshot-*.json; do
  echo -n "$f: "
  ./analyze-fleet-monitoring.sh --json "$f" | jq '.summary.controllerRestarts'
done
```

---

## Tips & Best Practices

1. **Use stderr redirection** (`2>/dev/null`) with monitor script to hide info messages when piping
2. **Save snapshots** before making changes for comparison
3. **Use short intervals** (3-5 seconds) when debugging active issues
4. **Use longer intervals** (30-60 seconds) for long-running monitoring
5. **Check commits** - mismatched commits across resources indicate sync issues
6. **Watch UIDs** - UID changes indicate resource recreation
7. **Monitor deletionTimestamp** - set timestamps without deletion indicate stuck finalizers
8. **Validate content resources** - missing content blocks deployments
9. **Check forceSyncGeneration** - mismatches prevent updates from triggering
10. **Look for API inconsistency** - time travel indicates serious cache problems

---

## Performance & Limitations

### Performance Notes

The monitoring script makes multiple `kubectl` calls per snapshot:
- ~15-20 API calls per execution
- With interval=5s, that's ~3-4 API calls per second
- Tested with 143 bundles, 282 secrets without issues
- Consider longer intervals for production monitoring
- Use `--issues` analysis to reduce output verbosity

**Optimizations:**
- Process substitution instead of command-line arguments avoids "Argument list too long" errors
- Efficient jq processing for large datasets
- Minimal resource tracking (only essential fields)

### Limitations

1. **Point-in-time snapshots:** Captures state at specific moments, may miss transient issues
2. **No historical correlation:** Compare multiple snapshots to see trends
3. **Manual interpretation:** Requires understanding of Fleet's reconciliation process
4. **Read-only:** Scripts only observe, don't fix issues
5. **Cluster scope:** Must run against cluster with appropriate permissions

---

## Architecture

### Data Flow
```
kubectl → monitor-fleet-resources.sh → JSON snapshot → analyze-fleet-monitoring.sh → Human-readable report
```

### Key Design Decisions

1. **JSON Output:** Machine-readable, pipe-friendly, preserves all data
2. **Separate Scripts:** Monitoring and analysis decoupled for flexibility  
3. **Process Substitution:** Avoids shell argument limits with large datasets
4. **Comprehensive Tracking:** Captures all fields needed for diagnosis
5. **Multiple Analysis Modes:** Summary, issues, detailed, JSON, compare

### Script Internals

**monitor-fleet-resources.sh functions:**
- `get_controller_info()` - Fleet controller pod status
- `get_gitrepos()` - GitRepo resources
- `get_bundles()` - Bundle resources with UIDs
- `get_bundledeployments()` - BundleDeployment resources with UIDs
- `get_contents()` - Content resources
- `get_bundle_secrets()` - Lifecycle secrets
- `get_orphaned_secrets()` - UID-validated secret orphan detection
- `check_content_issues()` - Content resource validation
- `check_api_consistency()` - Time travel detection
- `get_fleet_events()` - Recent Fleet events
- `detect_stuck_bundles()` - Bundle stuck state detection
- `detect_stuck_bundledeployments()` - BundleDeployment stuck state detection
- `detect_gitrepo_bundle_inconsistencies()` - Commit/forceSyncGen validation
- `validate_secret_owners()` - OwnerReference UID validation

**analyze-fleet-monitoring.sh modes:**
- `summary_analysis()` - High-level overview
- `detailed_analysis()` - Full resource details
- `issues_only()` - Problems only
- `json_output()` - Structured JSON for automation
- `compare_snapshots()` - Diff two snapshots

---

## Troubleshooting the Scripts

### "Argument list too long"
**Fixed in current version.** If you see this error, update to latest version using process substitution.

### "jq: parse error"
**Cause:** Invalid JSON in input  
**Fix:** Check monitoring script output, ensure complete JSON object captured

### "command not found: kubectl"
**Cause:** kubectl not in PATH  
**Fix:** Install kubectl or add to PATH

### Slow Performance
**Cause:** Large number of resources  
**Fix:** 
- Increase monitoring interval
- Filter specific namespaces if possible
- Use `--issues` mode for less verbose output

### Missing Data
**Cause:** Insufficient RBAC permissions  
**Fix:** Ensure service account/user has read access to all Fleet resources
