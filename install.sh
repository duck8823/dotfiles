#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
MANAGED_TAG="managed by duck8823/dotfiles"

# ============================================================
# ユーティリティ
# ============================================================

# ファイル拡張子からマーカーコメント形式を判定
# JSON はコメント非対応のため空文字を返す（サイドカーファイルで管理）
marker_for() {
  local file="$1"
  local base
  base="$(basename "$file")"

  # Codex の SKILL.md は YAML frontmatter が先頭必須のためマーカーを埋め込まない
  if [ "$base" = "SKILL.md" ]; then
    echo ""
    return
  fi

  case "$file" in
    *.json)    echo "" ;;
    *.yaml|*.yml) echo "# $MANAGED_TAG" ;;
    *.toml)    echo "# $MANAGED_TAG" ;;
    *.sh)      echo "# $MANAGED_TAG" ;;
    *.rules)   echo "# $MANAGED_TAG" ;;
    *.ghostty) echo "# $MANAGED_TAG" ;;
    *)         echo "<!-- $MANAGED_TAG -->" ;;
  esac
}

# マネージドマーカー付きコピー
# - マーカー付き既存ファイル → 上書き
# - マーカーなし既存ファイル → スキップ（ローカル独自ファイル）
# - 既存シンボリックリンク → 削除してコピーに置き換え
# - ファイルなし → 新規コピー
copy_managed() {
  local src="$1"
  local dst="$2"
  local marker
  marker="$(marker_for "$dst")"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  mkdir -p "$dst_dir"

  # 既存シンボリックリンク → 削除してコピーに移行
  if [ -L "$dst" ]; then
    rm "$dst"
    echo "  unlink: $dst (migrating from symlink to copy)"
  fi

  if [ -f "$dst" ]; then
    if [ -z "$marker" ]; then
      # JSON / SKILL.md 等コメント非対応: サイドカーファイルで管理判定
      # 旧方式（先頭マーカー）からの移行は許可する
      if [ ! -f "${dst}.managed" ] && ! head -1 "$dst" | grep -qF "$MANAGED_TAG"; then
        echo "  skip:   $dst (local override — no .managed sidecar)"
        return
      fi
    else
      # マーカーなし → ローカル独自ファイル、スキップ
      if ! head -1 "$dst" | grep -qF "$MANAGED_TAG"; then
        echo "  skip:   $dst (local override — no managed marker)"
        return
      fi
    fi
  fi

  if [ -z "$marker" ]; then
    # JSON 等: マーカーなしでコピー + サイドカーファイル作成
    cp "$src" "$dst"
    echo "$MANAGED_TAG" > "${dst}.managed"
  else
    # マーカーを先頭に付けてコピー
    {
      echo "$marker"
      cat "$src"
    } > "$dst"
  fi
  echo "  copy:   $dst"
}

# マネージドマーカー付きディレクトリコピー（skills 用）
# ディレクトリ内の全ファイルにマーカーを付けてコピーする
copy_managed_dir() {
  local src_dir="$1"
  local dst_dir="$2"

  mkdir -p "$dst_dir"

  # 既存シンボリックリンク → 削除
  if [ -L "$dst_dir" ]; then
    rm "$dst_dir"
    mkdir -p "$dst_dir"
    echo "  unlink: $dst_dir (migrating from symlink to copy)"
  fi

  # ディレクトリ内のファイルを再帰コピー
  local src_dir_clean="${src_dir%/}"
  find "$src_dir_clean" -type f -print0 | while IFS= read -r -d '' src_file; do
    local rel="${src_file#"${src_dir_clean}"/}"
    local dst_file="$dst_dir/$rel"
    copy_managed "$src_file" "$dst_file"
  done
}

# シェルスクリプト用コピー（shebang を維持しつつマーカーを挿入）
copy_managed_sh() {
  local src="$1"
  local dst="$2"
  local marker
  marker="$(marker_for "$dst")"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  mkdir -p "$dst_dir"

  if [ -L "$dst" ]; then
    rm "$dst"
    echo "  unlink: $dst (migrating from symlink to copy)"
  fi

  if [ -f "$dst" ]; then
    if ! head -2 "$dst" | grep -qF "$MANAGED_TAG"; then
      echo "  skip:   $dst (local override — no managed marker)"
      return
    fi
  fi

  # shebang を維持しつつマーカーを挿入
  local first_line
  first_line="$(head -1 "$src")"
  if [[ "$first_line" == "#!"* ]]; then
    {
      echo "$first_line"
      echo "$marker"
      tail -n +2 "$src"
    } > "$dst"
  else
    {
      echo "$marker"
      cat "$src"
    } > "$dst"
  fi
  chmod +x "$dst"
  echo "  copy:   $dst"
}

render_template() {
  local src="$1"
  sed "s|{{DOTFILES_DIR}}|${DOTFILES_DIR}|g; s|{{HOME}}|${HOME}|g" "$src"
}

install_managed_copy() {
  local src="$1"
  local dst="$2"

  if [ -L "$dst" ]; then
    rm "$dst"
    echo "  unlink: $dst (migrating from symlink to copy)"
  fi

  cp "$src" "$dst"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
    return
  fi

  echo "sha256 calculator not found: install shasum, sha256sum, or openssl" >&2
  return 1
}

sync_managed_settings() {
  local src="$1"
  local dst="$2"
  local mode="${3:-copy}"  # copy | template
  local dst_dir state_file candidate_file tmp_file
  local current_hash rendered_hash tracked_hash

  dst_dir="$(dirname "$dst")"
  state_file="${dst}.managed.sha256"
  candidate_file="${dst}.dotfiles-new"
  tmp_file="$(mktemp)"

  mkdir -p "$dst_dir"

  if [ "$mode" = "template" ]; then
    render_template "$src" > "$tmp_file"
  else
    cp "$src" "$tmp_file"
  fi

  rendered_hash="$(sha256_file "$tmp_file")"

  if [ ! -f "$dst" ]; then
    install_managed_copy "$tmp_file" "$dst"
    printf '%s\n' "$rendered_hash" > "$state_file"
    rm -f "$candidate_file" "$tmp_file"
    echo "  create: $dst"
    return
  fi

  current_hash="$(sha256_file "$dst")"

  if [ -f "$state_file" ]; then
    tracked_hash="$(cat "$state_file")"

    if [ "$current_hash" = "$tracked_hash" ]; then
      if [ "$rendered_hash" = "$tracked_hash" ]; then
        if [ -L "$dst" ]; then
          install_managed_copy "$tmp_file" "$dst"
          echo "  update: $dst (migrated from symlink to copy)"
        else
          echo "  keep:   $dst (already up to date)"
        fi
      else
        install_managed_copy "$tmp_file" "$dst"
        echo "  update: $dst"
      fi
      printf '%s\n' "$rendered_hash" > "$state_file"
      rm -f "$candidate_file" "$tmp_file"
      return
    fi

    if [ "$rendered_hash" = "$tracked_hash" ]; then
      echo "  keep:   $dst (local edits preserved)"
      rm -f "$candidate_file" "$tmp_file"
      return
    fi

    cp "$tmp_file" "$candidate_file"
    rm -f "$tmp_file"
    echo "  merge:  $dst (review ${candidate_file})"
    return
  fi

  if [ "$current_hash" = "$rendered_hash" ]; then
    if [ -L "$dst" ]; then
      install_managed_copy "$tmp_file" "$dst"
    fi
    printf '%s\n' "$rendered_hash" > "$state_file"
    rm -f "$candidate_file" "$tmp_file"
    echo "  track:  $dst (managed settings baseline created)"
    return
  fi

  cp "$tmp_file" "$candidate_file"
  rm -f "$tmp_file"
  echo "  merge:  $dst (existing file differs; review ${candidate_file})"
}

# ============================================================
# Claude Code
# ============================================================

echo ""
echo "[Claude Code]"

copy_managed "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

# commands
mkdir -p "$HOME/.claude/commands"
for f in "$DOTFILES_DIR/claude/commands/"*.md; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed "$f" "$HOME/.claude/commands/$fname"
done

# hooks
mkdir -p "$HOME/.claude/hooks"
for f in "$DOTFILES_DIR/claude/hooks/"*.sh; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed_sh "$f" "$HOME/.claude/hooks/$fname"
done

# agents
mkdir -p "$HOME/.claude/agents"
for f in "$DOTFILES_DIR/claude/agents/"*.md; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed "$f" "$HOME/.claude/agents/$fname"
done

# guidelines
mkdir -p "$HOME/.claude/guidelines"
for f in "$DOTFILES_DIR/claude/guidelines/"*.md; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed "$f" "$HOME/.claude/guidelines/$fname"
done

# skills: ディレクトリ単位でコピー
mkdir -p "$HOME/.claude/skills"
for skill_dir in "$DOTFILES_DIR/claude/skills/"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  copy_managed_dir "$skill_dir" "$HOME/.claude/skills/$skill_name"
done

# rules
mkdir -p "$HOME/.claude/rules"
for f in "$DOTFILES_DIR/claude/rules/"*.md; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed "$f" "$HOME/.claude/rules/$fname"
done

# settings.json は差分追跡しつつ同期する
sync_managed_settings \
  "$DOTFILES_DIR/claude/settings.json.template" \
  "$HOME/.claude/settings.json" \
  "template"

# ============================================================
# Gemini CLI
# ============================================================

echo ""
echo "[Gemini CLI]"

copy_managed "$DOTFILES_DIR/gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md"

# agents
mkdir -p "$HOME/.gemini/agents"
for f in "$DOTFILES_DIR/gemini/agents/"*.md; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed "$f" "$HOME/.gemini/agents/$fname"
done

# hooks
mkdir -p "$HOME/.gemini/hooks"
for f in "$DOTFILES_DIR/gemini/hooks/"*.sh; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed_sh "$f" "$HOME/.gemini/hooks/$fname"
done

# settings.json は差分追跡しつつ同期する（テンプレートから生成）
sync_managed_settings \
  "$DOTFILES_DIR/gemini/settings.json.template" \
  "$HOME/.gemini/settings.json" \
  "template"

# ============================================================
# Codex CLI
# ============================================================

echo ""
echo "[Codex CLI]"

copy_managed "$DOTFILES_DIR/codex/instructions.md" "$HOME/.codex/instructions.md"

# agents
mkdir -p "$HOME/.codex/agents"
for f in "$DOTFILES_DIR/codex/agents/"*.toml; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed "$f" "$HOME/.codex/agents/$fname"
done

# config.toml は差分追跡しつつ同期する
sync_managed_settings \
  "$DOTFILES_DIR/codex/config.toml.template" \
  "$HOME/.codex/config.toml" \
  "template"

# rules: default.rules
mkdir -p "$HOME/.codex/rules"
copy_managed "$DOTFILES_DIR/codex/rules/default.rules" "$HOME/.codex/rules/default.rules"

# hooks
mkdir -p "$HOME/.codex/hooks"
for f in "$DOTFILES_DIR/codex/hooks/"*.sh; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  copy_managed_sh "$f" "$HOME/.codex/hooks/$fname"
done

# hooks.json は差分追跡しつつ同期する（テンプレートから生成）
sync_managed_settings \
  "$DOTFILES_DIR/codex/hooks.json" \
  "$HOME/.codex/hooks.json" \
  "template"

# skills: スキル単位でコピー（.system/ を汚染しない）
mkdir -p "$HOME/.codex/skills"
for skill_dir in "$DOTFILES_DIR/codex/skills/"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  copy_managed_dir "$skill_dir" "$HOME/.codex/skills/$skill_name"
done

# ============================================================
# memories.sh
# ============================================================

echo ""
echo "[memories.sh]"

if command -v pnpm &>/dev/null; then
  # グローバルインストール（MCP serve 時の起動を高速化）
  if ! command -v memories &>/dev/null; then
    echo "  install: memories.sh をグローバルインストールします"
    pnpm add -g @memories.sh/cli
  else
    echo "  skip:    memories.sh はインストール済み ($(memories --version 2>/dev/null || echo 'unknown'))"
  fi

  # 初期セットアップ（local.db + セマンティック検索モデル）
  # --minimal-local -y: MCP 自動設定をスキップ（テンプレートで管理するため）
  if [ ! -f "$HOME/.config/memories/local.db" ]; then
    echo "  setup:   memories.sh を初期化します"
    memories setup --minimal-local -y || echo "  warn:    memories.sh の初期化に失敗しました"
  else
    echo "  skip:    memories.sh は初期化済み"
  fi

  # generate: 静的ベースラインを各ツールの設定ファイルに反映
  # MCP serve のフォールバックとして、記憶をファイルに埋め込む
  echo "  generate: 静的ベースラインを生成します"
  memories generate all --force 2>/dev/null || true

  # compact / consolidate の定期実行（launchd）
  MEMORIES_PLIST_DIR="$HOME/Library/LaunchAgents"
  MEMORIES_COMPACT_PLIST="$MEMORIES_PLIST_DIR/sh.memories.compact.plist"
  MEMORIES_CONSOLIDATE_PLIST="$MEMORIES_PLIST_DIR/sh.memories.consolidate.plist"
  MEMORIES_BIN="$(command -v memories)"

  if [ ! -f "$MEMORIES_COMPACT_PLIST" ]; then
    mkdir -p "$MEMORIES_PLIST_DIR"
    cat > "$MEMORIES_COMPACT_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>sh.memories.compact</string>
  <key>ProgramArguments</key>
  <array>
    <string>${MEMORIES_BIN}</string>
    <string>compact</string>
    <string>run</string>
    <string>--inactivity-minutes</string>
    <string>60</string>
  </array>
  <key>StartInterval</key>
  <integer>1800</integer>
  <key>StandardOutPath</key>
  <string>${HOME}/.config/memories/compact.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.config/memories/compact.log</string>
</dict>
</plist>
PLIST
    launchctl load "$MEMORIES_COMPACT_PLIST" 2>/dev/null || true
    echo "  launchd: memories compact を30分ごとに実行"
  else
    echo "  skip:    memories compact の launchd は設定済み"
  fi

  if [ ! -f "$MEMORIES_CONSOLIDATE_PLIST" ]; then
    cat > "$MEMORIES_CONSOLIDATE_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>sh.memories.consolidate</string>
  <key>ProgramArguments</key>
  <array>
    <string>${MEMORIES_BIN}</string>
    <string>consolidate</string>
    <string>run</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>3</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>${HOME}/.config/memories/consolidate.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.config/memories/consolidate.log</string>
</dict>
</plist>
PLIST
    launchctl load "$MEMORIES_CONSOLIDATE_PLIST" 2>/dev/null || true
    echo "  launchd: memories consolidate を毎日 3:00 に実行"
  else
    echo "  skip:    memories consolidate の launchd は設定済み"
  fi

else
  echo "  skip:   pnpm が見つからないため memories.sh をスキップ"
  echo "          pnpm をインストール後に再実行してください"
fi

# ============================================================
# cmux
# ============================================================

echo ""
echo "[cmux]"

CMUX_CONFIG_DIR="$HOME/Library/Application Support/com.cmuxterm.app"

if [ -d "/Applications/cmux.app" ]; then
  mkdir -p "$HOME/.config/cmux"
  copy_managed "$DOTFILES_DIR/cmux/cmux.json" "$HOME/.config/cmux/cmux.json"
  mkdir -p "$CMUX_CONFIG_DIR"
  copy_managed "$DOTFILES_DIR/cmux/config.ghostty" "$CMUX_CONFIG_DIR/config.ghostty"
else
  echo "  skip:   cmux not installed (/Applications/cmux.app not found)"
fi

# ============================================================
# 完了
# ============================================================

echo ""
echo "Done!"
echo ""
echo "================================================================"
echo " ローカルオーバーライドの方法"
echo "================================================================"
echo ""
echo "  dotfiles からコピーされたファイルには先頭にマネージドマーカーが付きます。"
echo "  install.sh を再実行すると、マーカー付きファイルのみ上書きされます。"
echo ""
echo "  ローカルで独自のルールを追加するには:"
echo "    1. マーカーなしの .md ファイルを ~/.claude/rules/ に作成"
echo "    2. install.sh を再実行してもスキップされます"
echo ""
echo "  例: 自動マージを禁止するオーバーライド"
echo "    ~/.claude/rules/no-auto-merge.md"
echo ""
echo "  dotfiles 管理のファイルをローカルで上書きするには:"
echo "    1. 対象ファイルの先頭行のマネージドマーカーを削除"
echo "    2. 内容を自由に編集"
echo "    3. install.sh を再実行してもスキップされます"
echo ""
echo "================================================================"
echo ""
echo " 管理対象の settings / config ファイルは内容ハッシュを追跡します。"
echo " ローカル未編集なら再実行時に自動更新されます。"
echo " ローカル編集と dotfiles 更新が衝突した場合は *.dotfiles-new を生成します。"
echo ""
echo " 例:"
echo "    ~/.claude/settings.json.dotfiles-new"
echo "    ~/.gemini/settings.json.dotfiles-new"
echo "    ~/.codex/config.toml.dotfiles-new"
echo ""
echo "================================================================"
echo ""
echo " 次のステップ"
echo "================================================================"
echo ""
echo "【1】フック設定を確認する（手動）"
echo ""
echo "  ~/.claude/settings.json を開いて不要なフックを削除してください。"
echo "  ~/.claude/hooks/*.sh を編集して、使用言語のリンター/フォーマッターを有効化してください。"
echo "  ~/.codex/config.toml を編集して、プロジェクトの trust_level を設定してください。"
echo ""
echo "----------------------------------------------------------------"
echo ""
echo "【2】各プロジェクトに AI レビュー設定を追加する"
echo ""
echo "  プロジェクトのルートで Claude Code を開き、以下をそのまま貼り付けてください:"
echo ""
echo "  ┌──────────────────────────────────────────────────────────────"
cat << 'PROMPT'
  │ CLAUDE.md に以下のセクションを追加してください。
  │ source_dirs・source_extensions・source_exclude・test_command・analyze_command は
  │ このプロジェクトの実際の構成に合わせて書き換えてください。
  │
  │ ## AI レビュー設定
  │
  │ ### Gemini レビュー用ソース収集
  │ - `source_dirs`: `src/ test/`
  │ - `source_extensions`: `ts js json`
  │ - `source_exclude`: `*.min.js`
  │
  │ ### Codex レビュー用コマンド
  │ - `test_command`: `npm test`
  │ - `analyze_command`: `npm run lint`
PROMPT
echo "  └──────────────────────────────────────────────────────────────"
echo ""
echo "  言語別の例:"
echo "    Flutter:    test_command=flutter test  analyze_command=flutter analyze  extensions=dart arb yaml"
echo "    TypeScript: test_command=npm test      analyze_command=npm run lint     extensions=ts js json"
echo "    Go:         test_command=go test ./... analyze_command=go vet ./...     extensions=go"
echo "    Python:     test_command=pytest        analyze_command=ruff check .     extensions=py"
echo ""
echo "----------------------------------------------------------------"
echo ""
echo "【3】memories.sh にプロジェクトのルールを取り込む"
echo ""
echo "  各プロジェクトのルートで以下を実行してください:"
echo ""
echo "    memories ingest claude    # CLAUDE.md のルールを取り込み"
echo "    memories ingest codex     # CODEX.md のルールを取り込み"
echo "    memories ingest gemini    # GEMINI.md のルールを取り込み"
echo ""
echo "================================================================"
