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

# codex exec または gemini（plan 以外）コマンドかチェック
is_codex_write=false
is_gemini_write=false

# コマンド先頭が codex exec かチェック（空白バリエーション対応）
if echo "$command" | grep -qE '(^|[;&|])\s*codex\s+exec\b'; then
    is_codex_write=true
fi

# コマンド先頭が gemini で --approval-mode plan 以外（= write モード）をチェック
if echo "$command" | grep -qE '(^|[;&|])\s*gemini\b' && ! echo "$command" | grep -qE '\-\-approval-mode\s+plan'; then
    is_gemini_write=true
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
