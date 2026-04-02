#!/bin/bash
# memories.sh 連携（Claude Code 用）
# SessionStart / Stop フックから呼ばれる
#
# 使い方:
#   memories-session.sh start  — セッション開始時（ingest + generate）
#   memories-session.sh stop   — セッション終了時（現時点では no-op）

command -v memories &>/dev/null || exit 0

ACTION="${1:-}"

case "$ACTION" in
  start)
    # プロジェクトのルール取り込みと静的ベースライン生成
    memories ingest claude 2>/dev/null || true
    memories generate claude --force 2>/dev/null || true
    ;;

  stop)
    # memories.sh v0.7.9 には session コマンドがないため、
    # session snapshot/end は将来のバージョンで対応予定
    :
    ;;
esac

exit 0
