#!/bin/bash
set -e

repo="rancher/fleet"

# refer this issue
issue=${1}

# copy title from this pr, body should contain "backport of, refers to #"
main_pr=${2}

# backport to this release
release_branch=${3-release/v0.10}

# must be created before
head=${4-HEAD} #v0.10-9010-feature..

if [ $# -lt 4 ]; then
  echo "Usage: $0 issue main_pr [release_branch] [HEAD]"
  echo "Example: $0 123 456 2.9.2 release/v0.10 HEAD"
  exit 1
fi

version=$(echo "$release_branch" | cut -d'/' -f2)
title=$(gh pr -R "$repo" view "$main_pr" --json title -q '.title')

echo "Creating backport pr: '[$version] Backport of $title', refers to #$issue, to $release_branch, from git branch $head"
read -rp "Press any key to continue... " -n1 -s

gh pr create -R "$repo" --base "$release_branch" --head "$head" --title "[$version] Backport of $title" --body "Backport of #$main_pr, refers to #$issue"
