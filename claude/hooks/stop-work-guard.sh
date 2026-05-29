#!/bin/bash
# Claude Code Stop hook: 作業依頼に対しツールを一度も使わずに停止しようとしたら
# 1 回だけ継続を促す（decision: block）。壁打ち・質問・完了・要判断は通す。
#
# 判定（上から評価し、該当したら素通り = 何も出力せず exit 0）:
#   0. stop_hook_active が真 → 素通り（あれば尊重。公式未記載のため依存はしない）
#   1. 最終ユーザー入力以降に assistant の tool_use がある → 素通り（作業した）
#   2. 最終ユーザー入力が相談・疑問（CHAT_RE）→ 素通り（壁打ち/質問）
#   3. 最終ユーザー入力が作業依頼シグナル（WORK_RE）を含まない → 素通り（挨拶等）
#   4. 同一ユーザーターン（最終ユーザー行の uuid）で既に block 済み → 素通り（ループ防止）
#   5. 上記すべて非該当 → decision: block を出力
#
# fail-safe: 解析不能・例外時はすべて素通り（stderr も出さず exit 0。停止を妨げない）。

INPUT=$(cat)

STOP_GUARD_INPUT="$INPUT" python3 - <<'PY'
import os, json, re, hashlib, pathlib


def main():
    try:
        data = json.loads(os.environ.get("STOP_GUARD_INPUT") or "{}")
    except Exception:
        return
    if not isinstance(data, dict):
        return

    # 既に guard が継続を促して再実行中なら尊重（フィールドがあれば）
    if data.get("stop_hook_active"):
        return

    tp = data.get("transcript_path") or ""
    if not tp or not os.path.exists(tp):
        return

    # 相談・疑問（壁打ち）は作業依頼判定より優先して素通り
    CHAT_RE = re.compile(
        r"(どう思う|どうすべき|意見|なぜ|どうして|教えて|ですか|でしょうか|[?？]\s*$)")
    WORK_RE = re.compile(
        r"(実装|修正|直し|なおし|追加|削除|変更|リファクタ|対応して|作って|書いて|"
        r"デバッグ|調査して|調べて|実行して|確認して|検証して|レビューして|"
        r"テストして|テスト書|fix|implement|refactor|debug|investigate|"
        r"build|create|update|\brun\b)", re.I)

    rows = []
    try:
        with open(tp, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if isinstance(obj, dict):
                    rows.append(obj)
    except Exception:
        return

    def is_real_user(o):
        if o.get("type") != "user":
            return False
        m = o.get("message")
        if not isinstance(m, dict):
            return False
        c = m.get("content")
        if isinstance(c, str):
            return bool(c.strip())
        if isinstance(c, list):
            types = [b.get("type") for b in c if isinstance(b, dict)]
            if types and all(t == "tool_result" for t in types):
                return False
            return any(t == "text" for t in types)
        return False

    def user_text(o):
        m = o.get("message")
        c = m.get("content") if isinstance(m, dict) else None
        if isinstance(c, str):
            return c
        if isinstance(c, list):
            return " ".join(b.get("text", "") for b in c
                            if isinstance(b, dict) and b.get("type") == "text")
        return ""

    def has_tool_use(o):
        if o.get("type") != "assistant":
            return False
        m = o.get("message")
        c = m.get("content") if isinstance(m, dict) else None
        return isinstance(c, list) and any(
            isinstance(b, dict) and b.get("type") == "tool_use" for b in c)

    last_idx = -1
    for i, o in enumerate(rows):
        if is_real_user(o):
            last_idx = i
    if last_idx < 0:
        return

    after = rows[last_idx + 1:]
    if any(has_tool_use(o) for o in after):
        return  # 作業した

    prompt_text = user_text(rows[last_idx])
    if CHAT_RE.search(prompt_text.strip()):
        return  # 相談・疑問は通す
    if not WORK_RE.search(prompt_text):
        return  # 作業依頼シグナルなし

    # ループ防止: 最終ユーザー行の uuid を turn identity に使う
    # （同一 prompt 文を別ターンで再投稿しても uuid が変わるので block される）
    turn = rows[last_idx]
    turn_id = turn.get("uuid") or turn.get("timestamp") or hashlib.sha256(
        prompt_text.encode("utf-8")).hexdigest()
    turn_id = str(turn_id)

    # session key は必ず hash 化（session_id を生でパスに使わない = path traversal 防止）
    raw_key = data.get("session_id") or tp
    key = hashlib.sha256(str(raw_key).encode("utf-8")).hexdigest()[:32]
    state_dir = pathlib.Path("/tmp/stop-work-guard")
    state_file = state_dir / ("%s.last" % key)

    try:
        if state_file.exists() and state_file.read_text().strip() == turn_id:
            return  # 同一ターンで既に block 済み
    except OSError:
        pass

    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        state_file.write_text(turn_id)
    except OSError:
        pass

    reason = ("直前の依頼に対しツールを一度も使わずに停止しようとしています。"
              "作業が残っているなら継続してください。"
              "完了済み・壁打ち/相談・ユーザー判断待ちのいずれかなら、"
              "その旨を一言述べてから停止してください。")
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


try:
    main()
except SystemExit:
    raise
except Exception:
    pass  # 未捕捉例外でも traceback を出さず素通り
PY

exit 0
