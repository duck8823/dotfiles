#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
multi-ai-research.sh

Run Claude / Gemini / Codex as safe headless research partners and write a status bundle.

Usage:
  multi-ai-research.sh --topic "research topic" [options]
  multi-ai-research.sh --prompt-file prompt.md [options]

Options:
  --topic TEXT              Research topic. Required unless --prompt-file is set.
  --prompt-file PATH        Prompt body to send.
  --packet PATH             Reviewed/sanitized context packet to append.
  --engines LIST            Comma-separated engines: claude,gemini,codex (default: MULTI_AI_ENGINES or claude,gemini,codex)
  --out-dir PATH            Output directory (default: /private/tmp/multi-ai-research-<timestamp>)
  --mode MODE               auto|workspace|packet|general (default: auto)
  --workspace-root PATH     Workspace root for --mode workspace/auto (default: current directory)
  --base-ref REF            Base ref for workspace diff (default: origin/main if present, else main)
  --source-extensions LIST  Comma-separated text/source extensions to include in workspace packets
  --max-file-bytes N        Max bytes per source file in workspace packet (default: MULTI_AI_MAX_FILE_BYTES or 25000)
  --max-total-bytes N       Max total source bytes in workspace packet (default: MULTI_AI_MAX_TOTAL_BYTES or 600000)
  --dry-run                 Write prompts/status plan but do not call external CLIs.
  --timeout SECONDS         Per-engine timeout when timeout/gtimeout exists (default: 600)
  -h, --help                Show this help.

Safety modes:
  auto       If run inside a git repository, build and share one sanitized workspace packet; otherwise general.
  workspace  Build one sanitized workspace packet and share the same reviewed packet identity with every engine.
  packet     Append only the explicit --packet file. Caller is responsible for policy review/redaction.
  general    Do not include local repository context. Use only for non-repository general research.

Local policy:
  This script reads ~/.config/ai-agent-policy.env or AI_AGENT_POLICY_FILE when present.
  Supported keys: MULTI_AI_ENGINES, MULTI_AI_DISABLED_ENGINES,
  MULTI_AI_GEMINI_APPROVAL_MODE, MULTI_AI_GEMINI_SKIP_TRUST,
  MULTI_AI_CODEX_SANDBOX, MULTI_AI_CODEX_MODEL, MULTI_AI_CODEX_REASONING_EFFORT,
  MULTI_AI_GEMINI_MODEL, MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT,
  MULTI_AI_MAX_FILE_BYTES, MULTI_AI_MAX_TOTAL_BYTES,
  MULTI_AI_CLAUDE_PERMISSION_MODE, MULTI_AI_TIMEOUT_SECONDS,
  MULTI_AI_ALLOW_UNSAFE_RESEARCH_MODES.
USAGE
}

source_agent_policy_lib() {
  local script_dir candidate
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for candidate in \
    "$script_dir/lib/agent-policy.sh" \
    "$script_dir/../lib/dotfiles/agent-policy.sh" \
    "${HOME:-}/.local/lib/dotfiles/agent-policy.sh"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      # shellcheck source=/dev/null
      . "$candidate"
      return 0
    fi
  done
  echo "agent policy library not found" >&2
  return 1
}

source_agent_policy_lib
agent_policy_load

topic=""
prompt_file=""
packet_file=""
engines="${MULTI_AI_ENGINES:-claude,gemini,codex}"
mode="auto"
dry_run=false
timeout_seconds="${MULTI_AI_TIMEOUT_SECONDS:-600}"
out_dir=""
workspace_root="$(pwd)"
base_ref=""
source_extensions="md,markdown,sh,bash,zsh,toml,json,yml,yaml,go,py,ts,tsx,js,jsx,dart,rs,java,kt,swift,rb,php,css,scss,html,sql,graphql,proto,txt,rules,ghostty"
max_file_bytes="${MULTI_AI_MAX_FILE_BYTES:-25000}"
max_total_bytes="${MULTI_AI_MAX_TOTAL_BYTES:-600000}"
disabled_engines="${MULTI_AI_DISABLED_ENGINES:-}"
gemini_approval_mode="${MULTI_AI_GEMINI_APPROVAL_MODE:-plan}"
gemini_skip_trust="${MULTI_AI_GEMINI_SKIP_TRUST:-true}"
codex_sandbox="${MULTI_AI_CODEX_SANDBOX:-read-only}"
codex_model="${MULTI_AI_CODEX_MODEL:-}"
codex_reasoning_effort="${MULTI_AI_CODEX_REASONING_EFFORT:-medium}"
gemini_model="${MULTI_AI_GEMINI_MODEL:-}"
tool_output_token_limit="${MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT:-12000}"
claude_permission_mode="${MULTI_AI_CLAUDE_PERMISSION_MODE:-plan}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --topic)
      topic="${2:-}"
      shift 2
      ;;
    --prompt-file)
      prompt_file="${2:-}"
      shift 2
      ;;
    --packet)
      packet_file="${2:-}"
      shift 2
      ;;
    --engines)
      engines="${2:-}"
      shift 2
      ;;
    --out-dir)
      out_dir="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --workspace-root)
      workspace_root="${2:-}"
      shift 2
      ;;
    --base-ref)
      base_ref="${2:-}"
      shift 2
      ;;
    --source-extensions)
      source_extensions="${2:-}"
      shift 2
      ;;
    --max-file-bytes)
      max_file_bytes="${2:-50000}"
      shift 2
      ;;
    --max-total-bytes)
      max_total_bytes="${2:-1500000}"
      shift 2
      ;;
    --timeout)
      timeout_seconds="${2:-600}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
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

if ! [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: invalid MULTI_AI_TIMEOUT_SECONDS=${timeout_seconds}; falling back to 600" >&2
  timeout_seconds=600
fi
if ! [[ "$max_file_bytes" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: invalid max_file_bytes=${max_file_bytes}; falling back to 25000" >&2
  max_file_bytes=25000
fi
if ! [[ "$max_total_bytes" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: invalid max_total_bytes=${max_total_bytes}; falling back to 600000" >&2
  max_total_bytes=600000
fi
if ! [[ "$tool_output_token_limit" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: invalid MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT=${tool_output_token_limit}; falling back to 12000" >&2
  tool_output_token_limit=12000
fi
case "$codex_reasoning_effort" in
  minimal|low|medium|high|xhigh) ;;
  *)
    echo "WARN: invalid MULTI_AI_CODEX_REASONING_EFFORT=${codex_reasoning_effort}; falling back to medium" >&2
    codex_reasoning_effort=medium
    ;;
esac

unsafe_research_modes="${MULTI_AI_ALLOW_UNSAFE_RESEARCH_MODES:-false}"
if [ "$unsafe_research_modes" != "true" ]; then
  if [ "$gemini_approval_mode" != "plan" ]; then
    echo "WARN: multi-ai-research forces Gemini approval mode to plan; set MULTI_AI_ALLOW_UNSAFE_RESEARCH_MODES=true only in a scoped worktree flow" >&2
    gemini_approval_mode="plan"
  fi
  if [ "$codex_sandbox" != "read-only" ]; then
    echo "WARN: multi-ai-research forces Codex sandbox to read-only; set MULTI_AI_ALLOW_UNSAFE_RESEARCH_MODES=true only in a scoped worktree flow" >&2
    codex_sandbox="read-only"
  fi
  if [ "$claude_permission_mode" != "plan" ]; then
    echo "WARN: multi-ai-research forces Claude permission mode to plan; set MULTI_AI_ALLOW_UNSAFE_RESEARCH_MODES=true only in a scoped worktree flow" >&2
    claude_permission_mode="plan"
  fi
fi


if [ -z "$topic" ] && [ -z "$prompt_file" ]; then
  echo "--topic or --prompt-file is required" >&2
  exit 2
fi

case "$mode" in
  auto|workspace|general|packet) ;;
  *)
    echo "--mode must be auto, workspace, general, or packet" >&2
    exit 2
    ;;
esac

if [ "$mode" = "packet" ] && [ -z "$packet_file" ]; then
  echo "--mode packet requires --packet" >&2
  exit 2
fi

if [ -n "$packet_file" ] && [ ! -f "$packet_file" ]; then
  echo "--packet not found: $packet_file" >&2
  exit 2
fi

if [ -n "$prompt_file" ] && [ ! -f "$prompt_file" ]; then
  echo "--prompt-file not found: $prompt_file" >&2
  exit 2
fi

if [ -z "$out_dir" ]; then
  base_tmp="${TMPDIR:-/private/tmp}"
  out_dir="${base_tmp%/}/multi-ai-research-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$out_dir"

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi
  python3 - "$1" <<'PY'
import hashlib, pathlib, sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

build_workspace_packet() {
  local root="$1"
  local output="$2"
  python3 - "$root" "$base_ref" "$source_extensions" "$max_file_bytes" "$max_total_bytes" > "$output" <<'PY'
from __future__ import annotations

import datetime as _dt
import os
import pathlib
import re
import subprocess
import sys

root_arg, base_ref_arg, extensions_arg, max_file_arg, max_total_arg = sys.argv[1:6]
root = pathlib.Path(root_arg).expanduser().resolve()
max_file_bytes = int(max_file_arg)
max_total_bytes = int(max_total_arg)
allowed_ext = {x.strip().lower().lstrip(".") for x in extensions_arg.split(",") if x.strip()}
always_names = {
    "readme", "readme.md", "license", "notice.md", "agents.md", "claude.md",
    "gemini.md", "makefile", "dockerfile", "justfile", ".gitignore",
}

def run_git(args: list[str], check: bool = False) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and proc.returncode != 0:
        raise SystemExit(proc.stderr.strip() or f"git {' '.join(args)} failed")
    return proc.stdout

top = pathlib.Path(run_git(["rev-parse", "--show-toplevel"], check=True).strip()).resolve()
root = top

def git_ok_ref(ref: str) -> bool:
    if not ref:
        return False
    proc = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", ref],
        cwd=root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc.returncode == 0

base_ref = base_ref_arg.strip()
if not base_ref:
    for candidate in ("origin/main", "main", "origin/master", "master"):
        if git_ok_ref(candidate):
            base_ref = candidate
            break

sensitive_path_re = re.compile(
    r"(^|/)(\.env(\..*)?|\.aws/|\.ssh/|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?|"
    r".*\.(pem|key|p12|pfx)|.*secret.*|.*credential.*|"
    r"(token|tokens|.*[._-]tokens?)(\..*)?|.*history|\.DS_Store)$",
    re.IGNORECASE,
)
secret_re = re.compile(
    r"(BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY|"
    r"AKIA[0-9A-Z]{16}|"
    r"gh[pousr]_[A-Za-z0-9_]{30,}|"
    r"xox[baprs]-[A-Za-z0-9-]+|"
    r"AIza[0-9A-Za-z_-]{35}|"
    r"sk-[A-Za-z0-9_-]{20,}|"
    r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|"
    r"Authorization:\s*Bearer\s+\S+)"
)

def mask_remote(remote: str) -> str:
    remote = remote.strip()
    remote = re.sub(r"(https?://)[^/@]+@", r"\1***@", remote)
    return remote

def truncate_text(text: str, max_bytes: int) -> tuple[str, bool]:
    data = text.encode("utf-8", "replace")
    if len(data) <= max_bytes:
        return text, False
    truncated = data[:max_bytes].decode("utf-8", "replace")
    return truncated + f"\n\n[truncated: {len(data) - max_bytes} bytes omitted]\n", True

def fence_lang(path: str) -> str:
    ext = pathlib.Path(path).suffix.lower().lstrip(".")
    return {
        "md": "markdown",
        "markdown": "markdown",
        "sh": "bash",
        "bash": "bash",
        "zsh": "zsh",
        "py": "python",
        "js": "javascript",
        "ts": "typescript",
        "tsx": "tsx",
        "json": "json",
        "toml": "toml",
        "yaml": "yaml",
        "yml": "yaml",
        "go": "go",
        "dart": "dart",
        "rs": "rust",
    }.get(ext, ext or "text")

def safe_code(text: str) -> str:
    return text.replace("```", "`\u200b``")

branch = run_git(["rev-parse", "--abbrev-ref", "HEAD"]).strip()
head = run_git(["rev-parse", "--short", "HEAD"]).strip()
remote = mask_remote(run_git(["remote", "get-url", "origin"]).strip())
status = run_git(["status", "--short"])
diff_stat = run_git(["diff", "--stat", f"{base_ref}...HEAD"]) if base_ref else ""
diff_names = run_git(["diff", "--name-only", f"{base_ref}...HEAD"]) if base_ref else ""
base_diff = run_git(["diff", "--no-ext-diff", "--unified=40", f"{base_ref}...HEAD"]) if base_ref else ""
worktree_diff = run_git(["diff", "--no-ext-diff", "--unified=40", "HEAD"])
staged_diff = run_git(["diff", "--no-ext-diff", "--cached", "--unified=40", "HEAD"])

for label, text in (("base diff", base_diff), ("worktree diff", worktree_diff), ("staged diff", staged_diff)):
    if secret_re.search(text):
        print(f"refusing to build workspace packet: secret-looking content found in {label}", file=sys.stderr)
        raise SystemExit(86)

base_diff, base_diff_truncated = truncate_text(base_diff, 120_000)
worktree_diff, worktree_diff_truncated = truncate_text(worktree_diff, 80_000)
staged_diff, staged_diff_truncated = truncate_text(staged_diff, 80_000)

tracked = run_git(["ls-files", "-co", "--exclude-standard"]).splitlines()
included: list[tuple[str, str, bool]] = []
skipped: list[str] = []
total = 0

for rel in sorted(dict.fromkeys(tracked)):
    rel_path = pathlib.PurePosixPath(rel)
    rel_str = str(rel_path)
    if sensitive_path_re.search(rel_str):
        skipped.append(f"{rel_str} (sensitive path)")
        continue
    abs_path = root / rel_str
    if not abs_path.is_file() or abs_path.is_symlink():
        skipped.append(f"{rel_str} (not regular file)")
        continue
    name = rel_path.name.lower()
    ext = pathlib.Path(rel_str).suffix.lower().lstrip(".")
    try:
        data = abs_path.read_bytes()
    except OSError as exc:
        skipped.append(f"{rel_str} (read error: {exc})")
        continue
    if b"\0" in data:
        skipped.append(f"{rel_str} (binary)")
        continue
    include = ext in allowed_ext or name in always_names
    if not include and data.startswith(b"#!"):
        include = True
    if not include:
        skipped.append(f"{rel_str} (extension not included)")
        continue
    text = data.decode("utf-8", "replace")
    if secret_re.search(text):
        skipped.append(f"{rel_str} (secret-looking content)")
        continue
    original_len = len(data)
    truncated = False
    if original_len > max_file_bytes:
        text = data[:max_file_bytes].decode("utf-8", "replace")
        text += f"\n\n[truncated: {original_len - max_file_bytes} bytes omitted]\n"
        truncated = True
    text_len = len(text.encode("utf-8", "replace"))
    if total + text_len > max_total_bytes:
        skipped.append(f"{rel_str} (total packet byte cap reached)")
        continue
    included.append((rel_str, text, truncated))
    total += text_len

generated_at = _dt.datetime.now(_dt.timezone.utc).isoformat()

print("# Workspace context packet")
print()
print("This packet is intentionally shared unchanged with every external research engine to avoid information asymmetry.")
print("It excludes sensitive paths, binary files, secret-looking content, and files beyond configured size limits.")
print()
print("## Metadata")
print()
print(f"- generated_at_utc: {generated_at}")
print(f"- workspace_root: {root}")
print(f"- remote: {remote or '(none)'}")
print(f"- branch: {branch}")
print(f"- head: {head}")
print(f"- base_ref: {base_ref or '(none)'}")
print(f"- included_source_files: {len(included)}")
print(f"- skipped_files: {len(skipped)}")
print(f"- source_bytes_included: {total}")
print()

def section(title: str, body: str, lang: str = "text") -> None:
    print(f"## {title}")
    print()
    if body.strip():
        print(f"```{lang}")
        print(safe_code(body.rstrip()))
        print("```")
    else:
        print("(empty)")
    print()

section("Git status", status)
section("Changed files against base", diff_names)
section("Diff stat against base", diff_stat)
section("Diff against base", base_diff, "diff")
if base_diff_truncated:
    print("> Diff against base was truncated in this packet.\n")
section("Staged diff", staged_diff, "diff")
if staged_diff_truncated:
    print("> Staged diff was truncated in this packet.\n")
section("Working tree diff", worktree_diff, "diff")
if worktree_diff_truncated:
    print("> Working tree diff was truncated in this packet.\n")

print("## Included source files")
print()
for path, text, truncated in included:
    print(f"### {path}")
    if truncated:
        print()
        print("> File content truncated by max-file-bytes.")
    print()
    print(f"```{fence_lang(path)}")
    print(safe_code(text.rstrip()))
    print("```")
    print()

print("## Skipped files")
print()
if skipped:
    for item in skipped[:500]:
        print(f"- {item}")
    if len(skipped) > 500:
        print(f"- ... {len(skipped) - 500} more")
else:
    print("(none)")
PY
}

mode_effective="$mode"
if [ "$mode_effective" = "auto" ]; then
  if [ -n "$packet_file" ]; then
    mode_effective="packet"
  elif git -C "$workspace_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    mode_effective="workspace"
  else
    mode_effective="general"
  fi
fi

if [ "$mode_effective" = "workspace" ]; then
  packet_file="$out_dir/workspace-context.md"
  build_workspace_packet "$workspace_root" "$packet_file"
elif [ "$mode_effective" = "packet" ] && [ -z "$packet_file" ]; then
  echo "--mode packet requires --packet" >&2
  exit 2
fi

prompt_path="$out_dir/prompt.md"
gemini_prompt_path="$out_dir/prompt.gemini.md"
status_path="$out_dir/status.md"
summary_path="$out_dir/summary.md"

{
  cat <<'PROMPT'
You are a read-only research partner in a multi-AI workflow.

Safety boundary:
- Do not read local files, repositories, shell history, credentials, tokens, `.env*`, or private user data.
- Do not ask for secrets or raw personal / production data.
- If local repository context is needed but not provided in this prompt, say exactly what sanitized packet is needed.
- Prefer official / primary sources. Mark uncertain or secondary-source-only claims.
- Return concise Japanese output with: conclusion, evidence/source URLs, recommended actions, uncertainty.
- Transport note: some engine prompts may escape `@` as `\u0040` to prevent CLI file-reference expansion.
  Treat that as a transport escape only; the reviewed packet identity is the packet_sha256 in status.

PROMPT

  if [ -n "$prompt_file" ]; then
    cat "$prompt_file"
  else
    printf 'Research topic:\n%s\n' "$topic"
  fi

  if [ -n "$packet_file" ]; then
    cat <<'PROMPT'

Reviewed context packet follows. It is intentionally shared unchanged with every engine in this run.
Treat it as the only allowed local/workspace context, and mention if the packet is insufficient.

PROMPT
    cat "$packet_file"
  fi
} > "$prompt_path"

# Gemini CLI expands @file-style references before sending the prompt to the model.
# Workspace packets frequently contain emails, git remotes, examples, and source snippets with "@".
# Transport-escape @ for Gemini only so the reviewed packet is not interpreted as local file paths.
# The original packet path and sha256 remain in status for cross-engine audit.
python3 - "$prompt_path" "$gemini_prompt_path" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
Path(sys.argv[2]).write_text(src.replace("@", r"\u0040"))
PY

run_timeout() {
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_seconds" "$@"
    return
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" "$@"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import subprocess, sys
timeout = int(sys.argv[1])
args = sys.argv[2:]
data = sys.stdin.buffer.read()
try:
    proc = subprocess.run(args, input=data, stdout=sys.stdout.buffer, stderr=sys.stderr.buffer, timeout=timeout)
    raise SystemExit(proc.returncode)
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        sys.stdout.buffer.write(exc.stdout)
    if exc.stderr:
        sys.stderr.buffer.write(exc.stderr)
    sys.stderr.write(f"\nTIMEOUT_AFTER={timeout}\n")
    raise SystemExit(124)
' "$timeout_seconds" "$@"
    return
  fi
  "$@"
}

classify_result() {
  local file="$1"
  if [ ! -s "$file" ]; then
    echo "empty_output"
    return
  fi
  if grep -Eqi 'ENAMETOOLONG|Error stating path|no such file or directory, stat' "$file"; then
    echo "prompt_file_reference_expansion"
    return
  fi
  if grep -Eqi 'not running in a trusted directory|Gemini CLI is not running in a trusted directory|trust this directory in interactive mode|trusted folders/#headless' "$file"; then
    echo "trust_failed"
    return
  fi
  if grep -Eqi 'JavaScript heap out of memory|FATAL ERROR: Ineffective mark-compacts|Allocation failed|heap limit' "$file"; then
    echo "process_oom"
    return
  fi
  if grep -Eqi 'TIMEOUT_AFTER=|timed out' "$file"; then
    echo "timeout"
    return
  fi
  if grep -Eqi 'Opening authentication page|Do you want to continue|authentication page|not authenticated|Please log in|login required' "$file"; then
    echo "auth_prompt"
    return
  fi
  if grep -Eqi '429|QUOTA_EXHAUSTED|RESOURCE_EXHAUSTED|exhausted your capacity|capacity on this model|quota[^[:alnum:]]+reset' "$file"; then
    echo "quota_or_capacity"
    return
  fi
  if grep -Eqi 'Rejected\(|policy_denied|unacceptable risk|permission denied' "$file"; then
    echo "policy_or_permission_denied"
    return
  fi
  if grep -Eqi '(^|[^[:alnum:]_])(claude|gemini|codex)_not_found([^[:alnum:]_]|$)' "$file"; then
    echo "tool_not_found"
    return
  fi
  if grep -Eq '^EXIT_CODE=[1-9][0-9]*' "$file"; then
    echo "command_failed"
    return
  fi
  echo "ok"
}

run_claude() {
  local out="$out_dir/claude.md"
  local err="$out_dir/claude.err"
  if ! command -v claude >/dev/null 2>&1; then
    printf 'EXIT_CODE=127\nclaude_not_found\n' > "$out"
    return 127
  fi
  (
    cd /private/tmp
    run_timeout claude \
      --print \
      --permission-mode "$claude_permission_mode" \
      --tools "WebSearch,WebFetch" \
      --disallowedTools "Read,Glob,Grep,Bash,Edit,MultiEdit,Write,NotebookRead,NotebookEdit" \
      --no-session-persistence \
      --output-format text < "$prompt_path"
  ) >"$out" 2>"$err" || {
    local code=$?
    {
      echo "EXIT_CODE=$code"
      cat "$err"
    } >> "$out"
    return "$code"
  }
  cat "$err" >> "$out"
}

run_gemini() {
  local out="$out_dir/gemini.md"
  local err="$out_dir/gemini.err"
  if ! command -v gemini >/dev/null 2>&1; then
    printf 'EXIT_CODE=127\ngemini_not_found\n' > "$out"
    return 127
  fi
  local gemini_cwd="$out_dir/gemini-cwd"
  mkdir -p "$gemini_cwd"
  (
    cd "$gemini_cwd"
    export TERM=xterm-256color
    export NO_BROWSER=true
    set -- gemini
    case "$(printf '%s' "$gemini_skip_trust" | tr '[:upper:]' '[:lower:]')" in
      true|1|yes|on) set -- "$@" --skip-trust ;;
    esac
    if [ -n "$gemini_model" ]; then
      set -- "$@" --model "$gemini_model"
    fi
    run_timeout "$@" \
      --approval-mode "$gemini_approval_mode" \
      -e none \
      --output-format text \
      -p " " < "$gemini_prompt_path"
  ) >"$out" 2>"$err" || {
    local code=$?
    {
      echo "EXIT_CODE=$code"
      cat "$err"
    } >> "$out"
    return "$code"
  }
  cat "$err" >> "$out"
}

run_codex() {
  local out="$out_dir/codex.md"
  local err="$out_dir/codex.err"
  if ! command -v codex >/dev/null 2>&1; then
    printf 'EXIT_CODE=127\ncodex_not_found\n' > "$out"
    return 127
  fi
  local codex_cwd="$out_dir/codex-cwd"
  mkdir -p "$codex_cwd"
  (
    cd "$codex_cwd"
    set -- codex exec \
      --ephemeral \
      --skip-git-repo-check \
      --sandbox "$codex_sandbox"
    if [ -n "$codex_model" ]; then
      set -- "$@" --model "$codex_model"
    fi
    run_timeout "$@" \
      -c "model_reasoning_effort=\"${codex_reasoning_effort}\"" \
      -c 'model_reasoning_summary="none"' \
      -c "tool_output_token_limit=${tool_output_token_limit}" \
      - < "$prompt_path"
  ) >"$out" 2>"$err" || {
    local code=$?
    {
      echo "EXIT_CODE=$code"
      cat "$err"
    } >> "$out"
    return "$code"
  }
  cat "$err" >> "$out"
}

engines_requested="$engines"
engines_skipped_by_policy="$(agent_policy_csv_disabled_for "$engines_requested")"
engines="$(agent_policy_csv_filter_disabled "$engines_requested")"

{
  echo "# Multi-AI research status"
  echo
  echo "- out_dir: $out_dir"
  echo "- mode_requested: $mode"
  echo "- mode_effective: $mode_effective"
  echo "- engines_requested: $engines_requested"
  echo "- engines_effective: ${engines:-'(none)'}"
  echo "- engines_skipped_by_policy: ${engines_skipped_by_policy:-'(none)'}"
  echo "- policy_file: ${AI_AGENT_POLICY_FILE:-${HOME:-}/.config/ai-agent-policy.env}"
  echo "- gemini_approval_mode: $gemini_approval_mode"
  echo "- gemini_skip_trust: $gemini_skip_trust"
  echo "- gemini_model: ${gemini_model:-'(default routing)'}"
  echo "- codex_sandbox: $codex_sandbox"
  echo "- codex_model: ${codex_model:-'(default config)'}"
  echo "- codex_reasoning_effort: $codex_reasoning_effort"
  echo "- tool_output_token_limit: $tool_output_token_limit"
  echo "- max_file_bytes: $max_file_bytes"
  echo "- max_total_bytes: $max_total_bytes"
  echo "- claude_permission_mode: $claude_permission_mode"
  echo "- prompt: $prompt_path"
  echo "- prompt_sha256: $(sha256_file "$prompt_path")"
  echo "- gemini_prompt: $gemini_prompt_path"
  echo "- gemini_prompt_sha256: $(sha256_file "$gemini_prompt_path")"
  if [ -n "$packet_file" ]; then
    echo "- packet: $packet_file"
    echo "- packet_sha256: $(sha256_file "$packet_file")"
  fi
  echo "- dry_run: $dry_run"
} > "$status_path"

if [ -n "$engines_skipped_by_policy" ]; then
  IFS=',' read -r -a skipped_array <<< "$engines_skipped_by_policy"
  for engine in "${skipped_array[@]}"; do
    engine="$(printf '%s' "$engine" | tr -d '[:space:]')"
    [ -n "$engine" ] || continue
    {
      printf '\n## %s\n' "$engine"
      echo "- exit_code: 0"
      echo "- classification: local_policy_disabled"
      echo "- output: (skipped by local agent policy)"
    } >> "$status_path"
  done
fi

if [ -z "$engines" ]; then
  {
    printf '\n## multi-ai-research\n'
    echo "- exit_code: 75"
    echo "- classification: no_effective_engines"
    echo "- output: no engine remained after local agent policy filtering"
  } >> "$status_path"
  {
    echo "# Multi-AI research bundle"
    echo
    cat "$status_path"
  } > "$summary_path"
  echo "$summary_path"
  if [ "$dry_run" = true ]; then
    exit 0
  fi
  exit 75
fi

IFS=',' read -r -a engine_array <<< "$engines"
for engine in "${engine_array[@]}"; do
  engine="$(printf '%s' "$engine" | tr -d '[:space:]')"
  [ -n "$engine" ] || continue
  if [ "$dry_run" = true ]; then
    printf '\n## %s\n- status: dry_run\n' "$engine" >> "$status_path"
    continue
  fi

  set +e
  case "$engine" in
    claude) run_claude ;;
    gemini) run_gemini ;;
    codex) run_codex ;;
    *)
      echo "unknown engine: $engine" >&2
      printf '\n## %s\n- status: unknown_engine\n' "$engine" >> "$status_path"
      continue
      ;;
  esac
  code=$?
  set -e
  result_file="$out_dir/$engine.md"
  classification="$(classify_result "$result_file")"
  {
    printf '\n## %s\n' "$engine"
    echo "- exit_code: $code"
    echo "- classification: $classification"
    echo "- output: $result_file"
  } >> "$status_path"
done

{
  echo "# Multi-AI research bundle"
  echo
  cat "$status_path"
  for engine in "${engine_array[@]}"; do
    engine="$(printf '%s' "$engine" | tr -d '[:space:]')"
    result_file="$out_dir/$engine.md"
    [ -f "$result_file" ] || continue
    printf '\n---\n\n## %s result\n\n' "$engine"
    cat "$result_file"
    echo
  done
} > "$summary_path"

echo "$summary_path"
