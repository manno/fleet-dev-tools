#!/bin/bash
set -e

repo="rancher/fleet"

# copy title, body from this issue
main_issue=${1}

release_milestone=${2-2.9.2}

# backport to this release
release_version=${3-v0.10}

if [ $# -lt 3 ]; then
  echo "Usage: $0 main_issue release_milestone [release_version]"
  echo "Example: $0 123 2.9.2 v0.10"
  exit 1
fi

title=$(gh issue -R "$repo" view "$main_issue" --json title -q '.title')
body=$(gh issue -R "$repo" view "$main_issue" --json body -q '.body')
# can also parse branch release/v0.10
version=$(echo "$release_version" | cut -d'/' -f2)

echo "Creating backport issue: '[$version] Backport of $title', on milestone $release_milestone"
read -rp "Press any key to continue... " -n1 -s

gh issue -R "$repo" create --title "[$version] Backport of $title" --milestone "$release_milestone" --body "
Backport of #$main_issue
$body
"
