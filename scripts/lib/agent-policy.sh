#!/usr/bin/env bash
# Shared local agent policy loader for dotfiles scripts/hooks.
# Bash-only: uses indirect expansion to keep per-run env vars higher
# precedence than the durable policy file.
# This file intentionally does not `source` the policy file. It parses only
# allowlisted KEY=VALUE lines and keeps shell env vars higher precedence than
# the durable policy file.

agent_policy_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

agent_policy_default_file() {
  if [ -n "${AI_AGENT_POLICY_FILE:-}" ]; then
    printf '%s' "$AI_AGENT_POLICY_FILE"
  elif [ -n "${HOME:-}" ]; then
    printf '%s' "$HOME/.config/ai-agent-policy.env"
  fi
}

agent_policy_key_allowed() {
  case "$1" in
    MULTI_AI_ENGINES|MULTI_AI_DISABLED_ENGINES|MULTI_AI_ANTIGRAVITY_CLI|MULTI_AI_ANTIGRAVITY_SANDBOX|MULTI_AI_ANTIGRAVITY_ALLOW_WRITE|MULTI_AI_ANTIGRAVITY_MODEL|MULTI_AI_ANTIGRAVITY_PRINT_TIMEOUT|MULTI_AI_GEMINI_APPROVAL_MODE|MULTI_AI_GEMINI_SKIP_TRUST|MULTI_AI_GEMINI_ALLOW_WRITE|MULTI_AI_GEMINI_MODEL|MULTI_AI_CODEX_SANDBOX|MULTI_AI_CODEX_MODEL|MULTI_AI_CODEX_REASONING_EFFORT|MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT|MULTI_AI_MAX_FILE_BYTES|MULTI_AI_MAX_TOTAL_BYTES|MULTI_AI_CLAUDE_PERMISSION_MODE|MULTI_AI_TIMEOUT_SECONDS|MULTI_AI_ALLOW_UNSAFE_RESEARCH_MODES)
      return 0
      ;;
  esac
  return 1
}

agent_policy_load() {
  local file
  file="$(agent_policy_default_file)"
  [ -n "$file" ] || return 0
  [ -f "$file" ] || return 0

  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(agent_policy_trim "$line")"
    [ -n "$line" ] || continue
    case "$line" in
      \#*) continue ;;
    esac
    [ "${line#*=}" != "$line" ] || continue
    key="$(agent_policy_trim "${line%%=*}")"
    value="$(agent_policy_trim "${line#*=}")"
    agent_policy_key_allowed "$key" || continue

    # Supported format is simple KEY=VALUE. Full shell quoting and inline
    # comments are intentionally not supported; keep policy files boring.
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"

    # Per-run environment wins over the durable policy file.
    if [ -z "${!key+x}" ]; then
      export "$key=$value"
    fi
  done < "$file"
}

agent_policy_csv_contains() {
  local list="$1"
  local needle="$2"
  local item
  local IFS=$' \t\n'
  needle="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  for item in ${list//,/ }; do
    item="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    [ -n "$item" ] || continue
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

agent_policy_is_disabled() {
  agent_policy_csv_contains "${MULTI_AI_DISABLED_ENGINES:-}" "$1"
}

agent_policy_csv_filter_disabled() {
  local list="$1"
  local item kept=""
  local IFS=$' \t\n'
  for item in ${list//,/ }; do
    item="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    [ -n "$item" ] || continue
    if agent_policy_is_disabled "$item"; then
      continue
    fi
    if [ -z "$kept" ]; then
      kept="$item"
    else
      kept="$kept,$item"
    fi
  done
  printf '%s' "$kept"
}

agent_policy_csv_disabled_for() {
  local list="$1"
  local item skipped=""
  local IFS=$' \t\n'
  for item in ${list//,/ }; do
    item="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    [ -n "$item" ] || continue
    if agent_policy_is_disabled "$item"; then
      if [ -z "$skipped" ]; then
        skipped="$item"
      else
        skipped="$skipped,$item"
      fi
    fi
  done
  printf '%s' "$skipped"
}
