#!/usr/bin/env python3

import os
import shlex
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
        preflight = REPO_ROOT / "scripts/agent-work-preflight.sh"
        validate_codex_config = REPO_ROOT / "scripts/validate-codex-config-template.sh"
        review_fallback = REPO_ROOT / "scripts/render-pr-review-fallback-comment.sh"
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
                "claude,antigravity",
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
        assert "engines_effective: claude,antigravity" in status
        assert "codex_reasoning_effort: medium" in status
        assert "tool_output_token_limit: 12000" in status
        assert "max_file_bytes: 25000" in status
        assert "max_total_bytes: 600000" in status

        alias_out_dir = tmp_root / "agy-alias-dry-run"
        run(
            [
                "bash",
                str(script),
                "--topic",
                "agy alias dry run",
                "--mode",
                "general",
                "--engines",
                "agy",
                "--dry-run",
                "--out-dir",
                str(alias_out_dir),
            ],
            env={"HOME": str(tmp_root / "no-policy-home")},
        )
        alias_status = (alias_out_dir / "status.md").read_text()
        assert "engines_requested: antigravity" in alias_status
        assert "engines_effective: antigravity" in alias_status
        assert "## antigravity" in alias_status
        assert "## agy" not in alias_status

        alias_disabled_policy = write_policy(
            tmp_root / "agy-alias-disabled.env",
            "MULTI_AI_DISABLED_ENGINES=antigravity\n",
        )
        alias_disabled_out = tmp_root / "agy-alias-disabled"
        alias_disabled = run(
            [
                "bash",
                str(script),
                "--topic",
                "agy alias disabled",
                "--mode",
                "general",
                "--engines",
                "agy",
                "--out-dir",
                str(alias_disabled_out),
            ],
            env={"AI_AGENT_POLICY_FILE": str(alias_disabled_policy)},
            check=False,
        )
        assert alias_disabled.returncode == 75
        alias_disabled_status = (alias_disabled_out / "status.md").read_text()
        assert "engines_skipped_by_policy: antigravity" in alias_disabled_status
        assert "classification: local_policy_disabled" in alias_disabled_status

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

        fake_bin = tmp_root / "fake-bin"
        fake_bin.mkdir()
        fake_claude = fake_bin / "claude"
        fake_claude.write_text("#!/usr/bin/env bash\necho 'Research note: users may sign in to apps, but this is not a CLI auth prompt.'\n")
        fake_claude.chmod(0o755)
        out_dir = tmp_root / "auth-false-positive"
        run(
            [
                "bash",
                str(script),
                "--topic",
                "auth wording",
                "--mode",
                "general",
                "--engines",
                "claude",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(tmp_root / "no-policy-home"),
            },
        )
        assert "classification: ok" in (out_dir / "status.md").read_text()

        codex_marker = tmp_root / "codex-fallback-ran"
        fake_codex = fake_bin / "codex"
        fake_codex.write_text(f"#!/usr/bin/env bash\ntouch {shlex.quote(str(codex_marker))}\necho 'codex fallback ran'\n")
        fake_codex.chmod(0o755)
        fake_claude.write_text("#!/usr/bin/env bash\necho 'Please log in to continue.'\n")
        out_dir = tmp_root / "auth-required"
        auth_required = run(
            [
                "bash",
                str(script),
                "--topic",
                "auth required",
                "--mode",
                "general",
                "--engines",
                "claude,codex",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(tmp_root / "no-policy-home"),
            },
            check=False,
        )
        assert auth_required.returncode == 78
        auth_status = (out_dir / "status.md").read_text()
        assert "classification: auth_prompt" in auth_status
        assert "## AUTH_REQUIRED" in auth_status
        assert "fallback: not executed" in auth_status
        assert "## codex" not in auth_status
        assert not codex_marker.exists()
        assert not (out_dir / "codex.md").exists()

        antigravity_marker = tmp_root / "codex-after-antigravity-auth-ran"
        fake_codex.write_text(f"#!/usr/bin/env bash\ntouch {shlex.quote(str(antigravity_marker))}\necho 'codex fallback ran'\n")
        fake_agy = fake_bin / "agy"
        fake_agy.write_text("#!/usr/bin/env bash\necho 'Opening authentication page in your browser'\n")
        fake_agy.chmod(0o755)
        out_dir = tmp_root / "auth-required-antigravity"
        antigravity_auth_required = run(
            [
                "bash",
                str(script),
                "--topic",
                "antigravity auth required",
                "--mode",
                "general",
                "--engines",
                "antigravity,codex",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(tmp_root / "no-policy-home"),
            },
            check=False,
        )
        assert antigravity_auth_required.returncode == 78
        antigravity_auth_status = (out_dir / "status.md").read_text()
        assert "## antigravity" in antigravity_auth_status
        assert "classification: auth_prompt" in antigravity_auth_status
        assert "fallback: not executed" in antigravity_auth_status
        assert "## codex" not in antigravity_auth_status
        assert not antigravity_marker.exists()
        assert not (out_dir / "codex.md").exists()

        all_disabled_policy = write_policy(
            tmp_root / "all-disabled.env",
            "MULTI_AI_DISABLED_ENGINES=claude,antigravity\n",
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
                "claude,antigravity",
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
            "MULTI_AI_DISABLED_ENGINES=antigravity\n",
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
                "antigravity",
                "--dry-run",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "AI_AGENT_POLICY_FILE": str(precedence_policy),
                "MULTI_AI_DISABLED_ENGINES": "",
            },
        )
        assert "engines_effective: antigravity" in (out_dir / "status.md").read_text()

        budget_policy = write_policy(
            tmp_root / "budget.env",
            "\n".join(
                [
                    "MULTI_AI_CODEX_REASONING_EFFORT=low",
                    "MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT=8000",
                    "MULTI_AI_MAX_FILE_BYTES=12345",
                    "MULTI_AI_MAX_TOTAL_BYTES=54321",
                    "MULTI_AI_ANTIGRAVITY_MODEL=antigravity-test",
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
                "codex,antigravity",
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
        assert "antigravity_model: antigravity-test" in budget_status
        assert "codex_model: gpt-test" in budget_status
        assert "antigravity_auth_retry_without_sandbox: true" in budget_status

        antigravity_retry_marker = tmp_root / "codex-after-antigravity-auth-retry-ran"
        antigravity_retry_log = tmp_root / "antigravity-auth-retry.log"
        out_dir = tmp_root / "auth-retry-antigravity"
        fake_agy.write_text(
            "#!/usr/bin/env bash\n"
            f"printf 'PWD=%s ARGS=%s NO_BROWSER=%s\\n' \"$PWD\" \"$*\" \"${{NO_BROWSER:-}}\" >> {shlex.quote(str(antigravity_retry_log))}\n"
            "case \" $* \" in\n"
            "  *' --sandbox '*) echo 'not authenticated in sandbox'; exit 42 ;;\n"
            "  *) echo 'antigravity host-auth retry ok'; exit 0 ;;\n"
            "esac\n"
        )
        fake_codex.write_text(f"#!/usr/bin/env bash\ntouch {shlex.quote(str(antigravity_retry_marker))}\necho 'codex after retry ran'\n")
        fake_agy.chmod(0o755)
        fake_codex.chmod(0o755)
        run(
            [
                "bash",
                str(script),
                "--topic",
                "antigravity sandbox auth retry",
                "--mode",
                "general",
                "--engines",
                "antigravity,codex",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(tmp_root / "no-policy-home"),
            },
        )
        retry_status = (out_dir / "status.md").read_text()
        assert "## antigravity" in retry_status
        assert "classification: ok" in retry_status
        assert "auth_retry: authenticated_transport_without_cli_sandbox" in retry_status
        assert "initial_output:" in retry_status
        assert (out_dir / "antigravity.sandbox-auth-prompt.md").exists()
        assert antigravity_retry_marker.exists()
        assert (out_dir / "codex.md").exists()
        retry_invocations = antigravity_retry_log.read_text().splitlines()
        assert len(retry_invocations) == 2
        assert all(str(out_dir / "antigravity-cwd") in line for line in retry_invocations)
        assert "--sandbox" in retry_invocations[0]
        assert "--sandbox" not in retry_invocations[1]
        assert all("NO_BROWSER=true" in line for line in retry_invocations)

        retry_disabled_policy = write_policy(
            tmp_root / "antigravity-auth-retry-disabled.env",
            "MULTI_AI_ANTIGRAVITY_AUTH_RETRY_WITHOUT_SANDBOX=false\n",
        )
        retry_disabled_marker = tmp_root / "codex-after-disabled-auth-retry-ran"
        fake_codex.write_text(f"#!/usr/bin/env bash\ntouch {shlex.quote(str(retry_disabled_marker))}\necho 'codex should not run'\n")
        out_dir = tmp_root / "auth-retry-antigravity-disabled"
        retry_disabled = run(
            [
                "bash",
                str(script),
                "--topic",
                "antigravity sandbox auth retry disabled",
                "--mode",
                "general",
                "--engines",
                "antigravity,codex",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "AI_AGENT_POLICY_FILE": str(retry_disabled_policy),
            },
            check=False,
        )
        assert retry_disabled.returncode == 78
        retry_disabled_status = (out_dir / "status.md").read_text()
        assert "classification: auth_prompt" in retry_disabled_status
        assert "auth_retry: authenticated_transport_without_cli_sandbox" not in retry_disabled_status
        assert not retry_disabled_marker.exists()
        assert not (out_dir / "codex.md").exists()

        still_auth_marker = tmp_root / "codex-after-still-auth-retry-ran"
        fake_agy.write_text("#!/usr/bin/env bash\necho 'still not authenticated'; exit 42\n")
        fake_codex.write_text(f"#!/usr/bin/env bash\ntouch {shlex.quote(str(still_auth_marker))}\necho 'codex should not run after auth retry failure'\n")
        fake_agy.chmod(0o755)
        fake_codex.chmod(0o755)
        out_dir = tmp_root / "auth-retry-antigravity-still-auth"
        still_auth = run(
            [
                "bash",
                str(script),
                "--topic",
                "antigravity sandbox auth retry still auth",
                "--mode",
                "general",
                "--engines",
                "antigravity,codex",
                "--out-dir",
                str(out_dir),
            ],
            env={
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(tmp_root / "no-policy-home"),
            },
            check=False,
        )
        assert still_auth.returncode == 78
        still_auth_status = (out_dir / "status.md").read_text()
        assert "classification: auth_prompt" in still_auth_status
        assert "auth_retry: authenticated_transport_without_cli_sandbox" in still_auth_status
        assert "initial_classification: auth_prompt" in still_auth_status
        assert (out_dir / "antigravity.sandbox-auth-prompt.md").exists()
        assert not still_auth_marker.exists()
        assert not (out_dir / "codex.md").exists()

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
            tmp_root / "disabled-antigravity.env",
            "MULTI_AI_DISABLED_ENGINES=antigravity\n",
        )
        antigravity_disabled = subprocess.run(
            ["bash", str(hook)],
            cwd=tmp_root,
            env={**os.environ, "AI_AGENT_POLICY_FILE": str(disabled_policy)},
            input='{"tool_input":{"command":"agy --print --sandbox --prompt \' \'"}}\n',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert antigravity_disabled.returncode == 2
        assert "local agent policy" in antigravity_disabled.stderr

        antigravity_write = subprocess.run(
            ["bash", str(hook)],
            cwd=tmp_root,
            input='{"tool_input":{"command":"agy --prompt \'edit files\'"}}\n',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert antigravity_write.returncode == 2
        assert "Antigravity write" in antigravity_write.stderr

        allow_write_policy = write_policy(
            tmp_root / "allow-antigravity-write.env",
            "MULTI_AI_ANTIGRAVITY_ALLOW_WRITE=true\n",
        )
        antigravity_write_allowed = subprocess.run(
            ["bash", str(hook)],
            cwd=tmp_root,
            env={**os.environ, "AI_AGENT_POLICY_FILE": str(allow_write_policy)},
            input='{"tool_input":{"command":"agy --prompt \'edit files\'"}}\n',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert antigravity_write_allowed.returncode == 0

        preflight_repo = tmp_root / "preflight-repo"
        preflight_repo.mkdir()
        run(["git", "init"], cwd=preflight_repo)
        (preflight_repo / "README.md").write_text("preflight repo\n")
        run(["git", "add", "README.md"], cwd=preflight_repo)
        run(
            [
                "git",
                "-c",
                "user.email=test@example.com",
                "-c",
                "user.name=Test User",
                "commit",
                "-m",
                "init",
            ],
            cwd=preflight_repo,
        )
        run(["git", "branch", "chore"], cwd=preflight_repo)
        branch_collision = run(
            [
                "bash",
                str(preflight),
                "--repo",
                str(preflight_repo),
                "--branch",
                "chore/foo",
                "--writable-root",
                str(tmp_root),
            ],
            check=False,
        )
        assert branch_collision.returncode == 2
        assert "branch_status: prefix_collision" in branch_collision.stdout
        assert "suggested_branch: chore-foo" in branch_collision.stdout

        branch_exists = run(
            [
                "bash",
                str(preflight),
                "--repo",
                str(preflight_repo),
                "--branch",
                "chore",
                "--writable-root",
                str(tmp_root),
            ],
            check=False,
        )
        assert branch_exists.returncode == 3
        assert "branch_status: exists" in branch_exists.stdout
        assert "suggested_branch: chore-2" in branch_exists.stdout

        outside_writable_root = run(
            [
                "bash",
                str(preflight),
                "--repo",
                str(preflight_repo),
                "--branch",
                "feature-token-guard",
                "--writable-root",
                str(tmp_root / "other-root"),
            ],
        )
        assert "branch_status: available" in outside_writable_root.stdout
        assert "git_write_requires_escalation: true" in outside_writable_root.stdout

        codex_config_check = run(["bash", str(validate_codex_config), "--repo", str(REPO_ROOT)])
        assert "toml: ok" in codex_config_check.stdout
        assert "model_instructions_file: ok" in codex_config_check.stdout

        auth_fallback = run(
            [
                "bash",
                str(review_fallback),
                "--pr",
                "123",
                "--head",
                "abc123",
                "--classification",
                "auth_prompt",
            ]
        )
        assert "classification: auth_prompt" in auth_fallback.stdout
        assert "Do not fallback" in auth_fallback.stdout

        no_response_fallback = run(
            [
                "bash",
                str(review_fallback),
                "--pr",
                "123",
                "--head",
                "abc123",
                "--classification",
                "no_response",
            ],
            env={"CODEX_REVIEW_POLL_SECONDS": "12"},
        )
        assert "wait_seconds: 12" in no_response_fallback.stdout
        assert "Proceed with local verification" in no_response_fallback.stdout

        print("agent policy script test OK")
    finally:
        shutil.rmtree(tmp_root)


if __name__ == "__main__":
    main()
