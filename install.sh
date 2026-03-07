#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"

# ============================================================
# ユーティリティ
# ============================================================

link_file() {
  local src="$1"
  local dst="$2"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  mkdir -p "$dst_dir"

  # 既存のファイル（シンボリックリンクでない）はバックアップ
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/"
    echo "  backup: $dst -> $BACKUP_DIR/"
  fi

  ln -sfn "$src" "$dst"
  echo "  link:   $dst -> $src"
}

process_template() {
  local src="$1"
  local dst="$2"

  mkdir -p "$(dirname "$dst")"

  if [ -f "$dst" ]; then
    echo "  skip:   $dst (already exists — edit manually if needed)"
    return
  fi

  sed "s|{{DOTFILES_DIR}}|${DOTFILES_DIR}|g; s|{{HOME}}|${HOME}|g" "$src" > "$dst"
  echo "  create: $dst (from template)"
}

# ============================================================
# Claude Code
# ============================================================

echo ""
echo "[Claude Code]"

link_file "$DOTFILES_DIR/claude/CLAUDE.md"         "$HOME/.claude/CLAUDE.md"

# commands: ファイル単位でリンク（既存コマンドを上書きしない）
mkdir -p "$HOME/.claude/commands"
for f in "$DOTFILES_DIR/claude/commands/"*.md; do
  fname="$(basename "$f")"
  link_file "$f" "$HOME/.claude/commands/$fname"
done

# hooks: ファイル単位でリンク
mkdir -p "$HOME/.claude/hooks"
for f in "$DOTFILES_DIR/claude/hooks/"*.sh; do
  fname="$(basename "$f")"
  link_file "$f" "$HOME/.claude/hooks/$fname"
  chmod +x "$HOME/.claude/hooks/$fname"
done

# settings.json はテンプレートから生成（上書きしない）
process_template \
  "$DOTFILES_DIR/claude/settings.json.template" \
  "$HOME/.claude/settings.json"

# ============================================================
# Gemini CLI
# ============================================================

echo ""
echo "[Gemini CLI]"

link_file "$DOTFILES_DIR/gemini/GEMINI.md"    "$HOME/.gemini/GEMINI.md"

# settings.json: 既存がなければリンク（OAuth 設定を壊さないよう上書きしない）
if [ ! -f "$HOME/.gemini/settings.json" ]; then
  link_file "$DOTFILES_DIR/gemini/settings.json" "$HOME/.gemini/settings.json"
else
  echo "  skip:   ~/.gemini/settings.json (already exists)"
fi

# ============================================================
# Codex CLI
# ============================================================

echo ""
echo "[Codex CLI]"

link_file "$DOTFILES_DIR/codex/instructions.md" "$HOME/.codex/instructions.md"

# config.toml はテンプレートから生成（上書きしない）
process_template \
  "$DOTFILES_DIR/codex/config.toml.template" \
  "$HOME/.codex/config.toml"

# rules: default.rules
mkdir -p "$HOME/.codex/rules"
if [ ! -f "$HOME/.codex/rules/default.rules" ]; then
  link_file "$DOTFILES_DIR/codex/rules/default.rules" "$HOME/.codex/rules/default.rules"
else
  echo "  skip:   ~/.codex/rules/default.rules (already exists — merge manually)"
fi

# skills: スキル単位でリンク（.system/ を汚染しない）
mkdir -p "$HOME/.codex/skills"
for skill_dir in "$DOTFILES_DIR/codex/skills/"/*/; do
  skill_name="$(basename "$skill_dir")"
  link_file "$skill_dir" "$HOME/.codex/skills/$skill_name"
done

# ============================================================
# 完了
# ============================================================

echo ""
echo "Done!"
echo ""
echo "次のステップ:"
echo "  1. ~/.claude/settings.json を確認し、不要なフックを削除してください"
echo "  2. ~/.codex/config.toml を編集し、プロジェクトの trust_level を設定してください"
echo "  3. 各プロジェクトの CLAUDE.md に '## AI レビュー設定' セクションを追加してください"
echo "     (test_command / analyze_command で sprint / review-and-merge コマンドが自動設定されます)"
