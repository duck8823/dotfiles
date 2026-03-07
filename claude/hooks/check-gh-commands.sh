#!/bin/bash
# Claude Code PreToolUse hook: GitHub CLIコマンドの危険パターンをチェック

input=$(cat)
command=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null || echo "")

# AIアカウントをGitHubコラボレーター/レビュアーとして追加しようとしている場合はブロック
if echo "$command" | grep -qE 'gh api.*(collaborators|PUT.*reviewers)'; then
    echo "🚫 [hook] AIアカウントをGitHubコラボレーター/レビュアーとして追加しないでください。" >&2
    echo "   代わりに 'gh pr comment' でレビュー結果を投稿してください。" >&2
    exit 2
fi

# gh pr review が使われている場合は代替手段を案内（ブロックはしない）
if echo "$command" | grep -qE '^gh pr review\b'; then
    echo "⚠️  [hook] 'gh pr review' は権限フックでブロックされる可能性があります。" >&2
    echo "   ブロックされた場合は 'gh pr comment' に切り替えてください。" >&2
fi

exit 0
