# dotfiles

Claude Code・Gemini CLI・Codex CLI の設定ファイル一式。

AI エージェントを使った開発ワークフロー（計画・実装・レビュー・品質保証）を、**モデル名ベースではなく運転モードとローカルポリシーベース**で標準化するための設定です。

## 設計思想

この dotfiles では、各 AI を「どのモデルが強いか」ではなく、**どの運転モードに向くか**で使い分けます。オーケストレーターは固定称号ではなく、タスク・ローカルポリシー・可用性・その時点の能力で選ぶ role です。現在の実運用では Codex が主に担っていますが、Claude / Gemini / Codex は同じ role schema で協調・代替できる前提にします。

| エージェント | 標準モード | 主担当 | 向いている仕事 |
|---|---|---|---|
| **Codex CLI** | Current orchestrator candidate / worker / verifier | 全体進行・実装・検証・セキュリティ | Issue/PR の自律進行、スコープが明確な実装、テスト追加、CI/CD、シェル、自動検証、レビュー反映 |
| **Claude Code** | Foreground specialist / orchestrator candidate / integrator | UX・仕様判断・大きめの統合判断 | ユーザー体験を変える判断、複数レイヤー統合、最終 diff の人間向け説明、Claude Code 固有の作業 |
| **Gemini CLI** | Policy-controlled scout / critic / optional worker | 俯瞰レビュー・計画補助 | リポジトリ横断の一貫性確認、影響範囲洗い出し、マイルストーン計画、ドキュメント/設定更新漏れ検出 |

### 基本方針

- **Orchestrator** は現在の main session が担う。いまは Codex が多いが、Claude / Gemini がより適する局面では切り替えられるよう role / schema / policy を共通化する
- **Claude / Gemini** は固定された上下関係ではなく、専門 agent / reviewer / scout / worker として協調する
- **Gemini を read-only に固定しない**。dotfiles の共有テンプレートでは安全側の scout 設定を置くが、write 可否・無効化・モデル・approval mode はローカルポリシーで上書きする
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
| `/review-and-merge [pr-number]` | 現在の PR を local policy に従う Multi-AI レビューで収束させる |
| `/implement-issue <issue-number>` | GitHub イシューを実装して PR を作成する |
| `/plan [milestone]` | イシュートリアージ・スプリント計画のみ実行する（コード実装なし） |
| `/multi-ai-research <topic>` | Claude / Gemini / Codex に同一 context packet で調査させる |

#### `/sprint` の特徴

- 実装前に **Codex + Gemini の 2系統スカウト**を実施
  - Codex: テスト戦略・セキュリティ・実装分割
  - Gemini: 既存パターン・命名一貫性・diff 外影響
- 実装担当は「モデルの強さ」ではなく、**orchestrator / worker / verifier / scout** の観点とローカルポリシーでルーティング
- Codex が実装した PR は利益相反を避けるため Codex をレビュアーから外す
- 現在の orchestrator が進行し、他 agent は必要な観点の reviewer / specialist / worker として参加する。Codex が進行する場合も、Codex 固定を目的にしない

#### `/review-and-merge` のレビュアー構成（local policy で調整）

| レビュアー | 観点 |
|-----------|------|
| Gemini CLI | repo-wide 一貫性、パターン逸脱、diff 外影響、ドキュメント/設定漏れ |
| Codex CLI | セキュリティ、エッジケース、テスト・解析コマンド実行 |
| Claude Code | 変更意図との整合、ユーザー影響、必要時の統合判断 |

---


### External AI delegation policy

Gemini / Codex / Claude CLI への delegation は `~/.codex/config.toml` の `[auto_review].policy` にある **External AI delegation exception** を満たす場合に実行します。

- trusted repository / git worktree 上で、1 ticket / 1 PR に限定
- PR title/body の ticket 参照は1つだけ（GitHub Issue は `Closes #123`、Jira 等は `[PROJ-123]`）。Claude hook は `gh pr create` / `ready` / `merge` で検査する
- コミットは1関心事ごとに分割し、「レビュー指摘対応」「address review feedback」などレビュー起点のメッセージは禁止
- ユーザーが multi-AI 協調を依頼した trusted repository では、source code は協調 context として共有可。local / private repository であることだけを理由に secret 扱いしない
- PR diff / local branch diff / workspace context packet / 関連ソース / テスト出力など必要最小限だけを渡す
- 同じ repo 質問を複数 AI に調査させる場合は、同一の sanitized workspace context packet または同一の source/diff bundle を渡す
- `.env`、credentials、tokens、private keys、shell history、無関係な repo / home directory dump は送らない
- 共有テンプレートの Gemini は安全側の plan mode を既定にするが、Gemini の無効化・write 許可・approval mode はローカルポリシーで上書きできる。Codex verifier は reviewer config を優先する
- policy deny 時は設定を弱めず、理由を記録して Claude-only fallback + local verification + CI で補完

### Codex 設定（`~/.codex/`）

| ファイル | 用途 |
|--------|------|
| `instructions.md` | Codex 全体のグローバル運用方針 |
| `agents/*.toml` | planner / architect / reviewer / spec-writer / structure-reviewer などの専門エージェント |
| `skills/*` | context resume / triage / review / research などの再利用可能スキル |
| `config.toml` | Codex CLI のローカル設定（テンプレート生成） |

AI knowledge の分類基準（rules / skills / agents / prompts / guidelines）は
`conventions/ai/knowledge-organization.md` を参照してください。

Multi-AI の role / context resume schema / 共通化方針は
`conventions/ai/multi-ai-agent-operations.md`、hook / Traceary / observability の点検基準は
`conventions/ai/agent-hooks-observability.md`、token budget の共通方針は
`conventions/ai/token-budget.md` を参照してください。

Claude / Gemini / Codex への headless 調査委譲は `scripts/multi-ai-research.sh`
（install 後は `~/.local/bin/multi-ai-research.sh`）を使い、同一の workspace
context packet を Claude / Gemini / Codex に共有して情報の偏りを避けます。
hooks / Traceary の状態確認は `scripts/audit-agent-observability.sh`
（install 後は `~/.local/bin/audit-agent-observability.sh`）で監査 bundle を作ります。

Codex で再開する場合は `codex/skills/context-resume` を使い、手書きの Claude→Codex 引き継ぎではなく、Traceary handoff / recent context / git status / PR / Issue から objective・scope・検証状態を復元します。同じ考え方を Claude / Gemini 側の orchestration にも投影できるよう、正本は `conventions/ai/multi-ai-agent-operations.md` に置きます。

#### Codex / Claude 共通スキル

| スキル | 用途 |
|--------|------|
| `structure-behavior-design` | 非自明な変更で、要求・概念モデル・責務分離・境界/IF・振る舞いテスト・TDD・構造レビューを実装前後に通す |

このスキルは、AI が要件から手続き的実装へ直行するリスクを抑えつつ、Claude / Codex / Gemini の役割分担に合わせて軽量に使えるよう調整しています。

### Gemini 設定（`~/.gemini/`）

| ファイル | 用途 |
|--------|------|
| `GEMINI.md` | Gemini 全体のグローバル運用方針 |
| `agents/*.md` | planner / reviewer / structure-reviewer などの scout / critic エージェント例 |
| `settings.json` | 安全側の plan mode を既定にしたユーザー設定。ローカル編集で上書き可 |

### Claude Code フック（`~/.claude/hooks/`）

| フック | タイミング | 内容 |
|--------|-----------|------|
| `check-gh-commands.sh` | PreToolUse | AI を GitHub コラボレーター/レビュアーとして追加するコマンドをブロック / `gh pr create --draft` 必須 / `gh pr merge` 前の Multi-AI レビューコメント必須 / `git tag` `gh release create` 抑止 |
| `check-permissions.sh` | PreToolUse | `gh auth status` で GitHub 認証を確認 |
| `check-verify-before-push.sh` | PreToolUse | analyze / test 通過の検証スタンプがない状態での `git push` / `gh pr ready` を警告 |
| `check-codex-worktree.sh` | PreToolUse | `codex exec` / `gemini`（write モード）を main / master ブランチで実行することをブロック |
| `record-verify-stamp.sh` | PostToolUse | `flutter analyze` / `flutter test` / `go vet` / `go test` / `npm test` / `npm run lint` 成功時に検証スタンプを記録（`git commit` 時にクリア） |
| `post-edit-lint.sh` | PostToolUse | ファイル編集後にリンター実行（Dart/YAML。他言語はコメントで拡張） |
| `post-write-format.sh` | PostToolUse | ファイル生成後にフォーマッター実行（Dart/YAML。他言語はコメントで拡張） |
| `stop-self-review.sh` | Stop | 停止時に未コミット差分のセルフレビューを促す |
| `stop-work-guard.sh` | Stop | 作業依頼にツール未使用で停止しようとした場合 1 回だけ継続を促す（壁打ち/完了/2 回目は素通り） |

> 各フックの詳細な挙動・スキップ条件・想定失敗パターンは `~/.claude/guidelines/harness-hooks.md` を参照してください。

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


### Agent policy override

共有 dotfiles は安全側のデフォルトを置くだけで、各 agent の最終的な使い方はローカルポリシーで決めます。`~/.config/ai-agent-policy.env` または環境変数で、Gemini を無効化したり、multi-AI 調査で使う engine を絞れます。

```bash
# 例: Gemini をこのマシンでは使わない
MULTI_AI_ENGINES=claude,codex
MULTI_AI_DISABLED_ENGINES=gemini

# 例: Gemini の headless review は plan mode に固定
MULTI_AI_GEMINI_APPROVAL_MODE=plan
MULTI_AI_GEMINI_ALLOW_WRITE=false

# 例: read-only research / scout は軽めの reasoning と小さめ packet で回す
MULTI_AI_CODEX_REASONING_EFFORT=medium
MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT=12000
MULTI_AI_MAX_FILE_BYTES=25000
MULTI_AI_MAX_TOTAL_BYTES=600000
```

`multi-ai-research.sh` はこのポリシーを読み取り、無効化された engine を skip として記録します。CLI の `--engines` は `MULTI_AI_ENGINES` をその実行だけ上書きしますが、`MULTI_AI_DISABLED_ENGINES` は安全側の deny-list として引き続き優先されます。workspace packet は既定で `MULTI_AI_MAX_FILE_BYTES=25000` / `MULTI_AI_MAX_TOTAL_BYTES=600000` に抑え、PR review では必要なら `--packet` で diff 中心の明示 context を渡します。

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

原則 MIT。

例外として、`NOTICE.md` に記載した一部の AI workflow knowledge は
`theoden9014/ai-knowledge-base` の `structure-behavior-design` knowledge pack を翻訳・要約・統合した派生物であり、CC BY-SA 4.0 として扱います。
該当ファイルは `SPDX-License-Identifier: CC-BY-SA-4.0` を付け、ライセンス参照は `LICENSES/CC-BY-SA-4.0.md` に置いています。
