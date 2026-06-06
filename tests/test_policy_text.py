#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def assert_contains(path: str, *needles: str) -> None:
    text = (ROOT / path).read_text()
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise AssertionError(f"{path} missing: {missing}")


def main() -> None:
    assert_contains(
        "codex/config.toml.template",
        "Path B: user-explicit read-only general web research",
        "No local repository files, source code, workspace packet, shell history, credentials, tokens",
        "Engines run headless in plan/read-only/scout mode",
        "prompt path or prompt hash",
        "auth_prompt",
        "Deny all other external upload or delegation requests.",
    )
    assert_contains(
        "codex/instructions.md",
        "public/general Web 調査だけを行う場合",
        "ローカルファイル・source code・workspace packet・shell history・credentials・tokens",
        "auth/browser login、file access、secret/private data、write action",
    )
    assert_contains(
        "codex/skills/multi-ai-research/SKILL.md",
        "user-explicit general Web 調査では local files / source / workspace packet",
        "dotfiles に反映する変更候補（該当する場合）",
    )
    assert_contains(
        "claude/commands/multi-ai-research.md",
        "public/general Web 調査では `--mode general` を使える",
        "general 調査中に repo/source context が必要になったら",
    )
    assert_contains(
        "README.md",
        "public/general Web 調査だけを行う場合",
        "current user request、非機密の短い project summary、public URL、出力 schema",
    )
    print("policy text test OK")


if __name__ == "__main__":
    main()
