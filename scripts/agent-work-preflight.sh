#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
agent-work-preflight.sh --repo PATH --branch NAME [--writable-root PATH ...]

Preflight checks for autonomous agent work:
- branch prefix / leaf collisions before `git switch -c`
- whether git writes are likely outside the configured writable roots

Environment:
  AI_AGENT_WRITABLE_ROOTS  Colon-separated writable roots. If omitted, the
                           sandbox write check is reported as unknown.
USAGE
}

repo=""
branch=""
declare -a writable_roots=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --branch)
      branch="${2:-}"
      shift 2
      ;;
    --writable-root)
      writable_roots+=("${2:-}")
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

if [ -z "$repo" ] || [ -z "$branch" ]; then
  usage >&2
  exit 64
fi

if [ ! -d "$repo" ]; then
  echo "repo not found: $repo" >&2
  exit 66
fi

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "not a git repository: $repo" >&2
  exit 65
fi

if [ "${#writable_roots[@]}" -eq 0 ] && [ -n "${AI_AGENT_WRITABLE_ROOTS:-}" ]; then
  IFS=':' read -r -a writable_roots <<< "$AI_AGENT_WRITABLE_ROOTS"
fi

repo_abs="$(cd "$repo" && pwd -P)"

branch_status="available"
collision_detail=""
suggested_branch=""

if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" ||
  git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  branch_status="exists"
  collision_detail="branch already exists: $branch"
else
  IFS='/' read -r -a branch_parts <<< "$branch"
  prefix=""
  if [ "${#branch_parts[@]}" -gt 1 ]; then
    for ((i = 0; i < ${#branch_parts[@]} - 1; i++)); do
      if [ -z "$prefix" ]; then
        prefix="${branch_parts[$i]}"
      else
        prefix="$prefix/${branch_parts[$i]}"
      fi
      if git -C "$repo" show-ref --verify --quiet "refs/heads/$prefix" ||
        git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$prefix"; then
        branch_status="prefix_collision"
        collision_detail="existing branch blocks prefix '$prefix' for '$branch'"
        break
      fi
    done
  fi
  if [ "$branch_status" = "available" ] &&
    git -C "$repo" for-each-ref --format='%(refname)' "refs/heads/$branch/*" "refs/remotes/origin/$branch/*" | grep -q .; then
    branch_status="leaf_collision"
    collision_detail="existing branch below '$branch/' blocks leaf branch '$branch'"
  fi
fi

writable_status="unknown"
if [ "${#writable_roots[@]}" -gt 0 ]; then
  roots_joined="$(printf '%s\n' "${writable_roots[@]}")"
  writable_status="$(
    ROOTS="$roots_joined" REPO_ABS="$repo_abs" python3 - <<'PY'
import os
from pathlib import Path

repo = Path(os.environ["REPO_ABS"]).resolve()
roots = [Path(p).expanduser().resolve() for p in os.environ["ROOTS"].splitlines() if p]
print("inside" if any(repo == root or root in repo.parents for root in roots) else "outside")
PY
  )"
fi

echo "# Agent work preflight"
echo
echo "- repo: $repo_abs"
echo "- branch: $branch"
echo "- branch_status: $branch_status"
if [ -n "$collision_detail" ]; then
  echo "- collision_detail: $collision_detail"
  case "$branch_status" in
    exists)
      suggested_branch="$(printf '%s' "$branch" | tr '/' '-')-2"
      ;;
    *)
      suggested_branch="$(printf '%s' "$branch" | tr '/' '-')"
      ;;
  esac
  echo "- suggested_branch: $suggested_branch"
fi
case "$writable_status" in
  inside)
    echo "- git_write_requires_escalation: false"
    ;;
  outside)
    echo "- git_write_requires_escalation: true"
    echo "- reason: repo is outside AI_AGENT_WRITABLE_ROOTS / --writable-root"
    ;;
  *)
    echo "- git_write_requires_escalation: unknown"
    echo "- reason: no writable roots were provided"
    ;;
esac

case "$branch_status" in
  available) exit 0 ;;
  exists) exit 3 ;;
  *) exit 2 ;;
esac
