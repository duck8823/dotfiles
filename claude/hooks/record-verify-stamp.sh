#!/bin/bash
# Claude Code PostToolUse hook: 検証コマンド成功時にスタンプを記録する
# git commit 時にスタンプをクリアする（再検証が必要）

input=$(cat)
command=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null || echo "")

# リポジトリのハッシュをスタンプファイル名に使用
repo_dir=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$repo_dir" ]; then
    exit 0
fi
repo_hash=$(echo "$repo_dir" | md5 -q 2>/dev/null || echo "$repo_dir" | md5sum | cut -d' ' -f1)
stamp_dir="${HOME}/.cache/claude-code"
mkdir -p "$stamp_dir" 2>/dev/null
stamp_file="${stamp_dir}/verify-stamp-${repo_hash}"

# git commit 実行時はスタンプをクリア（新コミットで再検証が必要）
if echo "$command" | grep -qE '(^|[;&|])\s*git\s+commit\b'; then
    rm -f "$stamp_file" 2>/dev/null
    exit 0
fi

# 検証コマンドのパターンマッチ
if ! echo "$command" | grep -qE '(flutter\s+analyze|flutter\s+test|go\s+vet|go\s+test|npm\s+test|npm\s+run\s+(lint|typecheck)|cargo\s+(test|clippy)|pytest\b|python3?\s+-m\s+pytest|uv\s+run\s+pytest|ruff\s+check)'; then
    exit 0
fi

# tool_response に失敗パターンが含まれていなければ成功とみなしスタンプ記録
# `exit code 0` や `No errors` のような成功出力を誤検出しないよう、
# 非0 exit と行頭エラーに限定する。
has_error=$(echo "$input" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    resp = str(d.get('tool_response', ''))
    patterns = [
        r'(?im)^\\s*(FAILED|FAIL)\\b',
        r'(?im)^\\s*ERRORS?\\b',
        r'(?im)^\\s*(error|Error):\\s',
        r'(?im)\\berror\\s+TS[0-9]+:',
        r'(?im)\\bpanic:\\s',
        r'(?im)\\bexit status\\s+[1-9][0-9]*\\b',
        r'(?im)\\bexit code\\s+[1-9][0-9]*\\b',
        r'(?im)^\\s*Command failed\\b',
    ]
    print('1' if any(re.search(p, resp) for p in patterns) else '0')
except:
    print('0')
" 2>/dev/null || echo "0")

if [ "$has_error" = "0" ]; then
    date +%s > "$stamp_file"
fi

exit 0
