#!/bin/bash
# memories.sh セッションライフサイクル管理（Claude Code 用）
# SessionStart / Stop フックから呼ばれる
#
# 使い方:
#   memories-session.sh start  — セッション開始時
#   memories-session.sh stop   — セッション終了時（snapshot + end）

command -v memories &>/dev/null || exit 0

CLIENT="claude-code"
# PPID でセッションを分離し、同一ツールの並行起動でも競合しない
SESSION_STATE_DIR="${HOME}/.config/memories/sessions"
SESSION_STATE_FILE="${SESSION_STATE_DIR}/${CLIENT}-${PPID}"
ACTION="${1:-}"

mkdir -p "$SESSION_STATE_DIR"

case "$ACTION" in
  start)
    # 前回セッションが残っていれば snapshot を再試行してから閉じる
    if [ -f "$SESSION_STATE_FILE" ]; then
      old_id="$(cat "$SESSION_STATE_FILE")"
      memories session snapshot "$old_id" --trigger reset 2>/dev/null || true
      memories session end "$old_id" --status closed 2>/dev/null || true
      rm -f "$SESSION_STATE_FILE"
    fi

    session_id="$(memories session start --client "$CLIENT" --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)"
    if [ -n "$session_id" ]; then
      echo "$session_id" > "$SESSION_STATE_FILE"
    fi

    # プロジェクトのルール取り込みと静的ベースライン生成
    # CLAUDE.md / CODEX.md / GEMINI.md が存在すれば ingest し、generate で反映
    memories ingest claude 2>/dev/null || true
    memories generate claude --force 2>/dev/null || true
    ;;

  stop)
    if [ -f "$SESSION_STATE_FILE" ]; then
      session_id="$(cat "$SESSION_STATE_FILE")"
      # snapshot + end の両方が成功した場合のみ state file を削除
      snapshot_ok=false
      end_ok=false
      memories session snapshot "$session_id" --trigger reset 2>/dev/null && snapshot_ok=true
      memories session end "$session_id" --status closed 2>/dev/null && end_ok=true

      if $snapshot_ok && $end_ok; then
        rm -f "$SESSION_STATE_FILE"
      else
        echo "warn: memories session の終了処理が一部失敗しました (snapshot=$snapshot_ok, end=$end_ok)" >&2
      fi
    fi
    ;;
esac

exit 0
