#!/bin/bash
# Claude Code PreToolUse hook: 外部 AI (Codex/Antigravity/Gemini legacy) の write タスクが main worktree で実行されることを防止

input=$(cat)
command=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# local agent policy（任意）を読む。shell として source せず、許可 key だけを扱う。
source_agent_policy_lib() {
    local hook_dir candidate
    hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for candidate in \
        "$hook_dir/lib/agent-policy.sh" \
        "$hook_dir/../../scripts/lib/agent-policy.sh" \
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

is_codex_write=false
is_antigravity_write=false
is_gemini_write=false
is_codex_command=false
is_antigravity_command=false
is_gemini_command=false

# コマンド先頭が codex exec かチェック（空白バリエーション対応）
if echo "$command" | grep -qE '(^|[;&|])\s*codex\s+exec\b'; then
    is_codex_command=true
    # read-only sandbox/scout は main 上でも許可する。
    if ! echo "$command" | grep -qE '(^|[[:space:]])(-s|--sandbox)(=|[[:space:]])read-only([[:space:]]|$)'; then
        is_codex_write=true
    fi
fi

# Antigravity (`agy`) は raw shell command では headless scout の `--print --sandbox` だけを read-heavy とみなし、それ以外は write-capable として扱う。
# sandbox が auth を隠す場合の no-sandbox authenticated transport retry は、
# `multi-ai-research.sh` / review runner が empty cwd・NO_BROWSER・no --add-dir・同一 prompt で内部実行し、status に記録する。
if echo "$command" | grep -qE '(^|[;&|])\s*agy\b'; then
    is_antigravity_command=true
    if ! echo "$command" | grep -qE '(^|[[:space:]])--print([[:space:]]|$)' || \
       ! echo "$command" | grep -qE '(^|[[:space:]])--sandbox([[:space:]]|$)'; then
        is_antigravity_write=true
    fi
fi

# legacy Gemini は明示 engine として残す。--approval-mode plan 以外を write モードとして扱う。
if echo "$command" | grep -qE '(^|[;&|])\s*gemini\b'; then
    is_gemini_command=true
    if ! echo "$command" | grep -qE '\-\-approval-mode(=|[[:space:]])plan([[:space:]]|$)'; then
        is_gemini_write=true
    fi
fi

if [ "$is_antigravity_command" = true ] && agent_policy_is_disabled "antigravity"; then
    echo "🚫 [hook] Antigravity は local agent policy で無効化されています。" >&2
    echo "   MULTI_AI_DISABLED_ENGINES から antigravity を外すか、Codex / Claude / local verification で代替してください。" >&2
    exit 2
fi

if [ "$is_gemini_command" = true ] && agent_policy_is_disabled "gemini"; then
    echo "🚫 [hook] Gemini legacy engine は local agent policy で無効化されています。" >&2
    echo "   MULTI_AI_DISABLED_ENGINES から gemini を外すか、Codex / Claude / local verification で代替してください。" >&2
    exit 2
fi

if [ "$is_antigravity_write" = true ]; then
    antigravity_allow_write="${MULTI_AI_ANTIGRAVITY_ALLOW_WRITE:-false}"
    if [ "$antigravity_allow_write" != "true" ]; then
        echo "🚫 [hook] Antigravity write は local agent policy で明示許可されていません。" >&2
        echo "   書き込みを許可する場合は dedicated branch/worktree で MULTI_AI_ANTIGRAVITY_ALLOW_WRITE=true を設定してください。" >&2
        exit 2
    fi
fi

if [ "$is_gemini_write" = true ]; then
    gemini_allow_write="${MULTI_AI_GEMINI_ALLOW_WRITE:-false}"
    if [ "$gemini_allow_write" != "true" ]; then
        echo "🚫 [hook] Gemini write は local agent policy で明示許可されていません。" >&2
        echo "   書き込みを許可する場合は dedicated branch/worktree で MULTI_AI_GEMINI_ALLOW_WRITE=true を設定してください。" >&2
        exit 2
    fi
fi

if [ "$is_codex_write" = false ] && [ "$is_antigravity_write" = false ] && [ "$is_gemini_write" = false ]; then
    exit 0
fi

# 現在のブランチが main/master の場合はブロック
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ]; then
    tool_name="Codex"
    [ "$is_antigravity_write" = true ] && tool_name="Antigravity"
    [ "$is_gemini_write" = true ] && tool_name="Gemini"

    echo "🚫 [hook] ${tool_name} の write タスクを main ブランチで実行しないでください。" >&2
    echo "   先に 'git worktree add' で worktree を作成するか、" >&2
    echo "   Claude Agent の 'isolation: worktree' を使ってください。" >&2
    echo "" >&2
    echo "   例: git worktree add .codex-work/<task> -b <branch-name>" >&2
    echo "       cd .codex-work/<task>" >&2
    echo "       codex exec / agy ..." >&2
    exit 2
fi

exit 0
