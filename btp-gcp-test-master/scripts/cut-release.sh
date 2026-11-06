#!/usr/bin/env bash
# =============================================================================
# Promote a release candidate to production
# =============================================================================
# FIPC convention: vYYYY.MM.DD[-hotfix.N], branched from the matching rel.*
# branch. Pushing it triggers .github/workflows/deploy-prod.yaml, which then
# waits on the `production` GitHub environment's required reviewers.
#
#   ./scripts/cut-release.sh 2026.09.29      -> v2026.09.29   (from rel.2026.09.29)
#   ./scripts/cut-release.sh 2026.09.29 1    -> v2026.09.29-hotfix.1
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

SUFFIX=""
if [[ -n "$HOTFIX_PART" ]]; then
  if [[ ! "$HOTFIX_PART" =~ ^[0-9]+$ ]]; then
    echo "Error: hotfix number must be an integer (got '$HOTFIX_PART')" >&2
    exit 1
  fi
  SUFFIX="-hotfix.${HOTFIX_PART}"
fi

RC_BRANCH="rel.${DATE_PART}${SUFFIX}"
REL_BRANCH="v${DATE_PART}${SUFFIX}"

echo "==> Fetching"
git fetch origin

if ! git rev-parse --verify "origin/${RC_BRANCH}" >/dev/null 2>&1; then
  echo "Error: release candidate origin/${RC_BRANCH} does not exist." >&2
  echo "Cut it first: ./scripts/cut-release-candidate.sh ${DATE_PART}${HOTFIX_PART:+ $HOTFIX_PART}" >&2
  exit 1
fi

echo "==> Creating ${REL_BRANCH} from origin/${RC_BRANCH}"
git checkout -b "$REL_BRANCH" "origin/${RC_BRANCH}"

echo "==> Pushing ${REL_BRANCH} (triggers the prod deploy, pending approval)"
git push -u origin "$REL_BRANCH"

cat <<MSG

Release ${REL_BRANCH} pushed.
  The prod deploy is queued and waits for a reviewer on the \`production\`
  GitHub environment. Approve it in the Actions run to proceed.

  Remember to merge ${RC_BRANCH} back into master and develop.
MSG
