#!/bin/bash
# memories.sh 連携（Codex 用）
# SessionStart / Stop フックから呼ばれる
#
# 使い方:
#   memories-session.sh start  — セッション開始時（ingest + generate）
#   memories-session.sh stop   — セッション終了時（現時点では no-op）

command -v memories &>/dev/null || exit 0

ACTION="${1:-}"

case "$ACTION" in
  start)
    memories ingest codex 2>/dev/null || true
    memories generate codex --force 2>/dev/null || true
    ;;

  stop)
    :
    ;;
esac

exit 0
