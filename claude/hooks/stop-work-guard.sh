#!/bin/bash
# Claude Code Stop hook: 作業依頼に対しツールを一度も使わずに停止しようとしたら
# 1 回だけ継続を促す（decision: block）。壁打ち・質問・完了・要判断は通す。
#
# 判定（上から評価し、該当したら素通り = 何も出力せず exit 0）:
#   0. stop_hook_active が真 → 素通り（あれば尊重。公式未記載のため依存はしない）
#   1. 最終ユーザー入力以降に assistant の tool_use がある → 素通り（作業した）
#   2. 最終ユーザー入力が作業依頼シグナルを含まない → 素通り（壁打ち/質問/挨拶）
#   3. 同一ユーザーターンで既に block 済み（状態ファイル一致）→ 素通り（ループ防止）
#   4. 上記すべて非該当 → decision: block を出力
#
# fail-safe: 解析不能・例外時はすべて素通り（停止を妨げない）。

INPUT=$(cat)

STOP_GUARD_INPUT="$INPUT" python3 - <<'PY'
import os, json, re, hashlib, pathlib

try:
    data = json.loads(os.environ.get("STOP_GUARD_INPUT") or "{}")
except Exception:
    raise SystemExit(0)

# 既に guard が継続を促して再実行中なら尊重（フィールドがあれば）
if data.get("stop_hook_active"):
    raise SystemExit(0)

tp = data.get("transcript_path") or ""
if not tp or not os.path.exists(tp):
    raise SystemExit(0)

WORK_RE = re.compile(
    r"(実装|修正|直し|なおし|追加|削除|変更|リファクタ|対応して|作って|書いて|"
    r"デバッグ|調査して|調べて|実行して|テスト書|fix|implement|refactor|debug|"
    r"investigate|build|create|update|\brun\b)", re.I)

try:
    rows = []
    with open(tp, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    pass
except Exception:
    raise SystemExit(0)

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
    c = o.get("message", {}).get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(b.get("text", "") for b in c
                        if isinstance(b, dict) and b.get("type") == "text")
    return ""

def has_tool_use(o):
    if o.get("type") != "assistant":
        return False
    c = o.get("message", {}).get("content")
    return isinstance(c, list) and any(
        isinstance(b, dict) and b.get("type") == "tool_use" for b in c)

last_idx = -1
for i, o in enumerate(rows):
    if is_real_user(o):
        last_idx = i
if last_idx < 0:
    raise SystemExit(0)

after = rows[last_idx + 1:]

# 作業した → 素通り
if any(has_tool_use(o) for o in after):
    raise SystemExit(0)

# 作業依頼シグナル無し（壁打ち/質問/挨拶）→ 素通り
prompt_text = user_text(rows[last_idx])
if not WORK_RE.search(prompt_text):
    raise SystemExit(0)

# ループ防止: 同一ユーザーターンで既に block 済みなら素通り
key = data.get("session_id") or hashlib.sha256(tp.encode("utf-8")).hexdigest()[:16]
state_dir = pathlib.Path("/tmp/stop-work-guard")
state_file = state_dir / ("%s.last" % key)
prompt_hash = hashlib.sha256(prompt_text.encode("utf-8")).hexdigest()
try:
    if state_file.exists() and state_file.read_text().strip() == prompt_hash:
        raise SystemExit(0)
except OSError:
    pass

# block する → 同一ターン再 block 防止のため状態を記録
try:
    state_dir.mkdir(parents=True, exist_ok=True)
    state_file.write_text(prompt_hash)
except OSError:
    pass

reason = ("直前の依頼に対しツールを一度も使わずに停止しようとしています。"
          "作業が残っているなら継続してください。"
          "完了済み・壁打ち/相談・ユーザー判断待ちのいずれかなら、"
          "その旨を一言述べてから停止してください。")
print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
raise SystemExit(0)
PY

exit 0
