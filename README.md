# dotfiles

Claude Code・Gemini CLI・Codex CLI の設定ファイル一式。

AI エージェントを使った開発ワークフロー（スプリント実行・コードレビュー・設計壁打ち）を標準化するための設定です。

## 前提条件

- [Claude Code](https://claude.ai/code) がインストール済み
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) がインストール済み（`gemini` コマンドが使えること）
- [Codex CLI](https://github.com/openai/codex) がインストール済み（`codex` コマンドが使えること）
- [GitHub CLI](https://cli.github.com/) がインストール済み（`gh auth login` 済み）
- `tmux` がインストール済み
- `python3` がインストール済み（フックが JSON パースに使用）

## インストール

```bash
git clone https://github.com/duck8823/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

dotfiles からコピーされたファイルには先頭にマネージドマーカー（`<!-- managed by duck8823/dotfiles -->`）が付きます。再実行するとマーカー付きファイルのみ上書きされ、ローカル独自ファイルはスキップされます。

## 含まれるもの

### Claude Code スラッシュコマンド（`~/.claude/commands/`）

| コマンド | 用途 |
|---------|------|
| `/sprint [issue-numbers]` | 複数の GitHub イシューを優先順位順に自律実装・レビュー・マージする |
| `/review-and-merge [pr-number]` | 現在の PR を 2-AI 並列レビュー + Claude 最終レビューでマージする |
| `/implement-issue <issue-number>` | GitHub イシューを実装して PR を作成する |
| `/plan [milestone]` | イシュートリアージ・スプリント計画のみ実行する（コード実装なし） |
| `/handoff-to-codex <task>` | Codex への引き継ぎ依頼文を標準フォーマットで生成する |

#### `/sprint` の特徴

- Codex による設計壁打ち（実装前にリポジトリを探索して設計案を作成）
- 設計結果を GitHub Issue にコメントとして永続化
- タスク特性に応じて Claude / Codex が実装を分担（UI 変更は Claude、テスト・CI/CD は Codex など）
- Codex が実装した PR は利益相反を避けるため Codex をレビュアーから除外

#### `/review-and-merge` のレビュアー構成

| レビュアー | 観点 |
|-----------|------|
| Gemini CLI | 設計・アーキテクチャ・一貫性・抜け漏れ |
| Codex CLI | セキュリティ・実装品質・テストカバレッジ |
| Claude Code | 最終判断・マージ可否 |

---

### Codex スキル（`~/.codex/skills/`）

| スキル | 用途 |
|--------|------|
| `codex-handoff` | Claude から Codex への引き継ぎ依頼文を標準フォーマットで生成 |
| `design-sparring` | 設計・アーキテクチャの壁打ち、案比較、トレードオフ整理 |
| `issue-triage` | GitHub Issues のトリアージ・優先順位付け・受け入れ条件整理 |
| `review-triage` | レビュー指摘を MUST / SHOULD / NIT に分類して対応方針を整理 |
| `tech-research` | API 仕様・ライブラリ挙動・フレームワーク更新などの技術調査 |

---

### Claude Code フック（`~/.claude/hooks/`）

| フック | タイミング | 内容 |
|--------|-----------|------|
| `check-gh-commands.sh` | PreToolUse | AI を GitHub コラボレーター/レビュアーとして追加するコマンドをブロック |
| `check-permissions.sh` | PreToolUse | `gh auth status` で GitHub 認証を確認 |
| `post-edit-lint.sh` | PostToolUse | ファイル編集後にリンター実行（Dart/YAML。他言語はコメントで拡張） |
| `post-write-format.sh` | PostToolUse | ファイル生成後にフォーマッター実行（Dart/YAML。他言語はコメントで拡張） |

---

## プロジェクトへの設定追加

`/sprint` や `/review-and-merge` はプロジェクトの `CLAUDE.md` にある `## AI レビュー設定` セクションを読み取り、テスト・解析コマンドを自動で決定します。

プロジェクトのルートで Claude Code を開き、以下をそのまま貼り付けてください:

---

```
CLAUDE.md に以下のセクションを追加してください。
source_dirs・source_extensions・source_exclude・test_command・analyze_command は
このプロジェクトの実際の構成に合わせて書き換えてください。

## AI レビュー設定

### Gemini レビュー用ソース収集
- `source_dirs`: `src/ test/`
- `source_extensions`: `ts js json`
- `source_exclude`: `*.min.js`

### Codex レビュー用コマンド
- `test_command`: `npm test`
- `analyze_command`: `npm run lint`
```

---

言語別の例:

| 言語/フレームワーク | `test_command` | `analyze_command` | `source_extensions` |
|-------------------|----------------|-------------------|---------------------|
| Flutter/Dart | `flutter test` | `flutter analyze` | `dart arb yaml` |
| Node.js/TypeScript | `npm test` | `npm run lint` | `ts js json` |
| Go | `go test ./...` | `go vet ./...` | `go` |
| Python | `pytest` | `ruff check .` | `py` |
| Ruby on Rails | `bundle exec rspec` | `bundle exec rubocop` | `rb erb` |

## ローカルオーバーライド

マシンごとに dotfiles のデフォルト動作を上書きできます。

### ルールのオーバーライド

`~/.claude/rules/` にマネージドマーカーなしの `.md` ファイルを作成すると、CLAUDE.md のルールを上書きできます。`install.sh` を再実行してもスキップされます。

```bash
# 例: 自動マージを禁止するオーバーライド
cat > ~/.claude/rules/no-auto-merge.md << 'EOF'
# 自動マージ禁止

- Claude が `gh pr merge` を自発的に実行してはならない
- AI レビュー完了後は `gh pr ready` で ready for review にし、ユーザーが APPROVE & マージする
EOF
```

### dotfiles 管理ファイルのローカル上書き

dotfiles 管理のファイルをローカルで上書きするには、対象ファイルの先頭行のマネージドマーカーを削除してから編集してください。`install.sh` を再実行してもスキップされます。

## カスタマイズ

### フックの調整

インストール後、`~/.claude/settings.json` を確認して不要なフックを削除してください。

フックファイル（`~/.claude/hooks/*.sh`）を直接編集して、プロジェクトで使う言語に合わせたリンター・フォーマッターを有効化してください（コメントアウトで言語別の例が入っています）。

### Codex の設定

`~/.codex/config.toml` でプロジェクトごとの `trust_level` を設定してください。

### Gemini の設定

`~/.gemini/settings.json` は既存ファイルがある場合は上書きしません（OAuth 設定を保護するため）。

## ライセンス

MIT
