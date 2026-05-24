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

        # skills 配下の shebang スクリプトは shebang を壊さず、生成物はコピーしない。
        fixture_skill = tmp_repo / "codex/skills/test-shebang"
        fixture_scripts = fixture_skill / "scripts"
        fixture_scripts.mkdir(parents=True, exist_ok=True)
        (fixture_skill / "SKILL.md").write_text(
            "---\nname: test-shebang\ndescription: installer fixture\n---\n"
        )
        (fixture_scripts / "tool.py").write_text(
            "#!/usr/bin/env python3\nprint('ok')\n"
        )
        (fixture_scripts / "tool.mjs").write_text(
            "#!/usr/bin/env node\nconsole.log('ok');\n"
        )
        (fixture_scripts / "tool.py").chmod(0o755)
        (fixture_scripts / "tool.mjs").chmod(0o755)
        pycache = fixture_scripts / "__pycache__"
        pycache.mkdir(parents=True, exist_ok=True)
        (pycache / "generated.pyc").write_bytes(b"pyc")

        # 初回生成
        run_install(tmp_repo, tmp_home)
        assert (tmp_home / ".claude/settings.json").exists()
        assert (tmp_home / ".claude/settings.json.managed.sha256").exists()
        assert (tmp_home / ".gemini/settings.json").exists()
        assert (tmp_home / ".gemini/settings.json.managed.sha256").exists()
        assert (tmp_home / ".codex/config.toml").exists()
        assert (tmp_home / ".codex/config.toml.managed.sha256").exists()
        assert (tmp_home / ".local/lib/dotfiles/agent-policy.sh").exists()
        installed_py = tmp_home / ".codex/skills/test-shebang/scripts/tool.py"
        assert installed_py.read_text().splitlines()[:2] == [
            "#!/usr/bin/env python3",
            "# managed by duck8823/dotfiles",
        ]
        installed_mjs = tmp_home / ".codex/skills/test-shebang/scripts/tool.mjs"
        assert installed_mjs.read_text().splitlines()[:2] == [
            "#!/usr/bin/env node",
            "// managed by duck8823/dotfiles",
        ]
        assert os.access(installed_py, os.X_OK)
        assert os.access(installed_mjs, os.X_OK)
        subprocess.run(["node", "--check", str(installed_mjs)], check=True)
        assert not (tmp_home / ".codex/skills/test-shebang/scripts/__pycache__").exists()
        assert not (tmp_home / ".claude/commands/handoff-to-codex.md").exists()
        assert not (tmp_home / ".codex/skills/codex-handoff").exists()

        # 廃止済み managed ファイル/ディレクトリは次回 install で掃除する。
        deprecated_command = tmp_home / ".claude/commands/handoff-to-codex.md"
        deprecated_command.write_text(
            "<!-- managed by duck8823/dotfiles -->\nlegacy command\n"
        )
        deprecated_skill = tmp_home / ".codex/skills/codex-handoff"
        deprecated_skill.mkdir(parents=True)
        (deprecated_skill / "SKILL.md").write_text(
            "---\nname: codex-handoff\n---\n"
        )
        (deprecated_skill / "SKILL.md.managed").write_text(
            "managed by duck8823/dotfiles\n"
        )
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".claude/commands/handoff-to-codex.md (deprecated managed file)")
        assert_contains(log, ".codex/skills/codex-handoff (deprecated managed directory)")
        assert not deprecated_command.exists()
        assert not deprecated_skill.exists()

        # 廃止済みディレクトリでも local override / symlink が混ざる場合は削除しない。
        deprecated_skill.mkdir(parents=True)
        local_note = deprecated_skill / "local-note.md"
        local_note.write_text("local override\n")
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".codex/skills/codex-handoff (deprecated but contains local override")
        assert local_note.exists()
        shutil.rmtree(deprecated_skill)

        # 2 回目以降も shebang の 2 行目マーカーを管理対象として認識し、同期できる
        (fixture_scripts / "tool.mjs").write_text(
            "#!/usr/bin/env node\nconsole.log('updated');\n"
        )
        (fixture_scripts / "tool.mjs").chmod(0o755)
        log = run_install(tmp_repo, tmp_home)
        assert "test-shebang/scripts/tool.mjs (local override" not in log
        assert "console.log('updated');" in installed_mjs.read_text()
        assert installed_mjs.read_text().splitlines()[:2] == [
            "#!/usr/bin/env node",
            "// managed by duck8823/dotfiles",
        ]
        assert os.access(installed_mjs, os.X_OK)

        # 壊れた symlink でも regular file に置き換えて生成できる
        broken_claude_settings = tmp_home / ".claude/settings.json"
        broken_claude_settings.unlink()
        broken_target = tmp_root / "missing-claude-settings.json"
        os.symlink(broken_target, broken_claude_settings)
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".claude/settings.json (migrating from symlink to copy)")
        assert not broken_claude_settings.is_symlink()
        assert broken_claude_settings.exists()

        # 未編集時は keep / update で収まる
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".claude/settings.json (already up to date)")
        assert_contains(log, ".gemini/settings.json (already up to date)")
        assert_contains(log, ".codex/config.toml (already up to date)")

        # 追跡済み symlink は regular file に移行する
        gemini_settings = tmp_home / ".gemini/settings.json"
        gemini_shadow = tmp_root / "gemini-settings-shadow.json"
        gemini_shadow.write_text(gemini_settings.read_text())
        gemini_settings.unlink()
        os.symlink(gemini_shadow, gemini_settings)
        log = run_install(tmp_repo, tmp_home)
        assert_contains(log, ".gemini/settings.json (migrated from symlink to copy)")
        assert not gemini_settings.is_symlink()

        # ローカル編集のみなら保持
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
