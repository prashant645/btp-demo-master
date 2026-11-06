#!/usr/bin/env bash
# =============================================================================
# Cut a release-candidate branch from master -> deploys to QA
# =============================================================================
# FIPC convention: rel.YYYY.MM.DD, optionally -hotfix.N. Pushing the branch is
# what triggers .github/workflows/deploy-qa.yaml.
#
#   ./scripts/cut-release-candidate.sh 2026.09.29      -> rel.2026.09.29
#   ./scripts/cut-release-candidate.sh 2026.09.29 1    -> rel.2026.09.29-hotfix.1
# =============================================================================
set -euo pipefail

DATE_PART="${1:-}"
HOTFIX_PART="${2:-}"

if [[ -z "$DATE_PART" ]]; then
  echo "Usage: $0 <YYYY.MM.DD> [hotfix-number]" >&2
  exit 1
fi

if [[ ! "$DATE_PART" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "Error: date must be YYYY.MM.DD (got '$DATE_PART')" >&2
  exit 1
fi

BRANCH="rel.${DATE_PART}"
if [[ -n "$HOTFIX_PART" ]]; then
  if [[ ! "$HOTFIX_PART" =~ ^[0-9]+$ ]]; then
    echo "Error: hotfix number must be an integer (got '$HOTFIX_PART')" >&2
    exit 1
  fi
  BRANCH="${BRANCH}-hotfix.${HOTFIX_PART}"
fi

echo "==> Updating master"
git checkout master
git pull --ff-only origin master

echo "==> Creating $BRANCH"
git checkout -b "$BRANCH"

echo "==> Pushing $BRANCH (this triggers the QA deploy)"
git push -u origin "$BRANCH"

cat <<MSG

Release candidate $BRANCH pushed.
  QA deploy: .github/workflows/deploy-qa.yaml
  Promote to prod when QA signs off:
      ./scripts/cut-release.sh ${DATE_PART}${HOTFIX_PART:+ $HOTFIX_PART}
MSG
