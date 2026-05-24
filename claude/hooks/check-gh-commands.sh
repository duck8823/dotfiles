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

extract_gh_pr_target_repo() {
    local subcommand="$1"
    COMMAND="$command" PR_SUBCOMMAND="$subcommand" python3 - <<'PY'
import os, shlex, sys

cmd = os.environ.get("COMMAND", "")
subcommand = os.environ.get("PR_SUBCOMMAND", "")
try:
    tokens = shlex.split(cmd)
except ValueError:
    tokens = cmd.split()

shell_operators = {";", "&", "|", "&&", "||", ";;"}
flags_with_value = {
    "-R", "--repo", "-t", "--title", "-b", "--body", "-F", "--body-file",
    "--template", "--base", "--head", "--assignee", "--reviewer", "--label",
    "--milestone", "--project", "--recover", "--match-head-commit",
    "--author", "--subject",
}

idx = -1
for i in range(len(tokens) - 2):
    if tokens[i] == "gh" and tokens[i + 1] == "pr" and tokens[i + 2] == subcommand:
        idx = i + 3
if idx < 0:
    print("\t")
    sys.exit(0)

repo = ""
target = ""
skip_next = False
for j in range(idx, len(tokens)):
    tok = tokens[j]
    if tok in shell_operators:
        break
    if skip_next:
        skip_next = False
        continue
    if tok.startswith("-") and "=" in tok:
        flag_name, value = tok.split("=", 1)
        if flag_name in ("-R", "--repo"):
            repo = value
        continue
    if tok in ("-R", "--repo"):
        if j + 1 < len(tokens):
            repo = tokens[j + 1]
            skip_next = True
        continue
    if tok in flags_with_value:
        skip_next = True
        continue
    if tok.startswith("-"):
        continue
    if not target:
        target = tok

print(target + "\t" + repo)
PY
}

validate_one_ticket_text() {
    local context="$1"
    local text="$2"
    TICKET_CONTEXT="$context" TICKET_TEXT="$text" python3 - <<'PY'
import os, re

text = os.environ.get("TICKET_TEXT", "")
context = os.environ.get("TICKET_CONTEXT", "")
refs = set()

ticket_prefix = r"(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|issue|issues|ticket|tickets|jira)"

for line in text.splitlines():
    if re.search(ticket_prefix, line, flags=re.IGNORECASE):
        for number in re.findall(r"(?:^|[^\w/-])(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#([0-9]+)\b", line):
            refs.add(f"GH#{number}")

for number in re.findall(r"https://github\.com/[^/\s]+/[^/\s]+/issues/([0-9]+)\b", text):
    refs.add(f"GH#{number}")

for key in re.findall(r"\b[A-Z][A-Z0-9]+-[0-9]+\b", text):
    refs.add(f"JIRA:{key}")

ordered = sorted(refs)
if len(ordered) == 1:
    print("ok\t" + ordered[0])
elif not ordered:
    print("missing\t")
else:
    print("multiple\t" + ",".join(ordered))
PY
}

extract_pr_create_text() {
    COMMAND="$command" python3 - <<'PY'
import os, pathlib, shlex, sys

cmd = os.environ.get("COMMAND", "")
try:
    tokens = shlex.split(cmd)
except ValueError:
    tokens = cmd.split()

shell_operators = {";", "&", "|", "&&", "||", ";;"}
idx = -1
for i in range(len(tokens) - 2):
    if tokens[i] == "gh" and tokens[i + 1] == "pr" and tokens[i + 2] == "create":
        idx = i + 3
if idx < 0:
    sys.exit(0)

title = ""
body = ""
body_file = ""
used_fill = False
skip_next = False
for j in range(idx, len(tokens)):
    tok = tokens[j]
    if tok in shell_operators:
        break
    if skip_next:
        skip_next = False
        continue
    if tok in ("-t", "--title"):
        if j + 1 < len(tokens):
            title = tokens[j + 1]
            skip_next = True
        continue
    if tok.startswith("--title="):
        title = tok.split("=", 1)[1]
        continue
    if tok in ("-b", "--body"):
        if j + 1 < len(tokens):
            body = tokens[j + 1]
            skip_next = True
        continue
    if tok.startswith("--body="):
        body = tok.split("=", 1)[1]
        continue
    if tok in ("-F", "--body-file"):
        if j + 1 < len(tokens):
            body_file = tokens[j + 1]
            skip_next = True
        continue
    if tok.startswith("--body-file="):
        body_file = tok.split("=", 1)[1]
        continue
    if tok.startswith("--fill"):
        used_fill = True

if body_file:
    try:
        body += "\n" + pathlib.Path(body_file).read_text()
    except OSError:
        print("__DOTFILES_BODY_FILE_UNREADABLE__ " + body_file)
        sys.exit(0)

if used_fill and not title and not body:
    print("__DOTFILES_FILL_UNVERIFIABLE__")
    sys.exit(0)

print(title)
print(body)
PY
}

check_commit_message_policy() {
    COMMAND="$command" python3 - <<'PY'
import os, pathlib, re, shlex, sys

cmd = os.environ.get("COMMAND", "")
try:
    tokens = shlex.split(cmd)
except ValueError:
    tokens = cmd.split()

shell_operators = {";", "&", "|", "&&", "||", ";;"}
banned = [
    r"レビュー\s*(指摘|コメント|フィードバック)?\s*(対応|反映|修正|修正対応)",
    r"(指摘|コメント|フィードバック)\s*(対応|反映|修正)",
    r"(codex|gemini|claude)\s*(review|レビュー)\s*(対応|反映|修正|fix|feedback)?",
    r"\b(review|reviewer)\s*(fix|feedback|comment|comments|changes)\b",
    r"\b(address|apply|fix|resolve|handle)[ -]?(review|reviewer)[ -]?(feedback|comments?|changes)\b",
    r"\bfix(?:es|ed)?\s+review\s+comments?\b",
]

def segment_after_git_commit(start: int) -> list[str]:
    segment = []
    for tok in tokens[start:]:
        if tok in shell_operators:
            break
        segment.append(tok)
    return segment

messages = []
for i in range(len(tokens) - 1):
    if tokens[i] != "git" or tokens[i + 1] != "commit":
        continue
    segment = segment_after_git_commit(i + 2)
    skip_next = False
    for j, tok in enumerate(segment):
        if skip_next:
            skip_next = False
            continue
        if tok in ("-m", "--message"):
            if j + 1 < len(segment):
                messages.append(segment[j + 1])
                skip_next = True
            continue
        if tok.startswith("--message="):
            messages.append(tok.split("=", 1)[1])
            continue
        if tok.startswith("-m") and tok != "-m":
            messages.append(tok[2:])
            continue
        if tok in ("-F", "--file"):
            if j + 1 < len(segment):
                try:
                    messages.append(pathlib.Path(segment[j + 1]).read_text())
                except OSError:
                    pass
                skip_next = True
            continue
        if tok.startswith("--file="):
            try:
                messages.append(pathlib.Path(tok.split("=", 1)[1]).read_text())
            except OSError:
                pass

combined = "\n".join(messages)
if not combined:
    print("ok\t")
    sys.exit(0)

for pattern in banned:
    if re.search(pattern, combined, flags=re.IGNORECASE):
        first_line = combined.strip().splitlines()[0] if combined.strip() else ""
        print("blocked\t" + first_line[:200])
        sys.exit(0)

print("ok\t")
PY
}

check_commit_split_policy() {
    if ! echo "$command" | grep -qE '(^|[;&|])\s*git\s+commit\b'; then
        return 0
    fi

    local staged_files
    staged_files=$(git diff --cached --name-only 2>/dev/null || true)
    [ -n "$staged_files" ] || return 0

    local split_result status details
    split_result=$(STAGED_FILES="$staged_files" python3 - <<'PY'
import os

files = [line.strip() for line in os.environ.get("STAGED_FILES", "").splitlines() if line.strip()]

def concern(path: str) -> str:
    parts = path.split("/")
    if not parts:
        return path
    top = parts[0]
    if top in {"claude", "codex", "gemini"}:
        if len(parts) >= 3 and parts[1] == "skills":
            return "/".join(parts[:3])
        if len(parts) >= 2:
            return "/".join(parts[:2])
        return top
    if top == "conventions" and len(parts) >= 2:
        return "/".join(parts[:2])
    if top == "scripts":
        if len(parts) >= 2 and parts[1] == "lib":
            return "scripts/lib"
        return "scripts"
    if top in {"tests", "cmux"}:
        return top
    if top in {"README.md", "install.sh"}:
        return top
    return top

groups = {}
for file in files:
    groups.setdefault(concern(file), []).append(file)

too_many_groups = len(groups) > 4
too_many_files = len(files) > 25
if not (too_many_groups or too_many_files):
    print("ok\t")
else:
    summary = ", ".join(f"{key}({len(value)})" for key, value in sorted(groups.items()))
    print(f"warn\t{len(files)} files / {len(groups)} concerns: {summary}")
PY
)
    status=$(printf '%s' "$split_result" | cut -f1)
    details=$(printf '%s' "$split_result" | cut -f2-)

    if [ "$status" = "warn" ]; then
        echo "⚠️  [hook] staged changes が複数の関心事に広がっています。" >&2
        echo "   $details" >&2
        echo "   1コミット1関心事になるよう、必要なら git add -p / git restore --staged で分割してください。" >&2
        if [ "${DOTFILES_COMMIT_SPLIT_STRICT:-false}" = "true" ]; then
            exit 2
        fi
    fi
}

validate_pr_ticket_or_exit() {
    local context="$1"
    local text="$2"
    local result status refs

    result=$(validate_one_ticket_text "$context" "$text")
    status=$(printf '%s' "$result" | cut -f1)
    refs=$(printf '%s' "$result" | cut -f2-)

    case "$status" in
        ok)
            return 0
            ;;
        missing)
            echo "🚫 [hook] $context は 1 PR = 1 ticket のため、PR title/body に Issue/Jira 等のチケット参照が1つ必要です。" >&2
            echo "   例: PR body に 'Closes #123'、または title/body に '[PROJ-123]' を含めてください。" >&2
            exit 2
            ;;
        multiple)
            echo "🚫 [hook] $context に複数のチケット参照があります: $refs" >&2
            echo "   1 PR は 1 ticket に限定し、別チケットの変更は別 PR / 別 branch に分割してください。" >&2
            exit 2
            ;;
    esac
}

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

# gh pr create は 1 PR = 1 ticket を機械的に確認できる title/body を必須にする
if echo "$command" | grep -qE '(^|[;&|])\s*gh\s+pr\s+create\b'; then
    pr_create_text=$(extract_pr_create_text)
    if printf '%s' "$pr_create_text" | grep -q '^__DOTFILES_BODY_FILE_UNREADABLE__'; then
        echo "🚫 [hook] gh pr create の body file を読めないため、チケット参照を検証できません。" >&2
        echo "   --body / --body-file に 'Closes #123' または '[PROJ-123]' を明示してください。" >&2
        exit 2
    fi
    if printf '%s' "$pr_create_text" | grep -q '^__DOTFILES_FILL_UNVERIFIABLE__$'; then
        echo "🚫 [hook] gh pr create --fill だけでは 1 PR = 1 ticket を検証できません。" >&2
        echo "   --title / --body / --body-file に 'Closes #123' または '[PROJ-123]' を明示してください。" >&2
        exit 2
    fi
    validate_pr_ticket_or_exit "gh pr create" "$pr_create_text"
fi

# gh pr ready の前に、既存 PR の title/body が 1 ticket だけを参照しているか確認する
if echo "$command" | grep -qE '(^|[;&|])\s*gh\s+pr\s+ready\b' && ! echo "$command" | grep -qE '(^|[;&|])\s*gh\s+pr\s+ready\b.*(\s|^)--undo(\s|$)'; then
    ready_info=$(extract_gh_pr_target_repo "ready")
    ready_target=$(printf '%s' "$ready_info" | cut -f1)
    ready_repo_flag=$(printf '%s' "$ready_info" | cut -f2)

    ready_view_args=()
    [ -n "$ready_target" ] && ready_view_args+=("$ready_target")
    [ -n "$ready_repo_flag" ] && ready_view_args+=("-R" "$ready_repo_flag")

    pr_text=$(gh pr view "${ready_view_args[@]}" --json title,body \
      -q '"\(.title)\n\(.body // "")"' 2>/dev/null || true)
    if [ -z "$pr_text" ]; then
        echo "🚫 [hook] ready 対象の PR title/body を確認できません。" >&2
        echo "   ネットワーク接続と gh auth を確認してください。" >&2
        exit 2
    fi
    validate_pr_ticket_or_exit "gh pr ready" "$pr_text"
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

    pr_text=$(gh pr view "${view_args[@]}" --json title,body \
      -q '"\(.title)\n\(.body // "")"' 2>/dev/null || true)
    if [ -z "$pr_text" ]; then
        echo "🚫 [hook] PR #$pr_number の title/body を確認できません。" >&2
        exit 2
    fi
    validate_pr_ticket_or_exit "gh pr merge" "$pr_text"

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

if echo "$command" | grep -qE '(^|[;&|])\s*git\s+push\b.*(--tags|--follow-tags)'; then
    echo "🚫 [hook] 'git push --tags/--follow-tags' を直接実行しないでください。" >&2
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
    commit_policy_result=$(check_commit_message_policy)
    commit_policy_status=$(printf '%s' "$commit_policy_result" | cut -f1)
    commit_policy_message=$(printf '%s' "$commit_policy_result" | cut -f2-)
    if [ "$commit_policy_status" = "blocked" ]; then
        echo "🚫 [hook] コミットメッセージにレビュー起点の文言（レビュー指摘対応等）が含まれています。" >&2
        [ -n "$commit_policy_message" ] && echo "   message: $commit_policy_message" >&2
        echo "   「何を・なぜ変えたか」でメッセージを書き直してください。" >&2
        exit 2
    fi
    check_commit_split_policy
fi

exit 0
