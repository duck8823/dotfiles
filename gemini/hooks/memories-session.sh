#!/bin/bash
# memories.sh 連携（Gemini 用）
# SessionStart / SessionEnd フックから呼ばれる
# Gemini のフックは JSON 出力が必須のため、最後に {} を返す
#
# 使い方:
#   memories-session.sh start  — セッション開始時（ingest + generate）
#   memories-session.sh stop   — セッション終了時（現時点では no-op）

if ! command -v memories &>/dev/null; then
  echo '{}'
  exit 0
fi

ACTION="${1:-}"

case "$ACTION" in
  start)
    memories ingest gemini 2>/dev/null || true
    memories generate gemini --force 2>/dev/null || true
    ;;

  stop)
    :
    ;;
esac

echo '{}'
exit 0
