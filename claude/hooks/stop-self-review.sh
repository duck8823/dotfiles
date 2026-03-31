#!/bin/bash
# Claude Code Stop hook: 停止時に未コミットの変更がある場合、セルフレビューを促す
#
# exit 0: 正常続行（stdout がコンテキストとして追加される）
# exit 2: 停止をブロック（stderr がフィードバック）

# 未コミット変更があるか確認
if git rev-parse --git-dir > /dev/null 2>&1; then
    changed_files=$(git diff --name-only 2>/dev/null)
    staged_files=$(git diff --cached --name-only 2>/dev/null)

    if [ -n "$changed_files" ] || [ -n "$staged_files" ]; then
        echo "未コミットの変更があります。コミット前にセルフレビューを検討してください:"
        if [ -n "$staged_files" ]; then
            echo "Staged: $staged_files"
        fi
        if [ -n "$changed_files" ]; then
            echo "Unstaged: $changed_files"
        fi
    fi
fi

exit 0
