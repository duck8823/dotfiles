#!/bin/bash
# Claude Code PreToolUse hook: 検証スタンプがない状態での push/ready をブロックする

input=$(cat)
command=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null || echo "")

# git push または gh pr ready を検出
is_push=false
is_ready=false

if echo "$command" | grep -qE '(^|[;&|])\s*git\s+push\b'; then
    is_push=true
fi

if echo "$command" | grep -qE '(^|[;&|])\s*gh\s+pr\s+ready\b'; then
    is_ready=true
fi

if [ "$is_push" = false ] && [ "$is_ready" = false ]; then
    exit 0
fi

# リポジトリのハッシュからスタンプファイルを特定
repo_dir=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$repo_dir" ]; then
    exit 0
fi
repo_hash=$(echo "$repo_dir" | md5 -q 2>/dev/null || echo "$repo_dir" | md5sum | cut -d' ' -f1)
stamp_dir="${HOME}/.cache/claude-code"
stamp_file="${stamp_dir}/verify-stamp-${repo_hash}"

# 検証対象のプロジェクトか判定（検証コマンドがあるプロジェクトのみ）
has_verify_target=false
[ -f "$repo_dir/pubspec.yaml" ] && has_verify_target=true
[ -f "$repo_dir/go.mod" ] && has_verify_target=true
[ -f "$repo_dir/package.json" ] && has_verify_target=true
[ -f "$repo_dir/Cargo.toml" ] && has_verify_target=true
[ -f "$repo_dir/pyproject.toml" ] && has_verify_target=true

# 検証対象でなければスキップ
if [ "$has_verify_target" = false ]; then
    exit 0
fi

# ドキュメントのみの変更かチェック（ソースコード変更がなければスキップ）
# push / ready ともにリモートとの差分で判定する
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
remote_ref="origin/$current_branch"
if git rev-parse "$remote_ref" >/dev/null 2>&1; then
    has_source_changes=$(git diff --name-only "$remote_ref"..HEAD 2>/dev/null | grep -cvE '\.(md|txt)$' || true)
else
    # 新規ブランチまたはリモート未設定の場合はスタンプチェック対象
    has_source_changes=1
fi

# ソースコード変更がなければスキップ
if [ "$has_source_changes" = "0" ]; then
    exit 0
fi

# スタンプの存在チェック
if [ ! -f "$stamp_file" ]; then
    action="push"
    [ "$is_ready" = true ] && action="ready"

    echo "⚠️  [hook] 検証コマンド（analyze/test/vet 等）の実行記録がありません。" >&2
    echo "   $action の前に検証を実行することを推奨します。" >&2
    echo "   （このチェックはブロックではなく警告です。続行できます）" >&2
fi

exit 0
