#!/bin/bash
# memories.sh セッションライフサイクル管理
# Claude Code の SessionStart / Stop フックから呼ばれる
#
# 使い方:
#   memories-session.sh start   — セッション開始時
#   memories-session.sh stop    — セッション終了時（snapshot + end）

command -v memories &>/dev/null || exit 0

SESSION_STATE_FILE="${HOME}/.config/memories/claude-session-id"
ACTION="${1:-}"

case "$ACTION" in
  start)
    # 前回セッションが残っていれば閉じる
    if [ -f "$SESSION_STATE_FILE" ]; then
      old_id="$(cat "$SESSION_STATE_FILE")"
      memories session end "$old_id" --status closed 2>/dev/null || true
      rm -f "$SESSION_STATE_FILE"
    fi

    # 新規セッション開始
    session_id="$(memories session start --client claude-code --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)"
    if [ -n "$session_id" ]; then
      echo "$session_id" > "$SESSION_STATE_FILE"
    fi
    ;;

  stop)
    if [ -f "$SESSION_STATE_FILE" ]; then
      session_id="$(cat "$SESSION_STATE_FILE")"
      # snapshot を取ってからセッションを閉じる
      memories session snapshot "$session_id" --trigger reset 2>/dev/null || true
      memories session end "$session_id" --status closed 2>/dev/null || true
      rm -f "$SESSION_STATE_FILE"
    fi
    ;;
esac

exit 0
