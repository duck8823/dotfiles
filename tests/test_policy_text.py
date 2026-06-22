#!/usr/bin/env python3
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def assert_contains(path: str, *needles: str) -> None:
    text = (ROOT / path).read_text()
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise AssertionError(f"{path} missing: {missing}")


def assert_not_contains(path: str, *needles: str) -> None:
    text = (ROOT / path).read_text()
    present = [needle for needle in needles if needle in text]
    if present:
        raise AssertionError(f"{path} unexpectedly contains: {present}")


def assert_general_dry_run_excludes_workspace_context() -> None:
    topic = "dry-run general safety sentinel"
    with tempfile.TemporaryDirectory(prefix="multi-ai-policy-test-") as tmp:
        env = os.environ.copy()
        env["MULTI_AI_DISABLED_ENGINES"] = ""
        proc = subprocess.run(
            [
                str(ROOT / "scripts/multi-ai-research.sh"),
                "--topic",
                topic,
                "--mode",
                "general",
                "--engines",
                "claude,antigravity",
                "--out-dir",
                tmp,
                "--dry-run",
            ],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if proc.returncode != 0:
            raise AssertionError(
                "general dry-run failed:\n"
                f"stdout={proc.stdout}\n"
                f"stderr={proc.stderr}"
            )

        status = (Path(tmp) / "status.md").read_text()
        prompt = (Path(tmp) / "prompt.md").read_text()
        antigravity_prompt = (Path(tmp) / "prompt.antigravity.md").read_text()

    for required in (
        "- mode_requested: general",
        "- mode_effective: general",
        "- dry_run: true",
        "- engines_requested: claude,antigravity",
    ):
        if required not in status:
            raise AssertionError(f"status missing {required!r}:\n{status}")

    for forbidden in ("- packet:", "- packet_sha256:"):
        if forbidden in status:
            raise AssertionError(f"general status should not include packet metadata: {forbidden}")

    for candidate in (prompt, antigravity_prompt):
        if f"Research topic:\n{topic}" not in candidate:
            raise AssertionError("general prompt did not include the requested topic")
        for forbidden in (
            "Reviewed context packet follows",
            "# Workspace context packet",
            "## Included source files",
            "diff --git",
            "codex/config.toml.template",
            ".ai/spec/93-general-multi-ai-research-policy.md",
            "scripts/multi-ai-research.sh",
            "Path B: user-explicit read-only general web research",
        ):
            if forbidden in candidate:
                raise AssertionError(f"general prompt leaked workspace context marker: {forbidden}")


def main() -> None:
    assert_contains(
        "codex/config.toml.template",
        "Path A: scoped repository / PR work",
        "Work must be scoped to one ticket / one PR",
        "Do not allow main/master direct push.",
        "Do not allow broad arbitrary upload",
        "Deny all other external upload or delegation requests.",
    )
    assert_contains(
        "codex/config.toml.template",
        "Path B: user-explicit read-only general web research",
        "No local repository files, source code, workspace packet, shell history, credentials, tokens",
        "Engines run headless in plan/read-only/scout mode",
        "research scope, engines requested and engines run",
        "classification for each engine",
        "auth_prompt",
        "see the Path B exit condition above",
    )
    assert_contains(
        "codex/config.toml.template",
        "Local orchestrator read-only external API sandbox escalation exception",
        "not external AI delegation",
        "concrete API / provider / resource inspection",
        "read-only `get`, `list`, `show`, `describe`, `search`, `query`",
        "Provider-specific examples include `bq query/show/ls`",
        "Provider SDKs may read/update host credential databases",
        "Credentials, tokens, cookies, and secrets must never be printed",
        "Raw API responses, production rows, and sensitive identifiers must not be sent to external AI reviewers",
        "If the question cannot be answered without raw sensitive data, stop and require a separate, explicit non-AI/manual workflow decision",
        "provider/API/resource inspected",
    )
    assert_not_contains(
        "codex/config.toml.template",
        "unless the user explicitly requests that exact sensitive read",
    )
    assert_contains(
        "codex/instructions.md",
        "public/general Web 調査だけを行う場合",
        "ローカルファイル・source code・workspace packet・shell history・credentials・tokens",
        "research scope・engines requested/run",
        "auth/browser login、file access、secret/private data、write action",
    )
    assert_contains(
        "codex/instructions.md",
        "Local read-only external API sandbox escalation",
        "具体的な API / provider / resource の確認を明示",
        "read-only の `get` / `list` / `show` / `describe` / `search` / `query`",
        "host の credential / access-token cache",
        "外部 AI reviewer へ渡せるのは sanitized summary だけ",
        "provider / API / resource",
    )
    assert_contains(
        "codex/instructions.md",
        "MCP connector の tool payload は別枠で context に入る",
        "Gmail / Traceary / GitHub connector-heavy な triage",
        "limit` / `max_results` / `pageSize` / `body_limit",
        "巨大 JSON / 長いログ / raw transcript は `/private/tmp` に保存",
    )
    assert_contains(
        "codex/instructions.md",
        "scripts/agent-work-preflight.sh --repo <repo> --branch <candidate>",
        "~/.local/bin/agent-work-preflight.sh",
        "rtk /usr/bin/find",
        "scripts/validate-codex-config-template.sh --repo <repo>",
        "~/.local/bin/validate-codex-config-template.sh",
        "CODEX_REVIEW_POLL_SECONDS=180",
        "~/.local/bin/render-pr-review-fallback-comment.sh",
        "Process friction",
    )
    assert_contains(
        "conventions/ai/autonomous-preflight.md",
        "branch prefix collision",
        "git_write_requires_escalation: true",
        "rtk ~/.local/bin/agent-work-preflight.sh",
        "rtk /usr/bin/find",
        "validate-codex-config-template.sh",
        "CODEX_REVIEW_POLL_SECONDS=180",
        "gh pr checks` は PR head ごとに1回取得",
        "Process friction",
    )
    assert_contains(
        "conventions/ai/token-budget.md",
        "`rtk` は shell stdout / stderr を削減できる",
        "Gmail / Traceary などの MCP connector が返す tool payload は別枠",
        "いきなり thread / message body を bulk read しない",
        "`max_results` / `pageSize` 相当で 5〜10 件",
        "metadata-only / minimal view",
        "`traceary sessions --snapshot --json` は session metadata と latest event を含み巨大化しやすい",
        "MCP Traceary tool を使う場合は、`list_events` / `get_context` / `search` の `body_limit`",
    )
    assert_contains(
        "conventions/ai/agent-hooks-observability.md",
        "Traceary read-surface / self-amplification guard",
        "wide snapshot を初手にしない",
        "`traceary sessions --snapshot --json` は最後の確認用",
        "Traceary MCP の `list_events` / `get_context` / `search` は `body_limit` 付き",
        "hook 重複、plugin version mismatch、MCP read surface",
    )
    assert_contains(
        "codex/skills/multi-ai-research/SKILL.md",
        "user-explicit general Web 調査では local files / source / workspace packet",
        "--mode general",
        "dotfiles に反映する変更候補（該当する場合）",
    )
    assert_contains(
        "claude/commands/multi-ai-research.md",
        "public/general Web 調査では `--mode general` を使える",
        "--mode general --engines claude,antigravity,codex",
        "general 調査中に repo/source context が必要になったら",
    )
    assert_contains(
        "README.md",
        "public/general Web 調査だけを行う場合",
        "current user request、非機密の短い project summary、public URL、出力 schema",
        "research scope・engines requested/run",
        "Local read-only external API sandbox escalation",
        "外部 API / SaaS / data service",
        "具体的な API / provider / resource の確認を明示",
        "raw API response / production row / credential / token / secret は渡さない",
        "~/.local/bin/agent-work-preflight.sh",
        "~/.local/bin/validate-codex-config-template.sh",
        "~/.local/bin/render-pr-review-fallback-comment.sh",
    )
    assert_not_contains(
        "scripts/multi-ai-research.sh",
        '"${model_args[@]}"',
        '"${trust_args[@]}"',
    )
    assert_general_dry_run_excludes_workspace_context()
    print("policy text test OK")


if __name__ == "__main__":
    main()
