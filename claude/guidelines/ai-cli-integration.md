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
| Codex | review / plan / worker | `codex exec --full-auto -o <file> - < <prompt>` | `-c 'agents.default.config_file=...'` で役割付与 |
| Gemini | scout / review / planning | `gemini --approval-mode plan -p ' ' -e none < <prompt> > <output>` | `GEMINI_SYSTEM_MD=...` で役割付与 |

> `gemini -e none` は公式にサポートされた「拡張を無効化する」指定。旧来の `-e ''` は使わない。

## 運用ルール

### Gemini
- 既定は `--approval-mode plan`（read-only）
- repo-wide scan、既存パターン比較、docs / config / l10n drift 検出に使う
- 書き込みをさせるのは、明示的に許可した isolated worktree 実験時のみ

### Codex
- scoped 実装、テスト、CI/CD、セキュリティ、シェル自動化に使う
- 実装タスクでは dedicated branch / worktree を使う
- 返却させる内容は **変更ファイル / 実行コマンド / 残リスク**

### Claude
- subagents / Task は sidecar 調査に使う
- マージ判断とユーザー影響の最終責任はメインセッションが持つ

## エージェント指定付き実行

### Codex（TOML エージェント定義を使用）
```bash
CODEX_AGENT=$HOME/.codex/agents/<agent-name>.toml
codex exec --full-auto \
  -c "agents.default.config_file=\"$CODEX_AGENT\"" \
  -o /tmp/<agent>-result.json \
  - < /tmp/<agent>-prompt.md 2>/tmp/<agent>.err
```

### Gemini（MD エージェント定義をシステムプロンプトとして使用）
```bash
GEMINI_SYSTEM_MD=$HOME/.gemini/agents/<agent-name>.md \
  TERM=xterm-256color \
  gemini --approval-mode plan -p ' ' -e none \
  < /tmp/<agent>-prompt.md > /tmp/<agent>-result.json 2>&1
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
  -o /tmp/codex-result.json \
  - < /tmp/codex-prompt.md 2>/tmp/codex.err
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
  -o /tmp/codex-architect-result.json \
  - < /tmp/codex-architect.md 2>/tmp/codex-architect.err && echo DONE"
$CMUX send-key --surface surface:1 Return

$CMUX send --surface "$SURFACE_RIGHT" "GEMINI_SYSTEM_MD=$HOME/.gemini/agents/reviewer.md \
  TERM=xterm-256color \
  gemini --approval-mode plan -p ' ' -e none \
  < /tmp/gemini-architect.md > /tmp/gemini-architect-result.json 2>&1 && echo DONE"
$CMUX send-key --surface "$SURFACE_RIGHT" Return
```

### 第二選択: Bash バックグラウンド実行

```bash
CODEX_AGENT=$HOME/.codex/agents/architect.toml
codex exec --full-auto \
  -c "agents.default.config_file=\"$CODEX_AGENT\"" \
  -o /tmp/codex-architect-result.json \
  - < /tmp/codex-architect.md 2>/tmp/codex-architect.err &
PID_CODEX=$!

GEMINI_SYSTEM_MD=$HOME/.gemini/agents/reviewer.md \
  TERM=xterm-256color \
  gemini --approval-mode plan -p ' ' -e none \
  < /tmp/gemini-architect.md > /tmp/gemini-architect-result.json 2>&1 &
PID_GEMINI=$!

wait $PID_CODEX $PID_GEMINI
```

### 第三選択: tmux（レガシー）

- `TERM=xterm-256color` を必ず設定する
- プロンプトは必ずファイルに書き出してから stdin で渡す
- 対話モード（`codex` / `gemini`）は使わない

## エラーハンドリング

- stderr と stdout は分離保存する（Gemini は単一ファイルでも可だが、Codex は必ず stderr を別保存）
- 失敗時は1回だけリトライ、2回目失敗でスキップして失敗を記録
- Codex を非リポジトリで使う場合は `--skip-git-repo-check` を付ける
- タイムアウト・JSON不正・空出力は統合ログに残す

## フォールバックマトリクス

| 障害種別 | 検出方法 | 対応 |
|---|---|---|
| **Codex タイムアウト** | 結果ファイル未出現（10分超過） | 1回リトライ → Claude が直接実行 |
| **Gemini タイムアウト** | 同上 | 1回リトライ → Codex scout で代替 |
| **Codex capacity failure** | stderr に `rate_limit` / `capacity` | 30秒待ってリトライ → スキップ |
| **Gemini capacity failure** | stderr に `429` / `RESOURCE_EXHAUSTED` | 30秒待ってリトライ → スキップ |
| **JSON パース失敗** | jq / python3 でパース不能 | 1回リトライ → 統合ログに記録してスキップ |
| **部分レビュー** | multi-AI レビュー中の一部のみ完了 | 完了分で統合判断を続行。欠落を記録 |

フォールバック発生時は `.ai-logs/` の統合ログに障害種別・AI・リトライ回数を記録する。
