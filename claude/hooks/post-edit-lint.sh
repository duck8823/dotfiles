#!/bin/bash
# Claude Code PostToolUse hook: Edit後にファイルをリント・解析する
#
# 新しい言語を追加するには、末尾の「追加言語はここに」ブロックを参考に追記してください。

input=$(cat)
file_path=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except:
    print('')
" 2>/dev/null || echo "")

# パストラバーサル防止（CVE-2025-59536 対策）
# 空パス・相対パス上昇・workspace 外の絶対パスを拒否
if [[ -z "$file_path" ]] || [[ "$file_path" == *".."* ]]; then
    exit 0
fi
if [[ -f "$file_path" ]]; then
    resolved=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$file_path" 2>/dev/null || echo "")
    workspace=$(pwd)
    if [[ -n "$resolved" ]] && [[ "$resolved" != "$workspace"/* ]]; then
        exit 0
    fi
fi

# --- Dart ---
if echo "$file_path" | grep -qE '\.dart$'; then
    dir=$(dirname "$file_path")
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/pubspec.yaml" ]; then
            result=$(cd "$dir" && dart analyze --fatal-infos "$file_path" 2>&1)
            if [ $? -ne 0 ]; then
                echo "⚠️  [hook] dart analyze: $file_path に問題があります:" >&2
                echo "$result" | head -10 >&2
            fi
            break
        fi
        dir=$(dirname "$dir")
    done
fi

# --- YAML ---
if echo "$file_path" | grep -qE '\.(ya?ml)$'; then
    if command -v yamllint &>/dev/null; then
        result=$(yamllint -d relaxed "$file_path" 2>&1)
        if [ $? -ne 0 ]; then
            echo "⚠️  [hook] yamllint: $file_path に問題があります:" >&2
            echo "$result" >&2
        fi
    fi
fi

# --- 追加言語はここに ---
# TypeScript / JavaScript の例:
# if echo "$file_path" | grep -qE '\.(ts|tsx|js|jsx)$'; then
#     if command -v npx &>/dev/null; then
#         result=$(npx eslint "$file_path" 2>&1)
#         if [ $? -ne 0 ]; then
#             echo "⚠️  [hook] eslint: $file_path に問題があります:" >&2
#             echo "$result" | head -20 >&2
#         fi
#     fi
# fi
#
# Go の例:
# if echo "$file_path" | grep -qE '\.go$'; then
#     result=$(go vet "$file_path" 2>&1)
#     if [ $? -ne 0 ]; then
#         echo "⚠️  [hook] go vet: $file_path に問題があります:" >&2
#         echo "$result" >&2
#     fi
# fi

exit 0
