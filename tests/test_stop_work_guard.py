#!/usr/bin/env python3
"""stop-work-guard.sh の振る舞いテスト。

作業依頼 × ツール未使用 × 初回のみ block し、
作業済み・壁打ち・2 回目（同一ターン）・stop_hook_active は素通りすることを検証する。
"""

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
HOOK = REPO_ROOT / "claude/hooks/stop-work-guard.sh"
STATE_DIR = Path("/tmp/stop-work-guard")


def make_transcript(dirpath: Path, rows: list) -> str:
    p = dirpath / "transcript.jsonl"
    with open(p, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return str(p)


def run_hook(transcript_path: str, session_id: str, stop_hook_active: bool = False) -> str:
    payload = json.dumps({
        "hook_event_name": "Stop",
        "transcript_path": transcript_path,
        "session_id": session_id,
        "stop_hook_active": stop_hook_active,
    })
    proc = subprocess.run(
        ["bash", str(HOOK)], input=payload, text=True, capture_output=True
    )
    assert proc.returncode == 0, f"hook must always exit 0, got {proc.returncode}: {proc.stderr}"
    return proc.stdout.strip()


def clean_state(session_id: str) -> None:
    sf = STATE_DIR / f"{session_id}.last"
    if sf.exists():
        sf.unlink()


def is_block(out: str) -> bool:
    if not out:
        return False
    try:
        return json.loads(out).get("decision") == "block"
    except Exception:
        return False


def u(text):
    return {"type": "user", "message": {"role": "user", "content": text}}


def a_tool():
    return {"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "tool_use", "name": "Bash", "input": {}}]}}


def a_text(t="ok"):
    return {"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "text", "text": t}]}}


def u_tool_result():
    return {"type": "user", "message": {"role": "user",
            "content": [{"type": "tool_result", "content": "r"}]}}


def main() -> None:
    tmp = Path(tempfile.mkdtemp(prefix="stop-guard-test-"))
    try:
        # 1. 作業依頼 × ツール未使用 × 初回 → block
        sid = "test-sg-block"
        clean_state(sid)
        tp = make_transcript(tmp, [u("この関数を修正して"), a_text("やっておきました")])
        out = run_hook(tp, sid)
        assert is_block(out), f"[1] expected block, got {out!r}"

        # 2. 同一ユーザーターンで 2 回目 → 素通り（ループ防止: 状態ファイル一致）
        out2 = run_hook(tp, sid)
        assert not is_block(out2), f"[2] expected pass on 2nd call, got {out2!r}"

        # 3. 作業依頼 × ツール使用あり → 素通り
        sid = "test-sg-tool"
        clean_state(sid)
        tp = make_transcript(tmp, [u("この関数を修正して"), a_tool(), a_text("完了")])
        assert not is_block(run_hook(tp, sid)), "[3] expected pass when tool was used"

        # 4. 壁打ち（作業依頼シグナル無し）× ツール未使用 → 素通り
        sid = "test-sg-chat"
        clean_state(sid)
        tp = make_transcript(tmp, [u("これってどう思う？意見を聞かせて"), a_text("私の考えは…")])
        assert not is_block(run_hook(tp, sid)), "[4] expected pass for chit-chat"

        # 5. stop_hook_active=true → 素通り
        sid = "test-sg-active"
        clean_state(sid)
        tp = make_transcript(tmp, [u("修正して"), a_text("…")])
        assert not is_block(run_hook(tp, sid, stop_hook_active=True)), \
            "[5] expected pass when stop_hook_active"

        # 6. tool_result だけの user 行は実ユーザー入力扱いしない（直前の実 prompt 基準で作業判定）
        sid = "test-sg-toolresult"
        clean_state(sid)
        tp = make_transcript(tmp, [u("修正して"), a_tool(), u_tool_result(), a_text("done")])
        assert not is_block(run_hook(tp, sid)), "[6] expected pass (tool_use after real prompt)"

        # 7. transcript_path が存在しない → 素通り（fail-safe）
        sid = "test-sg-missing"
        clean_state(sid)
        assert not is_block(run_hook("/nonexistent/transcript.jsonl", sid)), \
            "[7] expected pass when transcript missing"

        print("stop-work-guard test OK")
    finally:
        shutil.rmtree(tmp)
        for sid in ("test-sg-block", "test-sg-tool", "test-sg-chat",
                    "test-sg-active", "test-sg-toolresult", "test-sg-missing"):
            clean_state(sid)


if __name__ == "__main__":
    main()
