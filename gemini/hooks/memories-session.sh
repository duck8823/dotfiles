#!/bin/bash
# memories.sh セッションライフサイクル管理（Gemini 用ラッパー）
# Gemini のフックは JSON 出力が必須のため、共通スクリプトを呼んだ後 JSON を返す

# 共通スクリプトを実行（出力は stderr へ）
bash "${HOME}/.claude/hooks/memories-session.sh" "$@" 2>&1 >&2

# Gemini に空の成功レスポンスを返す
echo '{}'
exit 0
