# AI CLI 連携（Gemini / Codex の呼び出し）

## 原則

- **Claude** は foreground orchestrator として使う
- **Codex** は background worker / verifier として使う
- **Gemini** は read-only scout / critic として使う
- すべて **ヘッドレス実行** を基本とする
- 書き込みタスクは isolated branch / worktree 前提

## ヘッドレス実行コマンド

| ツール | 目的 | コマンド例 | 補足 |
|--------|------|-----------|------|
| Codex | review / plan / worker | `codex exec --full-auto - < <prompt> \| tee <file>` | `-c 'agents.default.config_file=...'` で役割付与 |
| Gemini | scout / review / planning | `gemini --approval-mode plan -p ' ' -e none < <prompt> 2>&1 \| tee <output>` | `GEMINI_SYSTEM_MD=...` で役割付与 |

> `gemini -e none` は公式にサポートされた「拡張を無効化する」指定。旧来の `-e ''` は使わない。

## 運用ルール

### Gemini
- 既定は `--approval-mode plan`（read-only）
- repo-wide scan、既存パターン比較、docs / config / l10n drift 検出に使う
- 書き込みをさせるのは、明示的に許可した isolated worktree 実験時のみ
- **自律レビュー中のブラウザ認証禁止**: headless 実行で `Opening authentication page in your browser` / `Do you want to continue?` が出たら、その場で Gemini プロセスを停止し、ブラウザを開かずフォールバックする
- **headless 事前確認**: multi-AI review 前に短い read-only prompt をタイムアウト付きで実行し、認証プロンプト・空出力・quota を先に検出する。`gemini --version` だけでは認証可否の確認にならない
- **1プロンプト1質問**: 複合的な質問（多項目チェック等）ではツールエラー後にリカバリできず空出力で終了する。質問は短く単一にして個別実行する
- **クォータ枯渇のサイレント失敗**: 連続実行で `429 QUOTA_EXHAUSTED` が発生しても exit code 0 で終了し出力が空になる。出力ファイルが空の場合はクォータ枯渇を疑う

### Codex
- scoped 実装、テスト、CI/CD、セキュリティ、シェル自動化に使う
- 実装タスクでは dedicated branch / worktree を使う
- 返却させる内容は **変更ファイル / 実行コマンド / 残リスク**
- **固定ロール/モデル非互換**: `reviewer` / `qa` などのサブエージェントロールがアカウント種別と非互換な固定モデルで失敗する場合がある。その場合は同じ依頼を `agent_type` 未指定の default subagent、またはメインセッションの直接検証にフォールバックする
- **sandbox 制約**: `go test` / `golangci-lint` 等のビルドキャッシュを使うツールは sandbox でブロックされる場合がある。read-only レビュータスクではプロンプトに「テスト・ビルド実行禁止。ソースコードを読んでレビューせよ」を明示する
- **スキル自動ロード**: `~/.codex/skills/` のスキルがプロンプトより優先される場合がある。レビュー等の明確なタスクでは、プロンプト冒頭に目的を強調して記載する

### Claude
- subagents / Task は sidecar 調査に使う
- マージ判断とユーザー影響の最終責任はメインセッションが持つ

## エージェント指定付き実行

### Codex（TOML エージェント定義を使用）
```bash
CODEX_AGENT=$HOME/.codex/agents/<agent-name>.toml
codex exec --full-auto \
  -c "agents.default.config_file=\"$CODEX_AGENT\"" \
  - < /tmp/<agent>-prompt.md 2>/tmp/<agent>.err | tee /tmp/<agent>-result.json
```

### Gemini（MD エージェント定義をシステムプロンプトとして使用）
```bash
GEMINI_SYSTEM_MD=$HOME/.gemini/agents/<agent-name>.md \
  TERM=xterm-256color \
  gemini --approval-mode plan -p ' ' -e none \
  < /tmp/<agent>-prompt.md 2>&1 | tee /tmp/<agent>-result.json
```

## worktree 運用

### Claude サブエージェント
- `isolation: worktree` が設定済み（architect, designer, reviewer）
- 自動的に worktree で実行されるため、追加設定不要

### Codex write タスク
- `main` 直下ではなく feature branch / dedicated worktree で実行する
- 実装スコープが広い場合は branch ではなく worktree を優先する

```bash
# worktree を作成してから Codex を実行
git worktree add .codex-work/<task-name> -b codex/<task-name>
cd .codex-work/<task-name>
codex exec --full-auto \
  -c "agents.default.config_file=\"$CODEX_AGENT\"" \
  - < /tmp/codex-prompt.md 2>/tmp/codex.err | tee /tmp/codex-result.json
```

### Gemini 実験タスク
Gemini で例外的に書き込みを試す場合だけ、公式 worktree 機能を使う。

```bash
gemini --worktree <task-name>
```

ただし dotfiles の標準運用では、Gemini を実装担当にしない。

## 並列実行方式

### 第一選択: cmux（推奨）

cmux を使って Codex / Gemini を複数ペインで並列実行する。結果はファイル出力で回収し、Claude メインセッションが統合する。

```bash
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
CODEX_AGENT=$HOME/.codex/agents/architect.toml
$CMUX new-workspace --cwd "$(pwd)"

SURFACE_RIGHT=$($CMUX new-split right)

$CMUX send --surface surface:1 "codex exec --full-auto \
  -c \"agents.default.config_file=\\\"$CODEX_AGENT\\\"\" \
  - < /tmp/codex-architect.md 2>/tmp/codex-architect.err | tee /tmp/codex-architect-result.json && echo DONE"
$CMUX send-key --surface surface:1 Return

$CMUX send --surface "$SURFACE_RIGHT" "GEMINI_SYSTEM_MD=$HOME/.gemini/agents/reviewer.md \
  TERM=xterm-256color \
  gemini --approval-mode plan -p ' ' -e none \
  < /tmp/gemini-architect.md 2>&1 | tee /tmp/gemini-architect-result.json && echo DONE"
$CMUX send-key --surface "$SURFACE_RIGHT" Return
# DONE は tee の完了を示す。ツール本体の成否は結果ファイルの内容で判断する
```

### 第二選択: Bash バックグラウンド実行

```bash
set -o pipefail  # パイプ左辺の失敗を検出するために必須

CODEX_AGENT=$HOME/.codex/agents/architect.toml
codex exec --full-auto \
  -c "agents.default.config_file=\"$CODEX_AGENT\"" \
  - < /tmp/codex-architect.md 2>/tmp/codex-architect.err | tee /tmp/codex-architect-result.json &
PID_CODEX=$!

GEMINI_SYSTEM_MD=$HOME/.gemini/agents/reviewer.md \
  TERM=xterm-256color \
  gemini --approval-mode plan -p ' ' -e none \
  < /tmp/gemini-architect.md 2>&1 | tee /tmp/gemini-architect-result.json &
PID_GEMINI=$!

wait $PID_CODEX $PID_GEMINI
# pipefail 有効でも空出力のケースがあるため、ファイルサイズでも検証する
[[ -s /tmp/codex-architect-result.json ]] || echo "WARN: Codex result empty"
[[ -s /tmp/gemini-architect-result.json ]] || echo "WARN: Gemini result empty"
```

### 第三選択: tmux（レガシー）

- `TERM=xterm-256color` を必ず設定する
- プロンプトは必ずファイルに書き出してから stdin で渡す
- 対話モード（`codex` / `gemini`）は使わない

## エラーハンドリング

- Codex は stderr を別ファイルに保存する。Gemini は `2>&1 | tee` で統合キャプチャする（応答テキストが stderr に混在するため）
- 失敗時は1回だけリトライ、2回目失敗でスキップして失敗を記録
- Codex を非リポジトリで使う場合は `--skip-git-repo-check` を付ける
- タイムアウト・JSON不正・空出力は統合ログに残す

## フォールバックマトリクス

| 障害種別 | 検出方法 | 対応 |
|---|---|---|
| **Codex タイムアウト** | 結果ファイルが空のまま 10分超過 | 1回リトライ → Claude が直接実行 |
| **Gemini タイムアウト** | 同上 | 1回リトライ → Codex scout で代替 |
| **Gemini headless 認証待ち** | 出力ファイルに `Opening authentication page in your browser` / `Do you want to continue?` | ブラウザを開かずプロセス停止 → Codex scout / default subagent で代替 |
| **Codex fixed-role model failure** | subagent エラーに `model is not supported` | `agent_type` 未指定の default subagent で再実行 → 失敗時はメインセッションで直接検証 |
| **Codex capacity failure** | stderr ファイルに `rate_limit` / `capacity` | 30秒待ってリトライ → スキップ |
| **Gemini capacity failure** | 出力ファイルに `429` / `RESOURCE_EXHAUSTED`、または exit 0 + 空出力 | 30秒待ってリトライ → スキップ |
| **JSON パース失敗** | jq / python3 でパース不能 | 1回リトライ → 統合ログに記録してスキップ |
| **部分レビュー** | multi-AI レビュー中の一部のみ完了 | 完了分で統合判断を続行。欠落を記録 |

フォールバック発生時は `.ai-logs/` の統合ログに障害種別・AI・リトライ回数を記録する。
