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

for key in re.findall(r"\[([A-Z][A-Z0-9]+-[0-9]+)\]", text):
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

check_pr_create_policy() {
    COMMAND="$command" python3 - <<'PY'
import os, pathlib, re, shlex, subprocess, sys

cmd = os.environ.get("COMMAND", "")
shell_operators = {";", "&", "|", "&&", "||", ";;"}

def shell_tokens(value: str) -> list[str]:
    try:
        lexer = shlex.shlex(value, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        return list(lexer)
    except (TypeError, ValueError):
        try:
            return shlex.split(value)
        except ValueError:
            return value.split()

def split_segments(tokens: list[str]) -> list[list[str]]:
    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token in shell_operators:
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments

def normalize_segment(segment: list[str]) -> list[str]:
    seg = list(segment)
    changed = True
    while changed and seg:
        changed = False
        if seg[:1] == ["rtk"]:
            seg = seg[1:]
            if seg[:1] == ["proxy"]:
                seg = seg[1:]
            changed = True
            continue
        if seg[:1] == ["command"]:
            seg = seg[1:]
            changed = True
            continue
        if seg[:1] == ["env"]:
            i = 1
            while i < len(seg):
                tok = seg[i]
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=.*", tok):
                    i += 1
                    continue
                if tok in {"-i", "--ignore-environment"}:
                    i += 1
                    continue
                if tok in {"-u", "--unset"} and i + 1 < len(seg):
                    i += 2
                    continue
                break
            seg = seg[i:]
            changed = True
            continue
    if seg[:1] == ["gh"] and "pr" in seg[1:]:
        i = 1
        while i < len(seg) and seg[i] != "pr":
            tok = seg[i]
            if tok in {"-R", "--repo"} and i + 1 < len(seg):
                i += 2
                continue
            if tok.startswith("--repo="):
                i += 1
                continue
            if tok.startswith("-"):
                i += 1
                continue
            break
        if i < len(seg) and seg[i] == "pr":
            seg = ["gh", *seg[i:]]
    return seg

def ticket_refs(text: str) -> set[str]:
    refs: set[str] = set()
    ticket_prefix = r"(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|issue|issues|ticket|tickets|jira)"
    for line in text.splitlines():
        if re.search(ticket_prefix, line, flags=re.IGNORECASE):
            for number in re.findall(r"(?:^|[^\w/-])(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#([0-9]+)\b", line):
                refs.add(f"GH#{number}")
    for number in re.findall(r"https://github\.com/[^/\s]+/[^/\s]+/issues/([0-9]+)\b", text):
        refs.add(f"GH#{number}")
    for key in re.findall(r"\[([A-Z][A-Z0-9]+-[0-9]+)\]", text):
        refs.add(f"JIRA:{key}")
    return refs

def parse_create(segment: list[str]) -> tuple[str, str]:
    title = ""
    body = ""
    body_file = ""
    has_draft = False
    used_fill = False
    skip_next = False
    for j, tok in enumerate(segment[3:], start=3):
        if skip_next:
            skip_next = False
            continue
        if tok in ("-d", "--draft"):
            has_draft = True
            continue
        if tok in ("-t", "--title"):
            if j + 1 < len(segment):
                title = segment[j + 1]
                skip_next = True
            continue
        if tok.startswith("--title="):
            title = tok.split("=", 1)[1]
            continue
        if tok in ("-b", "--body"):
            if j + 1 < len(segment):
                body = segment[j + 1]
                skip_next = True
            continue
        if tok.startswith("--body="):
            body = tok.split("=", 1)[1]
            continue
        if tok in ("-F", "--body-file"):
            if j + 1 < len(segment):
                body_file = segment[j + 1]
                skip_next = True
            continue
        if tok.startswith("--body-file="):
            body_file = tok.split("=", 1)[1]
            continue
        if tok.startswith("--fill"):
            used_fill = True

    if not has_draft:
        return "blocked", "'gh pr create' には必ず '--draft' を付けてください。"

    if body_file:
        expanded = pathlib.Path(os.path.expandvars(os.path.expanduser(body_file)))
        if str(body_file) == "-" or str(body_file).startswith("<("):
            return "blocked", "gh pr create の body file は検証不能です。--body または通常ファイルの --body-file を使ってください。"
        try:
            body += "\n" + expanded.read_text()
        except OSError:
            return "blocked", "gh pr create の body file を読めないため、チケット参照を検証できません。"

    text = title + "\n" + body
    if used_fill and not title and not body:
        return "blocked", "gh pr create --fill だけでは 1 PR = 1 ticket を検証できません。"

    refs = sorted(ticket_refs(text))
    if len(refs) == 1:
        return "ok", refs[0]
    if not refs:
        return "blocked", "gh pr create は 1 PR = 1 ticket のため、PR title/body に Issue/Jira 等のチケット参照が1つ必要です。"
    return "blocked", "gh pr create に複数のチケット参照があります: " + ",".join(refs)

tokens = shell_tokens(cmd)
checked = 0
for raw_segment in split_segments(tokens):
    segment = normalize_segment(raw_segment)
    if segment[:3] != ["gh", "pr", "create"]:
        continue
    checked += 1
    status, message = parse_create(segment)
    if status != "ok":
        print("blocked\t" + message)
        sys.exit(0)

if checked:
    print("ok\t")
else:
    print("none\t")
PY
}

check_pr_lifecycle_chain_policy() {
    COMMAND="$command" python3 - <<'PY'
import os, re, shlex, sys

cmd = os.environ.get("COMMAND", "")
shell_operators = {";", "&", "|", "&&", "||", ";;"}

def shell_tokens(value: str) -> list[str]:
    try:
        lexer = shlex.shlex(value, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        return list(lexer)
    except (TypeError, ValueError):
        print("blocked\tcommand を安全に解析できません。")
        sys.exit(0)

def split_segments(tokens: list[str]) -> list[list[str]]:
    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token in shell_operators:
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments

def normalize_segment(segment: list[str]) -> list[str]:
    seg = list(segment)
    changed = True
    while changed and seg:
        changed = False
        if seg[:1] == ["rtk"]:
            seg = seg[1:]
            if seg[:1] == ["proxy"]:
                seg = seg[1:]
            changed = True
            continue
        if seg[:1] == ["command"]:
            seg = seg[1:]
            changed = True
            continue
        if seg[:1] == ["env"]:
            i = 1
            while i < len(seg):
                tok = seg[i]
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=.*", tok):
                    i += 1
                    continue
                if tok in {"-i", "--ignore-environment"}:
                    i += 1
                    continue
                if tok in {"-u", "--unset"} and i + 1 < len(seg):
                    i += 2
                    continue
                break
            seg = seg[i:]
            changed = True
            continue
    if seg[:1] == ["gh"] and "pr" in seg[1:]:
        i = 1
        while i < len(seg) and seg[i] != "pr":
            tok = seg[i]
            if tok in {"-R", "--repo"} and i + 1 < len(seg):
                i += 2
                continue
            if tok.startswith("--repo="):
                i += 1
                continue
            if tok.startswith("-"):
                i += 1
                continue
            break
        if i < len(seg) and seg[i] == "pr":
            seg = ["gh", *seg[i:]]
    return seg

counts = {"ready": 0, "merge": 0}
for raw_segment in split_segments(shell_tokens(cmd)):
    segment = normalize_segment(raw_segment)
    if segment[:3] == ["gh", "pr", "ready"]:
        if "--undo" not in segment[3:]:
            counts["ready"] += 1
    if segment[:3] == ["gh", "pr", "merge"]:
        counts["merge"] += 1

if counts["ready"] > 1:
    print("blocked\t複数の gh pr ready を1コマンドに連結しないでください。")
elif counts["merge"] > 1:
    print("blocked\t複数の gh pr merge を1コマンドに連結しないでください。")
else:
    print("ok\t")
PY
}

check_commit_message_policy() {
    COMMAND="$command" python3 - <<'PY'
import os, pathlib, re, shlex, sys

cmd = os.environ.get("COMMAND", "")
shell_operators = {";", "&", "|", "&&", "||", ";;"}
banned = [
    r"レビュー\s*(指摘|コメント|フィードバック)?\s*(対応|反映|修正|修正対応)",
    r"(指摘|コメント|フィードバック)\s*(対応|反映|修正)",
    r"(codex|gemini|claude)\s*(review|レビュー)\s*(対応|反映|修正|fix|feedback|comments?|changes)",
    r"\b(review|reviewer)\s*(fix|feedback|comment|comments|changes)\b",
    r"\b(address|apply|fix|resolve|handle)[ -]?(review|reviewer)[ -]?(feedback|comments?|changes)\b",
    r"\bfix(?:es|ed)?\s+review\s+comments?\b",
]

def shell_tokens(value: str) -> list[str]:
    try:
        lexer = shlex.shlex(value, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        return list(lexer)
    except (TypeError, ValueError):
        try:
            return shlex.split(value)
        except ValueError:
            return value.split()

def split_segments(tokens: list[str]) -> list[list[str]]:
    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token in shell_operators:
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments

def normalize_segment(segment: list[str]) -> list[str]:
    seg = list(segment)
    changed = True
    while changed and seg:
        changed = False
        if seg[:1] == ["rtk"]:
            seg = seg[1:]
            if seg[:1] == ["proxy"]:
                seg = seg[1:]
            changed = True
            continue
        if seg[:1] == ["command"]:
            seg = seg[1:]
            changed = True
            continue
        if seg[:1] == ["env"]:
            i = 1
            while i < len(seg):
                tok = seg[i]
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=.*", tok):
                    i += 1
                    continue
                if tok in {"-i", "--ignore-environment"}:
                    i += 1
                    continue
                if tok in {"-u", "--unset"} and i + 1 < len(seg):
                    i += 2
                    continue
                break
            seg = seg[i:]
            changed = True
            continue
    return seg

def read_message_file(path: str) -> str:
    expanded = pathlib.Path(os.path.expandvars(os.path.expanduser(path)))
    return expanded.read_text()

def read_commit_message(rev: str) -> str:
    return subprocess.check_output(
        ["git", "log", "-1", "--format=%B", rev],
        text=True,
        stderr=subprocess.DEVNULL,
    )

def extract_messages(segment: list[str]) -> tuple[list[str], bool]:
    messages: list[str] = []
    unverifiable = False
    amend = False
    no_edit = False
    skip_next = False
    args = segment[2:]
    for j, tok in enumerate(args):
        if skip_next:
            skip_next = False
            continue
        if tok == "--amend":
            amend = True
            continue
        if tok == "--no-edit":
            no_edit = True
            continue
        if tok.startswith("--fixup") or tok.startswith("--squash"):
            messages.append(tok)
            continue
        if tok in ("-C", "--reuse-message", "-c", "--reedit-message"):
            if j + 1 < len(args):
                try:
                    messages.append(read_commit_message(args[j + 1]))
                except (OSError, subprocess.CalledProcessError):
                    unverifiable = True
                skip_next = True
            else:
                unverifiable = True
            continue
        if tok.startswith("--reuse-message=") or tok.startswith("--reedit-message="):
            try:
                messages.append(read_commit_message(tok.split("=", 1)[1]))
            except (OSError, subprocess.CalledProcessError):
                unverifiable = True
            continue
        if tok in ("-m", "--message"):
            if j + 1 < len(args):
                messages.append(args[j + 1])
                skip_next = True
            continue
        if tok.startswith("--message="):
            messages.append(tok.split("=", 1)[1])
            continue
        if tok.startswith("-") and not tok.startswith("--") and "m" in tok[1:]:
            flags = tok[1:]
            m_index = flags.find("m")
            if m_index != len(flags) - 1:
                unverifiable = True
                continue
            inline = flags[m_index + 1:]
            if inline:
                messages.append(inline)
            elif j + 1 < len(args):
                messages.append(args[j + 1])
                skip_next = True
            continue
        if tok in ("-F", "--file"):
            if j + 1 < len(args):
                try:
                    messages.append(read_message_file(args[j + 1]))
                except OSError:
                    unverifiable = True
                skip_next = True
            continue
        if tok.startswith("--file="):
            try:
                messages.append(read_message_file(tok.split("=", 1)[1]))
            except OSError:
                unverifiable = True
            continue
    if not messages and amend and no_edit:
        try:
            messages.append(read_commit_message("HEAD"))
        except (OSError, subprocess.CalledProcessError):
            unverifiable = True
    if not messages:
        unverifiable = True
    return messages, unverifiable

messages = []
unverifiable = False
checked = 0
for raw_segment in split_segments(shell_tokens(cmd)):
    segment = normalize_segment(raw_segment)
    if segment[:2] != ["git", "commit"]:
        continue
    checked += 1
    segment_messages, segment_unverifiable = extract_messages(segment)
    messages.extend(segment_messages)
    unverifiable = unverifiable or segment_unverifiable

if not checked:
    print("none\t")
    sys.exit(0)

combined = "\n".join(messages)
if not combined:
    print("blocked\tcommit message を検証できません。-m / --message / -F で明示してください。")
    sys.exit(0)

for pattern in banned:
    if re.search(pattern, combined, flags=re.IGNORECASE):
        first_line = combined.strip().splitlines()[0] if combined.strip() else ""
        print("blocked\t" + first_line[:200])
        sys.exit(0)

if unverifiable:
    print("blocked\tcommit message の一部を検証できません。-m / --message / -F で明示してください。")
    sys.exit(0)

print("ok\t")
PY
}

check_commit_split_policy() {
    if ! echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?git\s+commit\b'; then
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
        *)
            echo "🚫 [hook] $context のチケット参照検証に失敗しました。" >&2
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
if echo "$command" | grep -qE '^\s*(rtk\s+(proxy\s+)?)?gh\s+pr\s+review\b'; then
    echo "⚠️  [hook] 'gh pr review' は権限フックでブロックされる可能性があります。" >&2
    echo "   ブロックされた場合は 'gh pr comment' に切り替えてください。" >&2
fi

# gh pr create は segment ごとに --draft と 1 PR = 1 ticket を検査する
pr_create_policy=$(check_pr_create_policy)
pr_create_status=$(printf '%s' "$pr_create_policy" | cut -f1)
pr_create_message=$(printf '%s' "$pr_create_policy" | cut -f2-)
case "$pr_create_status" in
    ok|none)
        ;;
    blocked)
        echo "🚫 [hook] $pr_create_message" >&2
        echo "   --draft と、--title / --body / --body-file の 'Closes #123' または '[PROJ-123]' を1つだけ明示してください。" >&2
        exit 2
        ;;
    *)
        echo "🚫 [hook] gh pr create のチケット検証に失敗しました。" >&2
        exit 2
        ;;
esac

pr_lifecycle_policy=$(check_pr_lifecycle_chain_policy)
pr_lifecycle_status=$(printf '%s' "$pr_lifecycle_policy" | cut -f1)
pr_lifecycle_message=$(printf '%s' "$pr_lifecycle_policy" | cut -f2-)
case "$pr_lifecycle_status" in
    ok)
        ;;
    blocked)
        echo "🚫 [hook] $pr_lifecycle_message" >&2
        echo "   PR ready / merge は1コマンド1対象で分離して実行してください。" >&2
        exit 2
        ;;
    *)
        echo "🚫 [hook] PR lifecycle command の解析に失敗しました。" >&2
        exit 2
        ;;
esac

# gh pr ready の前に、既存 PR の title/body が 1 ticket だけを参照しているか確認する
if echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?gh\s+pr\s+ready\b' && ! echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?gh\s+pr\s+ready\b.*(\s|^)--undo(\s|$)'; then
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
if echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?gh\s+pr\s+merge\b'; then
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
if echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?git\s+tag\b'; then
    echo "🚫 [hook] 'git tag' を直接実行しないでください。" >&2
    echo "   リリースタグはユーザーの明示的な承認を得てから作成してください。" >&2
    exit 2
fi

if echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?git\s+push\b.*(--tags|--follow-tags)'; then
    echo "🚫 [hook] 'git push --tags/--follow-tags' を直接実行しないでください。" >&2
    echo "   リリースタグはユーザーの明示的な承認を得てから push してください。" >&2
    exit 2
fi

if echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?gh\s+release\s+create\b'; then
    echo "🚫 [hook] 'gh release create' を直接実行しないでください。" >&2
    echo "   リリースはユーザーの明示的な承認を得てから作成してください。" >&2
    exit 2
fi

# コミットメッセージにレビュー起点の文言が含まれていないかチェック
if echo "$command" | grep -qE '(^|[;&|])\s*(rtk\s+(proxy\s+)?)?git\s+commit\b'; then
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
