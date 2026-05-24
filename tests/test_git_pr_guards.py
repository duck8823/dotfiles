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
  if [[ "$*" == *"number,url"* ]]; then
    printf '52\\thttps://github.com/duck8823/dotfiles/pull/52\\n'
    exit 0
  fi
  printf '%s\\n%s\\n' {title!r} {body!r}
  exit 0
fi
if [ "$1" = "api" ]; then
  printf '%s\\n' "🤖 AI コードレビュー結果" "Gemini: ok" "Codex: ok"
  exit 0
fi
echo "unexpected gh args: $*" >&2
exit 1
"""
    )
    gh.chmod(gh.stat().st_mode | stat.S_IXUSR)


def test_git_pr_guards() -> None:
    # PR creation must be draft and must expose exactly one ticket ref in title/body.
    ok = run_hook('gh pr create --draft --title "[OPS-123] tighten guards" --body "details"')
    assert ok.returncode == 0, ok.stderr

    rtk_ok = run_hook('rtk gh pr create --draft --title "tighten guards" --body "Closes #123"')
    assert rtk_ok.returncode == 0, rtk_ok.stderr

    global_repo_ok = run_hook('gh --repo duck8823/dotfiles pr create --draft --title "tighten guards" --body "Closes #123"')
    assert global_repo_ok.returncode == 0, global_repo_ok.stderr

    env_prefix_ok = run_hook('env FOO=1 gh pr create --draft --title "tighten guards" --body "Closes #123"')
    assert env_prefix_ok.returncode == 0, env_prefix_ok.stderr

    missing = run_hook('gh pr create --draft --title "tighten guards" --body "no ticket"')
    assert_blocked(missing, "1 PR = 1 ticket")

    multiple = run_hook('gh pr create --draft --title "tighten guards" --body "Closes #123 and Closes #124"')
    assert_blocked(multiple, "複数のチケット参照")

    chained = run_hook('gh pr create --draft --title "first" --body "no ticket"; gh pr create --draft --title "[OPS-123] second" --body "details"')
    assert_blocked(chained, "1 PR = 1 ticket")

    bare_version_like = run_hook('gh pr create --draft --title "Support ISO-8601" --body "no ticket"')
    assert_blocked(bare_version_like, "1 PR = 1 ticket")

    fill_only = run_hook("gh pr create --draft --fill")
    assert_blocked(fill_only, "--fill だけでは")

    no_draft = run_hook('gh pr create --title "[OPS-123] tighten guards" --body "details"')
    assert_blocked(no_draft, "--draft")

    quoted_draft = run_hook('gh pr create --title "[OPS-123] tighten guards" --body "mentions --draft but no flag"')
    assert_blocked(quoted_draft, "--draft")

    env_tag = run_hook("env FOO=1 git tag v1.2.3")
    assert_blocked(env_tag, "git tag")

    push_tags = run_hook("rtk proxy git push --follow-tags")
    assert_blocked(push_tags, "git push --tags/--follow-tags")

    release_create = run_hook("command gh --repo duck8823/dotfiles release create v1.2.3")
    assert_blocked(release_create, "gh release create")

    # Ready also checks the current PR metadata so edited PRs cannot bypass 1 ticket / PR.
    tmp_root = Path(tempfile.mkdtemp(prefix="dotfiles-git-pr-guard-test-"))
    try:
        fake_bin = tmp_root / "bin"
        fake_bin.mkdir()
        make_fake_gh(fake_bin, title="tighten guards", body="Closes #123")
        ready = run_hook("gh pr ready", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert ready.returncode == 0, ready.stderr

        global_repo_ready = run_hook("gh --repo duck8823/dotfiles pr ready", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert global_repo_ready.returncode == 0, global_repo_ready.stderr

        merge = run_hook("env FOO=1 gh --repo duck8823/dotfiles pr merge 52", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert merge.returncode == 0, merge.stderr

        make_fake_gh(fake_bin, title="tighten guards", body="Closes #123\nCloses #124")
        ready_multiple = run_hook("gh pr ready", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert_blocked(ready_multiple, "複数のチケット参照")

        chained_ready = run_hook("gh pr ready 1; gh pr ready 2", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert_blocked(chained_ready, "複数の gh pr ready")

        undo_then_ready = run_hook("gh pr ready --undo; gh pr ready", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert_blocked(undo_then_ready, "複数の gh pr ready")

        # Review-feedback commit messages are blocked; semantic commit messages pass.
        review_msg = run_hook('git commit -m "fix: address review feedback"')
        assert_blocked(review_msg, "レビュー起点")

        rtk_review_msg = run_hook('rtk git commit -m "fix: review comments"')
        assert_blocked(rtk_review_msg, "レビュー起点")

        env_review_msg = run_hook('env FOO=1 git commit -m "fix: review comments"')
        assert_blocked(env_review_msg, "レビュー起点")

        combined_flags = run_hook('git commit -am "fix: review comments"')
        assert_blocked(combined_flags, "レビュー起点")

        interactive_msg = run_hook("git commit")
        assert_blocked(interactive_msg, "commit message を検証できません")

        semantic_msg = run_hook('git commit -m "fix: validate PR ticket references"')
        assert semantic_msg.returncode == 0, semantic_msg.stderr

        ai_feature_msg = run_hook('git commit -m "fix: gemini review logic"')
        assert ai_feature_msg.returncode == 0, ai_feature_msg.stderr

        fixup_msg = run_hook("git commit --fixup HEAD")
        assert fixup_msg.returncode == 0, fixup_msg.stderr

        reuse_msg = run_hook("git commit -C HEAD")
        assert reuse_msg.returncode == 0, reuse_msg.stderr

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

        env_split = run_hook(
            'env FOO=1 git commit -m "chore: update guard wiring"',
            cwd=repo,
            env={"DOTFILES_COMMIT_SPLIT_STRICT": "true"},
        )
        assert_blocked(env_split, "複数の関心事")

        print("git/pr guard hook test OK")
    finally:
        shutil.rmtree(tmp_root)


if __name__ == "__main__":
    test_git_pr_guards()
