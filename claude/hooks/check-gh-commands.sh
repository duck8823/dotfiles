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

# gh pr create で --draft / -d がない場合はブロック
if echo "$command" | grep -qE '(^|[;&|])\s*gh\s+pr\s+create\b' && ! echo "$command" | grep -qE '(\s|^)(-d|--draft)(\s|$)'; then
    echo "🚫 [hook] 'gh pr create' には必ず '--draft' を付けてください。" >&2
    echo "   PR はドラフトで作成し、レビュー完了後に 'gh pr ready' で公開してください。" >&2
    exit 2
fi

# gh pr merge 実行前にレビューコメント（🤖 AI コードレビュー結果）が存在するか確認
if echo "$command" | grep -qE '(^|[;&|])\s*gh\s+pr\s+merge\b'; then
    pr_number=$(echo "$command" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | awk '{print $NF}')

    # PR番号が省略された場合、現在のブランチのPR番号を取得
    if [ -z "$pr_number" ]; then
        pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)
        if [ -z "$pr_number" ]; then
            echo "🚫 [hook] 現在のブランチに紐づくPRが見つかりません。PR番号を指定してください。" >&2
            exit 2
        fi
    fi

    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    if [ -n "$repo" ]; then
        review_body=$(gh api "repos/$repo/issues/$pr_number/comments" --jq '.[].body' 2>/dev/null || true)
        has_review=$(echo "$review_body" | grep -c '🤖 AI コードレビュー結果' || true)
        if [ "$has_review" = "0" ]; then
            echo "🚫 [hook] PR #$pr_number にレビューコメント（🤖 AI コードレビュー結果）がありません。" >&2
            echo "   レビューを実施してからマージしてください。" >&2
            exit 2
        fi
        has_multi_ai=$(echo "$review_body" | grep -cE 'Gemini|Codex' || true)
        if [ "$has_multi_ai" = "0" ]; then
            echo "🚫 [hook] PR #$pr_number に Multi-AI レビュー（Gemini または Codex）がありません。" >&2
            echo "   Claude 単独レビューではマージできません。Gemini scout または Codex verifier のレビューを実施してください。" >&2
            exit 2
        fi
    fi
fi

# コミットメッセージにレビュー起点の文言が含まれていないかチェック
if echo "$command" | grep -qE '(^|[;&|])\s*git\s+commit\b'; then
    if echo "$command" | grep -qiE 'レビュー指摘|レビュー対応|レビュー修正|review fix'; then
        echo "🚫 [hook] コミットメッセージにレビュー起点の文言（レビュー指摘対応等）が含まれています。" >&2
        echo "   「何を・なぜ変えたか」でメッセージを書き直してください。" >&2
        exit 2
    fi
fi

exit 0
