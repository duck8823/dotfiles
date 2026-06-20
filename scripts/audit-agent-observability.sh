#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
audit-agent-observability.sh

Collect Traceary / Claude / Antigravity / Codex hook status into a local audit bundle.

Usage:
  audit-agent-observability.sh [--out-dir PATH]

Notes:
  - This script only reads local config and writes the audit bundle.
  - In sandboxed runtimes, Traceary SQLite access may fail; the failure is recorded
    instead of hidden.
  - Traceary v0.21 can diagnose Antigravity capability, but Antigravity hooks are
    not queried because there is no supported hooks print surface yet.
USAGE
}

out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --out-dir)
      out_dir="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$out_dir" ]; then
  base_tmp="${TMPDIR:-/private/tmp}"
  out_dir="${base_tmp%/}/agent-observability-audit-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$out_dir"

summary="$out_dir/summary.md"

run_capture() {
  local label="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3
  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  local code=$?
  set -e
  printf '%s\t%s\t%s\t%s\n' "$label" "$code" "$stdout_file" "$stderr_file" >> "$out_dir/commands.tsv"
  return 0
}

record_skip() {
  local label="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local message="$4"
  printf '%s\n' "$message" > "$stdout_file"
  : > "$stderr_file"
  printf '%s\t%s\t%s\t%s\n' "$label" "0" "$stdout_file" "$stderr_file" >> "$out_dir/commands.tsv"
}

: > "$out_dir/commands.tsv"

if command -v traceary >/dev/null 2>&1; then
  run_capture "traceary version" "$out_dir/traceary-version.txt" "$out_dir/traceary-version.err" traceary --version
  for client in claude gemini codex antigravity; do
    run_capture "traceary doctor $client" "$out_dir/traceary-doctor-$client.json" "$out_dir/traceary-doctor-$client.err" traceary doctor --client "$client" --json
    if [ "$client" = "antigravity" ]; then
      record_skip "traceary hooks $client" "$out_dir/traceary-hooks-$client.txt" "$out_dir/traceary-hooks-$client.err" "skipped: Traceary currently exposes Antigravity capability via doctor; hooks print is intentionally unsupported until a public Antigravity hook contract exists."
    else
      run_capture "traceary hooks $client" "$out_dir/traceary-hooks-$client.txt" "$out_dir/traceary-hooks-$client.err" traceary hooks print --client "$client"
    fi
  done
else
  echo "traceary not found" > "$out_dir/traceary-version.err"
  printf '%s\t%s\t%s\t%s\n' "traceary version" "127" "$out_dir/traceary-version.txt" "$out_dir/traceary-version.err" >> "$out_dir/commands.tsv"
fi

if command -v agy >/dev/null 2>&1; then
  run_capture "agy version" "$out_dir/agy-version.txt" "$out_dir/agy-version.err" agy --version
  run_capture "agy plugin list" "$out_dir/agy-plugin-list.txt" "$out_dir/agy-plugin-list.err" agy plugin list
else
  echo "agy not found" > "$out_dir/agy-version.err"
  printf '%s\t%s\t%s\t%s\n' "agy version" "127" "$out_dir/agy-version.txt" "$out_dir/agy-version.err" >> "$out_dir/commands.tsv"
fi

for file in "$HOME/.claude/settings.json" "$HOME/.gemini/antigravity-cli/settings.json"; do
  name="$(basename "$(dirname "$file")")-$(basename "$file")"
  if [ -f "$file" ]; then
    run_capture "json validate $file" "$out_dir/$name.validate.txt" "$out_dir/$name.validate.err" python3 -m json.tool "$file"
  else
    echo "missing: $file" > "$out_dir/$name.validate.err"
    printf '%s\t%s\t%s\t%s\n' "json validate $file" "66" "$out_dir/$name.validate.txt" "$out_dir/$name.validate.err" >> "$out_dir/commands.tsv"
  fi
done

{
  echo "# Agent observability audit"
  echo
  echo "- out_dir: $out_dir"
  echo "- generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Commands"
  echo
  echo "| label | exit | stdout | stderr |"
  echo "|---|---:|---|---|"
  while IFS=$'\t' read -r label code stdout_file stderr_file; do
    printf '| %s | %s | `%s` | `%s` |\n' "$label" "$code" "$stdout_file" "$stderr_file"
  done < "$out_dir/commands.tsv"
  echo
  echo "## Interpretation"
  echo
  echo "- exit 0: local config / hook status command succeeded."
  echo "- non-zero traceary doctor in sandbox is often SQLite / permission related; rerun outside sandbox before changing dotfiles."
  echo "- Antigravity hooks are reported through doctor only until Traceary and Antigravity have a public hook contract."
  echo "- memory activation warnings with 0 accepted memories are review items, not automatic failures."
} > "$summary"

echo "$summary"
