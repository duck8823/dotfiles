#!/usr/bin/env python3

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def run_install(repo_copy: Path, home_dir: Path) -> str:
    env = os.environ.copy()
    env["HOME"] = str(home_dir)
    result = subprocess.run(
        ["bash", str(repo_copy / "install.sh")],
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def assert_contains(text: str, needle: str) -> None:
    if needle not in text:
        raise AssertionError(f"expected to find {needle!r} in output")


def main() -> None:
    tmp_root = Path(tempfile.mkdtemp(prefix="dotfiles-install-test-"))

    try:
        tmp_home = tmp_root / "home"
        tmp_repo = tmp_root / "repo"
        tmp_home.mkdir()
        shutil.copytree(REPO_ROOT, tmp_repo)

        # 初回生成
        run_install(tmp_repo, tmp_home)
        assert (tmp_home / ".claude/settings.json").exists()
        assert (tmp_home / ".claude/settings.json.managed.sha256").exists()
        assert (tmp_home / ".gemini/settings.json").exists()
        assert (tmp_home / ".gemini/settings.json.managed.sha256").exists()
        assert (tmp_home / ".codex/config.toml").exists()
        assert (tmp_home / ".codex/config.toml.managed.sha256").exists()

        # 未編集時は keep / update で収まる
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".claude/settings.json (already up to date)")
        assert_contains(log, ".gemini/settings.json (already up to date)")
        assert_contains(log, ".codex/config.toml (already up to date)")

        # ローカル編集のみなら保持
        gemini_settings = tmp_home / ".gemini/settings.json"
        gemini_settings.write_text(
            gemini_settings.read_text().replace(
                '"enableNotifications": true',
                '"enableNotifications": false',
            )
        )
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".gemini/settings.json (local edits preserved)")
        assert not (tmp_home / ".gemini/settings.json.dotfiles-new").exists()

        # copy mode で upstream 更新と衝突したら候補ファイル生成
        repo_gemini_settings = tmp_repo / "gemini/settings.json"
        repo_gemini_settings.write_text(
            repo_gemini_settings.read_text().replace(
                '"modelSteering": true',
                '"modelSteering": false',
            )
        )
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".gemini/settings.json.dotfiles-new")
        assert (tmp_home / ".gemini/settings.json.dotfiles-new").exists()

        # template mode でも upstream 更新と衝突したら候補ファイル生成
        codex_config = tmp_home / ".codex/config.toml"
        codex_config.write_text(codex_config.read_text() + "\n# local override\n")
        repo_codex_template = tmp_repo / "codex/config.toml.template"
        repo_codex_template.write_text(
            repo_codex_template.read_text() + "\n[example]\nenabled = true\n"
        )
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".codex/config.toml.dotfiles-new")
        assert (tmp_home / ".codex/config.toml.dotfiles-new").exists()

        print("installer sync test OK")
    finally:
        shutil.rmtree(tmp_root)


if __name__ == "__main__":
    main()
