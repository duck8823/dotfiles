#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
validate-codex-config-template.sh [--repo PATH] [--keep]

Render and validate codex/config.toml.template in an isolated temporary
CODEX_HOME. This catches missing instructions.md / invalid TOML before a real
Codex run.
USAGE
}

repo="$(pwd)"
keep=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --keep)
      keep=true
      shift
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

template="$repo/codex/config.toml.template"
instructions="$repo/codex/instructions.md"

if [ ! -f "$template" ]; then
  echo "missing template: $template" >&2
  exit 66
fi
if [ ! -f "$instructions" ]; then
  echo "missing instructions: $instructions" >&2
  exit 66
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-config-check.XXXXXX")"
if [ "$keep" != true ]; then
  trap 'rm -rf "$tmp_root"' EXIT
fi
codex_home="$tmp_root/CODEX_HOME"
mkdir -p "$codex_home"

python3 - "$template" "$codex_home/config.toml" "$HOME" <<'PY'
import sys
from pathlib import Path

template, output, home = map(Path, sys.argv[1:4])
text = template.read_text().replace("{{HOME}}", str(home))
output.write_text(text)
PY
cp "$instructions" "$codex_home/instructions.md"

CODEX_HOME="$codex_home" python3 - <<'PY'
import os
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError as exc:
        raise SystemExit("Python 3.11+ or the tomli package is required to parse TOML") from exc

home = Path(os.environ["CODEX_HOME"])
config_path = home / "config.toml"
config = tomllib.loads(config_path.read_text())
instructions_file = config.get("model_instructions_file", "instructions.md")
instructions_path = home / instructions_file
if not instructions_path.is_file():
    raise SystemExit(f"model_instructions_file not found: {instructions_path}")
if "{{HOME}}" in config_path.read_text():
    raise SystemExit("unexpanded {{HOME}} remains in rendered config")
print("# Codex config template validation")
print(f"- codex_home: {home}")
print(f"- config: {config_path}")
print(f"- instructions: {instructions_path}")
print("- toml: ok")
print("- model_instructions_file: ok")
PY
