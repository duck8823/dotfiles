#!/usr/bin/env python3
"""stop-work-guard.sh の振る舞いテスト。

作業依頼 × ツール未使用 × 初回のみ block し、作業済み・壁打ち・疑問形・
同一ターン2回目・stop_hook_active は素通りすることを検証する。
fail-safe（malformed 行で traceback を出さない）と path traversal 耐性も確認する。
"""

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
HOOK = REPO_ROOT / "claude/hooks/stop-work-guard.sh"
TEMPLATE = REPO_ROOT / "claude/settings.json.template"
STATE_DIR = Path("/tmp/stop-work-guard")

SESSION_IDS = [
    "test-sg-block", "test-sg-tool", "test-sg-chat", "test-sg-active",
    "test-sg-toolresult", "test-sg-missing", "test-sg-question", "test-sg-verb",
    "test-sg-malformed",
]


def make_transcript(dirpath: Path, rows: list, name="transcript.jsonl") -> str:
    p = dirpath / name
    with open(p, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return str(p)


def run_hook(transcript_path: str, session_id: str, stop_hook_active: bool = False):
    payload = json.dumps({
        "hook_event_name": "Stop",
        "transcript_path": transcript_path,
        "session_id": session_id,
        "stop_hook_active": stop_hook_active,
    })
    proc = subprocess.run(
        ["bash", str(HOOK)], input=payload, text=True, capture_output=True
    )
    assert proc.returncode == 0, f"hook must always exit 0, got {proc.returncode}"
    return proc.stdout.strip(), proc.stderr


def clean_state(session_id: str) -> None:
    import hashlib
    key = hashlib.sha256(session_id.encode("utf-8")).hexdigest()[:32]
    sf = STATE_DIR / f"{key}.last"
    if sf.exists():
        sf.unlink()


def is_block(out: str) -> bool:
    if not out:
        return False
    try:
        return json.loads(out).get("decision") == "block"
    except Exception:
        return False


def u(text, uid=None):
    o = {"type": "user", "message": {"role": "user", "content": text}}
    if uid:
        o["uuid"] = uid
    return o


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
    for sid in SESSION_IDS:
        clean_state(sid)
    tmp = Path(tempfile.mkdtemp(prefix="stop-guard-test-"))
    try:
        # 1. 作業依頼 × ツール未使用 × 初回 → block
        sid = "test-sg-block"
        tp = make_transcript(tmp, [u("この関数を修正して", "uid-1"), a_text("やっておきました")])
        out, _ = run_hook(tp, sid)
        assert is_block(out), f"[1] expected block, got {out!r}"

        # 2. 同一ユーザーターン（同 uuid）で 2 回目 → 素通り（ループ防止）
        out2, _ = run_hook(tp, sid)
        assert not is_block(out2), f"[2] expected pass on 2nd call, got {out2!r}"

        # 3. 作業依頼 × ツール使用あり → 素通り
        sid = "test-sg-tool"
        tp = make_transcript(tmp, [u("修正して", "uid-3"), a_tool(), a_text("完了")])
        assert not is_block(run_hook(tp, sid)[0]), "[3] expected pass when tool used"

        # 4. 壁打ち（作業依頼シグナル無し）→ 素通り
        sid = "test-sg-chat"
        tp = make_transcript(tmp, [u("今日はいい天気ですね", "uid-4"), a_text("そうですね")])
        assert not is_block(run_hook(tp, sid)[0]), "[4] expected pass for chit-chat"

        # 5. stop_hook_active=true → 素通り
        sid = "test-sg-active"
        tp = make_transcript(tmp, [u("修正して", "uid-5"), a_text("…")])
        assert not is_block(run_hook(tp, sid, stop_hook_active=True)[0]), \
            "[5] expected pass when stop_hook_active"

        # 6. tool_result だけの user 行は実ユーザー入力扱いしない
        sid = "test-sg-toolresult"
        tp = make_transcript(tmp, [u("修正して", "uid-6"), a_tool(), u_tool_result(), a_text("done")])
        assert not is_block(run_hook(tp, sid)[0]), "[6] expected pass (tool_use after real prompt)"

        # 7. transcript 欠如 → 素通り（fail-safe）
        assert not is_block(run_hook("/nonexistent/transcript.jsonl", "test-sg-missing")[0]), \
            "[7] expected pass when transcript missing"

        # 8. 同一 session・同文だが別ターン（別 uuid）→ block される（turn identity）
        sid = "test-sg-block"
        clean_state(sid)
        tp1 = make_transcript(tmp, [u("修正して", "uid-8a"), a_text("done")], "t8a.jsonl")
        assert is_block(run_hook(tp1, sid)[0]), "[8] first turn should block"
        tp2 = make_transcript(tmp, [u("修正して", "uid-8b"), a_text("done")], "t8b.jsonl")
        assert is_block(run_hook(tp2, sid)[0]), "[8] different turn (new uuid) should block again"

        # 9. malformed 行（null / list）混在 → 素通りせず block かつ traceback を出さない
        sid = "test-sg-malformed"
        tp = make_transcript(tmp, [None, [1, 2], u("修正して", "uid-9"), a_text("x")], "t9.jsonl")
        out, err = run_hook(tp, sid)
        assert is_block(out), f"[9] expected block despite malformed rows, got {out!r}"
        assert "Traceback" not in err, f"[9] fail-safe must not leak traceback: {err!r}"

        # 10. session_id の path traversal → /tmp/stop-work-guard 外にファイルを作らない
        traversal_sid = "../sg-pwned-test"
        leaked = Path("/tmp/sg-pwned-test.last")
        if leaked.exists():
            leaked.unlink()
        tp = make_transcript(tmp, [u("修正して", "uid-10"), a_text("x")], "t10.jsonl")
        run_hook(tp, traversal_sid)
        assert not leaked.exists(), "[10] path traversal must not write outside state dir"

        # 11. 疑問形（相談）→ 素通り（CHAT_RE が WORK_RE より優先）
        sid = "test-sg-question"
        tp = make_transcript(tmp, [u("この実装方針についてどう思う？", "uid-11"), a_text("私見では…")])
        assert not is_block(run_hook(tp, sid)[0]), "[11] expected pass for question form"

        # 12. 追加動詞「レビューして」→ block
        sid = "test-sg-verb"
        tp = make_transcript(tmp, [u("この PR をレビューして", "uid-12"), a_text("…")])
        assert is_block(run_hook(tp, sid)[0]), "[12] expected block for review request"

        # 13. settings.json.template に stop-work-guard が登録され、valid JSON である
        rendered = TEMPLATE.read_text().replace("{{HOME}}", "/h").replace("{{DOTFILES_DIR}}", "/d")
        data = json.loads(rendered)
        stop_cmds = [h.get("command", "")
                     for blk in data["hooks"]["Stop"]
                     for h in blk.get("hooks", [])]
        assert any("stop-work-guard.sh" in c for c in stop_cmds), \
            "[13] template Stop hooks must register stop-work-guard.sh"

        print("stop-work-guard test OK")
    finally:
        shutil.rmtree(tmp)
        for sid in SESSION_IDS:
            clean_state(sid)
        clean_state("../sg-pwned-test")
        leaked = Path("/tmp/sg-pwned-test.last")
        if leaked.exists():
            leaked.unlink()


if __name__ == "__main__":
    main()
