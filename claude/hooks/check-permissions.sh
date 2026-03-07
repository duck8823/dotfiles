#!/bin/bash
# Claude Code PreToolUse hook: セッション最初のBash実行時にghパーミッションをチェック

FLAG_FILE="/tmp/.claude-permissions-checked-$$"

# すでにチェック済みならスキップ
if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

input=$(cat)
command=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null || echo "")

# ghコマンドを含む場合のみチェック
if echo "$command" | grep -qE '^gh\b'; then
    touch "$FLAG_FILE"

    # gh auth status でトークンスコープを確認
    auth_result=$(gh auth status 2>&1)
    if [ $? -ne 0 ]; then
        echo "⚠️  [hook] gh CLIの認証に問題があります。'gh auth login' でログインしてください。" >&2
        echo "$auth_result" >&2
    fi
fi

exit 0
