#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
render-pr-review-fallback-comment.sh --pr NUMBER --head SHA --classification KIND [options]

Render a PR comment for AI review wait/fallback decisions.

Classifications:
  no_response | timeout | quota_or_capacity | policy_or_permission_denied |
  empty_output | auth_prompt | local_policy_disabled | environment_unavailable

Environment:
  CODEX_REVIEW_POLL_SECONDS  Default wait seconds for @codex review (default: 180)
USAGE
}

pr=""
head_sha=""
classification=""
reviewer="codex"
wait_seconds="${CODEX_REVIEW_POLL_SECONDS:-180}"
evidence_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      pr="${2:-}"
      shift 2
      ;;
    --head)
      head_sha="${2:-}"
      shift 2
      ;;
    --classification)
      classification="${2:-}"
      shift 2
      ;;
    --reviewer)
      reviewer="${2:-}"
      shift 2
      ;;
    --wait-seconds)
      wait_seconds="${2:-}"
      shift 2
      ;;
    --evidence-path)
      evidence_path="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ -z "$pr" ] || [ -z "$head_sha" ] || [ -z "$classification" ]; then
  usage >&2
  exit 64
fi

case "$classification" in
  no_response|timeout|quota_or_capacity|policy_or_permission_denied|empty_output|auth_prompt|local_policy_disabled|environment_unavailable) ;;
  *)
    echo "unsupported classification: $classification" >&2
    exit 64
    ;;
esac

fallback_action="Proceed with local verification / available reviewers; record missing reviewer."
if [ "$classification" = "auth_prompt" ]; then
  fallback_action="Do not fallback. Stop and ask the user to fix CLI authentication."
fi

cat <<COMMENT
## AI review wait / fallback

- PR: #$pr
- head: \`$head_sha\`
- reviewer: $reviewer
- wait_seconds: $wait_seconds
- classification: $classification
- fallback_action: $fallback_action
COMMENT

if [ -n "$evidence_path" ]; then
  echo "- evidence: \`$evidence_path\`"
fi

cat <<'COMMENT'

Notes:
- `auth_prompt` / browser login / interactive login is not fallbackable.
- `no_response`, `timeout`, `quota_or_capacity`, `empty_output`, and `environment_unavailable` may be covered by local verification plus another reviewer when merge gates still pass.
- Re-request review after any new push / force-with-lease.
COMMENT
