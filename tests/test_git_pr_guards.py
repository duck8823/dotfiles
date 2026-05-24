#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HOOK = REPO_ROOT / "claude/hooks/check-gh-commands.sh"


def run_hook(command: str, *, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps({"tool_input": {"command": command}}) + "\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd or REPO_ROOT,
        env=merged_env,
    )


def assert_blocked(result: subprocess.CompletedProcess[str], needle: str) -> None:
    if result.returncode != 2:
        raise AssertionError(f"expected hook block, got {result.returncode}\nstdout={result.stdout}\nstderr={result.stderr}")
    if needle not in result.stderr:
        raise AssertionError(f"expected {needle!r} in stderr\nstderr={result.stderr}")


def make_fake_gh(bin_dir: Path, *, title: str, body: str) -> None:
    gh = bin_dir / "gh"
    gh.write_text(
        f"""#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '%s\\n%s\\n' {title!r} {body!r}
  exit 0
fi
echo "unexpected gh args: $*" >&2
exit 1
"""
    )
    gh.chmod(gh.stat().st_mode | stat.S_IXUSR)


def main() -> None:
    # PR creation must be draft and must expose exactly one ticket ref in title/body.
    ok = run_hook('gh pr create --draft --title "[OPS-123] tighten guards" --body "details"')
    assert ok.returncode == 0, ok.stderr

    missing = run_hook('gh pr create --draft --title "tighten guards" --body "no ticket"')
    assert_blocked(missing, "1 PR = 1 ticket")

    multiple = run_hook('gh pr create --draft --title "tighten guards" --body "Closes #123 and Closes #124"')
    assert_blocked(multiple, "複数のチケット参照")

    fill_only = run_hook("gh pr create --draft --fill")
    assert_blocked(fill_only, "--fill だけでは")

    no_draft = run_hook('gh pr create --title "[OPS-123] tighten guards" --body "details"')
    assert_blocked(no_draft, "--draft")

    # Ready also checks the current PR metadata so edited PRs cannot bypass 1 ticket / PR.
    tmp_root = Path(tempfile.mkdtemp(prefix="dotfiles-git-pr-guard-test-"))
    try:
        fake_bin = tmp_root / "bin"
        fake_bin.mkdir()
        make_fake_gh(fake_bin, title="tighten guards", body="Closes #123")
        ready = run_hook("gh pr ready", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert ready.returncode == 0, ready.stderr

        make_fake_gh(fake_bin, title="tighten guards", body="Closes #123\nCloses #124")
        ready_multiple = run_hook("gh pr ready", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert_blocked(ready_multiple, "複数のチケット参照")

        # Review-feedback commit messages are blocked; semantic commit messages pass.
        review_msg = run_hook('git commit -m "fix: address review feedback"')
        assert_blocked(review_msg, "レビュー起点")

        semantic_msg = run_hook('git commit -m "fix: validate PR ticket references"')
        assert semantic_msg.returncode == 0, semantic_msg.stderr

        # Commit split guard is advisory by default, but strict mode can block oversized/multi-concern commits.
        repo = tmp_root / "repo"
        repo.mkdir()
        subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
        paths = [
            "README.md",
            "install.sh",
            "claude/hooks/example.sh",
            "codex/skills/example/SKILL.md",
            "scripts/example.sh",
        ]
        for rel in paths:
            path = repo / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("x\n")
        subprocess.run(["git", "add", "."], cwd=repo, check=True)

        split = run_hook(
            'git commit -m "chore: update guard wiring"',
            cwd=repo,
            env={"DOTFILES_COMMIT_SPLIT_STRICT": "true"},
        )
        assert_blocked(split, "複数の関心事")

        print("git/pr guard hook test OK")
    finally:
        shutil.rmtree(tmp_root)


if __name__ == "__main__":
    main()
