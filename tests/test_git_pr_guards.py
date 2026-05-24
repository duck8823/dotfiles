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
  printf '%s\\n%b\\n' {title!r} {body!r}
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
    assert_blocked(chained, "1コマンド単独")

    bare_version_like = run_hook('gh pr create --draft --title "Support ISO-8601" --body "no ticket"')
    assert_blocked(bare_version_like, "1 PR = 1 ticket")

    fill_only = run_hook("gh pr create --draft --fill")
    assert_blocked(fill_only, "--fill は")

    fill_with_title = run_hook('gh pr create --draft --fill --title "tighten guards" --body "Closes #123"')
    assert_blocked(fill_with_title, "--fill は")

    recovered_body = run_hook('gh pr create --draft --title "tighten guards" --body "Closes #123" --recover abc')
    assert_blocked(recovered_body, "--recover")

    templated_body = run_hook('gh pr create --draft --title "tighten guards" --body "Closes #123" --template pull_request_template.md')
    assert_blocked(templated_body, "--template")

    no_draft = run_hook('gh pr create --title "[OPS-123] tighten guards" --body "details"')
    assert_blocked(no_draft, "--draft")

    quoted_draft = run_hook('gh pr create --title "[OPS-123] tighten guards" --body "mentions --draft but no flag"')
    assert_blocked(quoted_draft, "--draft")

    assignment_pr = run_hook('FOO=1 gh pr create --draft --title "tighten guards" --body "Closes #123"')
    assert assignment_pr.returncode == 0, assignment_pr.stderr

    literal_git_chain = run_hook('echo "fix git tag docs" && echo done')
    assert literal_git_chain.returncode == 0, literal_git_chain.stderr

    literal_substitution_text = run_hook("echo 'we document $(git rev-parse) usage'")
    assert literal_substitution_text.returncode == 0, literal_substitution_text.stderr

    newline_pr = run_hook('echo ok\ngh pr create --draft --title "tighten guards" --body "no ticket"')
    assert_blocked(newline_pr, "1コマンド単独")

    substituted_body = run_hook('gh pr create --draft --title "tighten guards" --body "$(cat body.md)"')
    assert_blocked(substituted_body, "command substitution")

    env_tag = run_hook("env FOO=1 git tag v1.2.3")
    assert_blocked(env_tag, "git tag")

    assignment_tag = run_hook("FOO=1 git tag v1.2.3")
    assert_blocked(assignment_tag, "git tag")

    exec_tag = run_hook("exec git tag v1.2.3")
    assert_blocked(exec_tag, "git tag")

    shell_wrapper_tag = run_hook("bash -lc 'git tag v1.2.3'")
    assert_blocked(shell_wrapper_tag, "bash -c")

    absolute_shell_wrapper_tag = run_hook("/bin/bash -lc 'git tag v1.2.3'")
    assert_blocked(absolute_shell_wrapper_tag, "bash -c")

    sudo_tag = run_hook("sudo git tag v1.2.3")
    assert_blocked(sudo_tag, "sudo")

    absolute_git_tag = run_hook("/usr/bin/git tag v1.2.3")
    assert_blocked(absolute_git_tag, "git tag")

    newline_tag = run_hook("echo ok\ngit tag v1.2.3")
    assert_blocked(newline_tag, "1コマンド単独")

    git_global_tag = run_hook("git -C /tmp tag v1.2.3")
    assert_blocked(git_global_tag, "git tag")

    push_tags = run_hook("rtk proxy git push --follow-tags")
    assert_blocked(push_tags, "git push --tags/--follow-tags")

    push_tag_ref = run_hook("git push origin refs/tags/v1.2.3")
    assert_blocked(push_tag_ref, "git push tag ref")

    push_delete_tag_ref = run_hook("git push origin :refs/tags/v1.2.3")
    assert_blocked(push_delete_tag_ref, "git push tag ref")

    push_mirror = run_hook("git push --mirror")
    assert_blocked(push_mirror, "git push --tags/--follow-tags")

    push_tag_syntax = run_hook("git push origin tag release-candidate")
    assert_blocked(push_tag_syntax, "git push tag ref")

    release_create = run_hook("command gh --repo duck8823/dotfiles release create v1.2.3")
    assert_blocked(release_create, "gh release create")

    reviewer_option = run_hook('gh pr create --draft --title "tighten guards" --body "Closes #123" --reviewer bot')
    assert_blocked(reviewer_option, "reviewer")

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
        assert_blocked(chained_ready, "1コマンド単独")

        undo_then_ready = run_hook("gh pr ready --undo; gh pr ready", env={"PATH": f"{fake_bin}:{os.environ['PATH']}"})
        assert_blocked(undo_then_ready, "1コマンド単独")

        # Review-feedback commit messages are blocked; semantic commit messages pass.
        review_msg = run_hook('git commit -m "fix: address review feedback"')
        assert_blocked(review_msg, "レビュー起点")

        rtk_review_msg = run_hook('rtk git commit -m "fix: review comments"')
        assert_blocked(rtk_review_msg, "レビュー起点")

        env_review_msg = run_hook('env FOO=1 git commit -m "fix: review comments"')
        assert_blocked(env_review_msg, "レビュー起点")

        assignment_review_msg = run_hook('FOO=1 git commit -m "fix: review comments"')
        assert_blocked(assignment_review_msg, "レビュー起点")

        combined_flags = run_hook('git commit -am "fix: review comments"')
        assert_blocked(combined_flags, "レビュー起点")

        inline_message = run_hook('git commit -mfix')
        assert inline_message.returncode == 0, inline_message.stderr

        newline_review_msg = run_hook('echo ok\ngit commit -m "fix: review comments"')
        assert_blocked(newline_review_msg, "1コマンド単独")

        substituted_review_msg = run_hook('git commit -m "$(echo review comments)"')
        assert_blocked(substituted_review_msg, "command substitution")

        git_global_review_msg = run_hook('git -c user.name=duck commit -m "fix: review comments"')
        assert_blocked(git_global_review_msg, "レビュー起点")

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
