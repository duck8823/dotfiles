#!/bin/bash
# Claude Code PreToolUse hook: 外部 AI (Codex/Gemini) の write タスクが main worktree で実行されることを防止

input=$(cat)
command=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null || echo "")

# local agent policy（任意）を読む。shell として source せず、許可 key だけを扱う。
load_disabled_engines() {
    local file="${AI_AGENT_POLICY_FILE:-}"
    if [ -z "$file" ] && [ -n "${HOME:-}" ]; then
        file="$HOME/.config/ai-agent-policy.env"
    fi
    local value="${MULTI_AI_DISABLED_ENGINES:-}"
    if [ -f "$file" ]; then
        local line key raw
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            case "$line" in
                ""|\#*) continue ;;
            esac
            key="${line%%=*}"
            raw="${line#*=}"
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            if [ "$key" = "MULTI_AI_DISABLED_ENGINES" ]; then
                raw="${raw#"${raw%%[![:space:]]*}"}"
                raw="${raw%"${raw##*[![:space:]]}"}"
                raw="${raw%\"}"
                raw="${raw#\"}"
                raw="${raw%\'}"
                raw="${raw#\'}"
                value="$raw"
            fi
        done < "$file"
    fi
    printf '%s' "$value"
}

is_disabled_engine() {
    local needle="$1"
    local disabled item
    disabled="$(load_disabled_engines)"
    IFS=',' read -r -a disabled_array <<< "$disabled"
    for item in "${disabled_array[@]}"; do
        item="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# codex exec または gemini コマンドかチェック
is_codex_write=false
is_gemini_write=false
is_codex_command=false
is_gemini_command=false

# コマンド先頭が codex exec かチェック（空白バリエーション対応）
if echo "$command" | grep -qE '(^|[;&|])\s*codex\s+exec\b'; then
    is_codex_command=true
    is_codex_write=true
fi

# コマンド先頭が gemini で --approval-mode plan 以外（= write モード）をチェック
if echo "$command" | grep -qE '(^|[;&|])\s*gemini\b'; then
    is_gemini_command=true
    if ! echo "$command" | grep -qE '\-\-approval-mode\s+plan'; then
        is_gemini_write=true
    fi
fi

if [ "$is_codex_command" = true ] && is_disabled_engine "codex"; then
    echo "🚫 [hook] Codex は local agent policy で無効化されています。" >&2
    echo "   MULTI_AI_DISABLED_ENGINES から codex を外すか、別 reviewer / local verification を使ってください。" >&2
    exit 2
fi

if [ "$is_gemini_command" = true ] && is_disabled_engine "gemini"; then
    echo "🚫 [hook] Gemini は local agent policy で無効化されています。" >&2
    echo "   MULTI_AI_DISABLED_ENGINES から gemini を外すか、Codex / Claude / local verification で代替してください。" >&2
    exit 2
fi

if [ "$is_codex_write" = false ] && [ "$is_gemini_write" = false ]; then
    exit 0
fi

# 現在のブランチが main/master の場合はブロック
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ]; then
    tool_name="Codex"
    [ "$is_gemini_write" = true ] && tool_name="Gemini"

    echo "🚫 [hook] ${tool_name} の write タスクを main ブランチで実行しないでください。" >&2
    echo "   先に 'git worktree add' で worktree を作成するか、" >&2
    echo "   Claude Agent の 'isolation: worktree' を使ってください。" >&2
    echo "" >&2
    echo "   例: git worktree add .codex-work/<task> -b <branch-name>" >&2
    echo "       cd .codex-work/<task>" >&2
    echo "       codex exec / gemini ..." >&2
    exit 2
fi

exit 0
