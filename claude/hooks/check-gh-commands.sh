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
    # merge コマンドの引数を解析（対象指定と -R フラグを抽出）
    # shlex.split をコマンド全体に適用し、クォート内のメタ文字を正しく処理する
    merge_info=$(echo "$command" | python3 -c "
import sys, shlex
cmd = sys.stdin.read().strip()
try:
    tokens = shlex.split(cmd)
except ValueError:
    tokens = cmd.split()
# gh pr merge の最後の出現位置を使用（前段コマンドの引数に含まれるケースを回避）
merge_idx = -1
for i in range(len(tokens) - 2):
    if tokens[i] == 'gh' and tokens[i+1] == 'pr' and tokens[i+2] == 'merge':
        merge_idx = i + 3
if merge_idx < 0:
    print('\t'); sys.exit(0)
flags_with_value = {'-R', '--repo', '-t', '--subject', '-b', '--body', '-F', '--body-file', '--match-head-commit', '--author'}
shell_operators = {';', '&', '|', '&&', '||', ';;'}
repo = ''
target = ''
skip_next = False
for j in range(merge_idx, len(tokens)):
    tok = tokens[j]
    if tok in shell_operators:
        break
    if skip_next:
        skip_next = False
        continue
    if '=' in tok and tok.startswith('-'):
        flag_name = tok.split('=', 1)[0]
        if flag_name in ('-R', '--repo'):
            repo = tok.split('=', 1)[1]
        continue
    if tok in ('-R', '--repo'):
        if j + 1 < len(tokens):
            repo = tokens[j + 1]
            skip_next = True
        continue
    if tok in flags_with_value:
        skip_next = True
        continue
    if tok.startswith('-'):
        continue
    if not target:
        target = tok
print(target + '\t' + repo)
" 2>/dev/null) || {
        echo "🚫 [hook] コマンド解析に失敗しました。python3 が必要です。" >&2
        exit 2
    }

    merge_target=$(printf '%s' "$merge_info" | cut -f1)
    repo_flag=$(printf '%s' "$merge_info" | cut -f2)

    # gh pr view で PR 番号と URL を解決（数値/URL/branch/省略すべてに対応）
    view_args=()
    [ -n "$merge_target" ] && view_args+=("$merge_target")
    [ -n "$repo_flag" ] && view_args+=("-R" "$repo_flag")

    pr_info=$(gh pr view "${view_args[@]}" --json number,url \
      -q '"\(.number)\t\(.url)"' 2>/dev/null || true)

    if [ -z "$pr_info" ]; then
        echo "🚫 [hook] マージ対象のPRが見つかりません。" >&2
        exit 2
    fi

    pr_number=$(echo "$pr_info" | cut -f1)
    pr_url=$(echo "$pr_info" | cut -f2)
    repo=$(echo "$pr_url" | sed -nE 's|https://github\.com/([^/]+/[^/]+)/pull/[0-9]+|\1|p')

    if [ -z "$pr_number" ] || [ -z "$repo" ]; then
        echo "🚫 [hook] PR情報の解決に失敗しました。ネットワーク接続と gh auth を確認してください。" >&2
        exit 2
    fi

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

# git tag / git push --tags / gh release create はユーザー確認なしで実行させない
if echo "$command" | grep -qE '(^|[;&|])\s*git\s+tag\b'; then
    echo "🚫 [hook] 'git tag' を直接実行しないでください。" >&2
    echo "   リリースタグはユーザーの明示的な承認を得てから作成してください。" >&2
    exit 2
fi

if echo "$command" | grep -qE '(^|[;&|])\s*git\s+push\b.*--tags'; then
    echo "🚫 [hook] 'git push --tags' を直接実行しないでください。" >&2
    echo "   リリースタグはユーザーの明示的な承認を得てから push してください。" >&2
    exit 2
fi

if echo "$command" | grep -qE '(^|[;&|])\s*gh\s+release\s+create\b'; then
    echo "🚫 [hook] 'gh release create' を直接実行しないでください。" >&2
    echo "   リリースはユーザーの明示的な承認を得てから作成してください。" >&2
    exit 2
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
