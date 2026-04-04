# dotfiles

Claude Code・Gemini CLI・Codex CLI の設定ファイル一式。

AI エージェントを使った開発ワークフロー（計画・実装・レビュー・品質保証）を、**モデル名ベースではなく運転モードベース**で標準化するための設定です。

## 設計思想

この dotfiles では、各 AI を「どのモデルが強いか」ではなく、**どの運転モードに向くか**で使い分けます。

| エージェント | 基本モード | 主担当 | 向いている仕事 |
|---|---|---|---|
| **Claude Code** | Foreground orchestrator | 実装・統合判断・最終レビュー | UX を含む仕様判断、複数レイヤー統合、最終 diff 判断、マージゲート |
| **Codex CLI** | Background worker / verifier | 実装補助・検証・セキュリティ | スコープが明確な実装、テスト追加、CI/CD、シェル、自動検証、セキュリティレビュー |
| **Gemini CLI** | Read-only scout / critic | 俯瞰レビュー・計画補助 | リポジトリ横断の一貫性確認、影響範囲洗い出し、マイルストーン計画、ドキュメント/設定更新漏れ検出 |

### 基本方針

- **Claude** はユーザー価値と最終責任を持つメイン操縦席
- **Codex** は isolated branch / worktree 前提の worker・validator
- **Gemini** は plan/read-only 前提の scout・critic
- ベンチマークではなく、**失敗率・再現性・レビュー品質・割り込み耐性**で運用判断する

## 前提条件

- [Claude Code](https://claude.ai/code) がインストール済み
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) がインストール済み（`gemini` コマンドが使えること）
- [Codex CLI](https://github.com/openai/codex) がインストール済み（`codex` コマンドが使えること）
- [GitHub CLI](https://cli.github.com/) がインストール済み（`gh auth login` 済み）
- `tmux` がインストール済み
- `python3` がインストール済み（フックや補助スクリプトで使用）

## インストール

```bash
git clone https://github.com/duck8823/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

dotfiles からコピーされたファイルには先頭にマネージドマーカー（`<!-- managed by duck8823/dotfiles -->` など）が付きます。再実行するとマーカー付きファイルのみ上書きされ、ローカル独自ファイルはスキップされます。

`~/.claude/settings.json` / `~/.gemini/settings.json` / `~/.codex/config.toml` のような**ユーザー設定ファイル**は、インストーラが内容ハッシュを追跡します。

- ローカル未編集なら再実行時に自動更新
- ローカル編集のみならそのまま保持
- dotfiles 更新とローカル編集が衝突した場合は `*.dotfiles-new` を生成

## 含まれるもの

### Claude Code スラッシュコマンド（`~/.claude/commands/`）

| コマンド | 用途 |
|---------|------|
| `/sprint [issue-numbers]` | 複数の GitHub イシューを優先順位順に自律実装・レビュー・マージする |
| `/review-and-merge [pr-number]` | 現在の PR を Multi-AI レビュー + Claude 最終判断でマージする |
| `/implement-issue <issue-number>` | GitHub イシューを実装して PR を作成する |
| `/plan [milestone]` | イシュートリアージ・スプリント計画のみ実行する（コード実装なし） |
| `/handoff-to-codex <task>` | Codex への引き継ぎ依頼文を標準フォーマットで生成する |

#### `/sprint` の特徴

- 実装前に **Codex + Gemini の 2系統スカウト**を実施
  - Codex: テスト戦略・セキュリティ・実装分割
  - Gemini: 既存パターン・命名一貫性・diff 外影響
- 実装担当は「モデルの強さ」ではなく、**Foreground orchestration / Background worker / Read-only scout** の観点でルーティング
- Codex が実装した PR は利益相反を避けるため Codex をレビュアーから外す
- Claude は最終統合判断とマージゲートに専念する

#### `/review-and-merge` のレビュアー構成

| レビュアー | 観点 |
|-----------|------|
| Gemini CLI | repo-wide 一貫性、パターン逸脱、diff 外影響、ドキュメント/設定漏れ |
| Codex CLI | セキュリティ、エッジケース、テスト・解析コマンド実行 |
| Claude Code | 変更意図との整合、ユーザー影響、最終マージ可否 |

---

### Codex 設定（`~/.codex/`）

| ファイル | 用途 |
|--------|------|
| `instructions.md` | Codex 全体のグローバル運用方針 |
| `agents/*.toml` | planner / architect / reviewer / spec-writer の専門エージェント |
| `skills/*` | handoff / triage / review / research などの再利用可能スキル |
| `config.toml` | Codex CLI のローカル設定（テンプレート生成） |

### Gemini 設定（`~/.gemini/`）

| ファイル | 用途 |
|--------|------|
| `GEMINI.md` | Gemini 全体のグローバル運用方針 |
| `agents/*.md` | planner / architect / reviewer / spec-writer の専門エージェント |
| `settings.json` | read-only scout 運用向けのユーザー設定 |

### Claude Code フック（`~/.claude/hooks/`）

| フック | タイミング | 内容 |
|--------|-----------|------|
| `check-gh-commands.sh` | PreToolUse | AI を GitHub コラボレーター/レビュアーとして追加するコマンドをブロック |
| `check-permissions.sh` | PreToolUse | `gh auth status` で GitHub 認証を確認 |
| `post-edit-lint.sh` | PostToolUse | ファイル編集後にリンター実行（Dart/YAML。他言語はコメントで拡張） |
| `post-write-format.sh` | PostToolUse | ファイル生成後にフォーマッター実行（Dart/YAML。他言語はコメントで拡張） |
| `stop-self-review.sh` | Stop | 停止時に未コミット差分のセルフレビューを促す |

> `~/.claude/settings.json` は **インストール済みの `~/.claude/hooks/*.sh` を参照**するため、ローカルでフックを調整した内容がそのまま反映されます。

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
- `source_dirs`: `src/ test/ docs/`
- `source_extensions`: `ts js json md`
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
| Node.js/TypeScript | `npm test` | `npm run lint` | `ts js json md` |
| Go | `go test ./...` | `go vet ./...` | `go md` |
| Python | `pytest` | `ruff check .` | `py md toml` |
| Ruby on Rails | `bundle exec rspec` | `bundle exec rubocop` | `rb erb yml md` |

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

JSON ファイル（`cmux.json` 等）はコメント非対応のため、サイドカーファイル（`.managed`）で管理されています。ローカルで上書きするには、対象ファイルの横にある `.managed` ファイルを削除してください（例: `rm ~/.config/cmux/cmux.json.managed`）。

## カスタマイズ

### フックの調整

インストール後、`~/.claude/settings.json` を確認して不要なフックを削除してください。

フックファイル（`~/.claude/hooks/*.sh`）を直接編集して、プロジェクトで使う言語に合わせたリンター・フォーマッターを有効化してください（コメントアウトで言語別の例が入っています）。

### Codex の設定

`~/.codex/config.toml` でプロジェクトごとの `trust_level` を設定してください。
installer は `~/.codex/config.toml.managed.sha256` を使って追跡し、競合時は `~/.codex/config.toml.dotfiles-new` を生成します。

### Gemini の設定

`~/.gemini/settings.json` は installer が内容ハッシュを追跡します。
dotfiles 側の更新とローカル編集が衝突した場合は `~/.gemini/settings.json.dotfiles-new` を確認してください。

## 既存ユーザー向けメモ

現行 installer は以下のファイルを**差分追跡つきで同期**します。

- `~/.claude/settings.json`
- `~/.gemini/settings.json`
- `~/.codex/config.toml`

ローカル未編集なら `./install.sh` の再実行で自動更新されます。
ローカル編集と dotfiles 更新が衝突した場合は、次の候補ファイルが生成されます。

- `~/.claude/settings.json.dotfiles-new`
- `~/.gemini/settings.json.dotfiles-new`
- `~/.codex/config.toml.dotfiles-new`

旧バージョンから移行済みで追跡情報がまだない場合も、installer は既存設定を壊さずに候補ファイルを生成します。

## ライセンス

MIT
