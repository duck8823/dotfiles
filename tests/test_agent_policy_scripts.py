#!/usr/bin/env python3

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def run(cmd, *, env=None, cwd=None, check=True):
    merged_env = os.environ.copy()
    if env:
        for key, value in env.items():
            if value is None:
                merged_env.pop(key, None)
            else:
                merged_env[key] = value
    return subprocess.run(
        cmd,
        cwd=cwd or REPO_ROOT,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def write_policy(path: Path, body: str) -> Path:
    path.write_text(body)
    return path


def main() -> None:
    tmp_root = Path(tempfile.mkdtemp(prefix="dotfiles-agent-policy-test-"))
    try:
        script = REPO_ROOT / "scripts/multi-ai-research.sh"
        hook = REPO_ROOT / "claude/hooks/check-codex-worktree.sh"

        out_dir = tmp_root / "default-dry-run"
        run(
            [
                "bash",
                str(script),
                "--topic",
                "default dry run",
                "--mode",
                "general",
                "--engines",
                "claude,gemini",
                "--dry-run",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "HOME": str(tmp_root / "no-policy-home"),
                "MULTI_AI_ENGINES": None,
                "MULTI_AI_DISABLED_ENGINES": None,
            },
        )
        status = (out_dir / "status.md").read_text()
        assert "engines_effective: claude,gemini" in status
        assert "codex_reasoning_effort: medium" in status
        assert "tool_output_token_limit: 12000" in status
        assert "max_file_bytes: 25000" in status
        assert "max_total_bytes: 600000" in status

        out_dir = tmp_root / "tool-not-found"
        run(
            [
                "bash",
                str(script),
                "--topic",
                "missing codex",
                "--mode",
                "general",
                "--engines",
                "codex",
                "--out-dir",
                str(out_dir),
            ],
            env={"PATH": "/usr/bin:/bin", "HOME": str(tmp_root / "no-policy-home")},
        )
        assert "classification: tool_not_found" in (out_dir / "status.md").read_text()

        all_disabled_policy = write_policy(
            tmp_root / "all-disabled.env",
            "MULTI_AI_DISABLED_ENGINES=claude,gemini\n",
        )
        out_dir = tmp_root / "all-disabled"
        result = run(
            [
                "bash",
                str(script),
                "--topic",
                "all disabled",
                "--mode",
                "general",
                "--engines",
                "claude,gemini",
                "--out-dir",
                str(out_dir),
            ],
            env={"AI_AGENT_POLICY_FILE": str(all_disabled_policy)},
            check=False,
        )
        assert result.returncode == 75
        assert "classification: no_effective_engines" in (out_dir / "status.md").read_text()

        precedence_policy = write_policy(
            tmp_root / "precedence.env",
            "MULTI_AI_DISABLED_ENGINES=gemini\n",
        )
        out_dir = tmp_root / "precedence"
        run(
            [
                "bash",
                str(script),
                "--topic",
                "precedence",
                "--mode",
                "general",
                "--engines",
                "gemini",
                "--dry-run",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "AI_AGENT_POLICY_FILE": str(precedence_policy),
                "MULTI_AI_DISABLED_ENGINES": "",
            },
        )
        assert "engines_effective: gemini" in (out_dir / "status.md").read_text()

        budget_policy = write_policy(
            tmp_root / "budget.env",
            "\n".join(
                [
                    "MULTI_AI_CODEX_REASONING_EFFORT=low",
                    "MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT=8000",
                    "MULTI_AI_MAX_FILE_BYTES=12345",
                    "MULTI_AI_MAX_TOTAL_BYTES=54321",
                    "MULTI_AI_GEMINI_MODEL=gemini-test",
                    "MULTI_AI_CODEX_MODEL=gpt-test",
                ]
            )
            + "\n",
        )
        out_dir = tmp_root / "budget-policy"
        run(
            [
                "bash",
                str(script),
                "--topic",
                "budget policy",
                "--mode",
                "general",
                "--engines",
                "codex,gemini",
                "--dry-run",
                "--out-dir",
                str(out_dir),
            ],
            env={"AI_AGENT_POLICY_FILE": str(budget_policy)},
        )
        budget_status = (out_dir / "status.md").read_text()
        assert "codex_reasoning_effort: low" in budget_status
        assert "tool_output_token_limit: 8000" in budget_status
        assert "max_file_bytes: 12345" in budget_status
        assert "max_total_bytes: 54321" in budget_status
        assert "gemini_model: gemini-test" in budget_status
        assert "codex_model: gpt-test" in budget_status

        workspace = tmp_root / "workspace-packet"
        (workspace / "docs").mkdir(parents=True)
        (workspace / "docs" / "token-budget.md").write_text("token budget guidance\n")
        (workspace / "api-token.txt").write_text("secret placeholder\n")
        run(["git", "init"], cwd=workspace)
        out_dir = tmp_root / "workspace-packet-out"
        run(
            [
                "bash",
                str(script),
                "--topic",
                "workspace packet",
                "--mode",
                "workspace",
                "--workspace-root",
                str(workspace),
                "--engines",
                "claude",
                "--dry-run",
                "--out-dir",
                str(out_dir),
            ],
            env={"HOME": str(tmp_root / "no-policy-home")},
        )
        packet = (out_dir / "workspace-context.md").read_text()
        assert "### docs/token-budget.md" in packet
        assert "api-token.txt (sensitive path)" in packet
        assert "### api-token.txt" not in packet

        no_policy_home = tmp_root / "hook-home"
        no_policy_home.mkdir()
        plan = run(
            ["bash", str(hook)],
            cwd=tmp_root,
            env={"HOME": str(no_policy_home)},
            check=False,
        )
        # Empty hook input means no command and should pass.
        assert plan.returncode == 0

        disabled_policy = write_policy(
            tmp_root / "disabled-gemini.env",
            "MULTI_AI_DISABLED_ENGINES=gemini\n",
        )
        gemini_disabled = subprocess.run(
            ["bash", str(hook)],
            cwd=tmp_root,
            env={**os.environ, "AI_AGENT_POLICY_FILE": str(disabled_policy)},
            input='{"tool_input":{"command":"gemini --approval-mode=plan -p \' \'"}}\n',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert gemini_disabled.returncode == 2
        assert "local agent policy" in gemini_disabled.stderr

        gemini_write = subprocess.run(
            ["bash", str(hook)],
            cwd=tmp_root,
            input='{"tool_input":{"command":"gemini --approval-mode yolo -p \' \'"}}\n',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert gemini_write.returncode == 2
        assert "Gemini write" in gemini_write.stderr

        allow_write_policy = write_policy(
            tmp_root / "allow-gemini-write.env",
            "MULTI_AI_GEMINI_ALLOW_WRITE=true\n",
        )
        gemini_write_allowed = subprocess.run(
            ["bash", str(hook)],
            cwd=tmp_root,
            env={**os.environ, "AI_AGENT_POLICY_FILE": str(allow_write_policy)},
            input='{"tool_input":{"command":"gemini --approval-mode yolo -p \' \'"}}\n',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert gemini_write_allowed.returncode == 0

        print("agent policy script test OK")
    finally:
        shutil.rmtree(tmp_root)


if __name__ == "__main__":
    main()
