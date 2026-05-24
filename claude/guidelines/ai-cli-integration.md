# AI CLI 連携（Gemini / Codex の呼び出し）

## 原則

- **Current orchestrator** は固定 AI 名ではなく、task / local policy / 可用性 / 能力で選ぶ role として扱う
- **Codex** は現状の orchestrator candidate / worker / verifier として使う
- **Claude** は foreground specialist / orchestrator candidate / integrator として使う
- **Gemini** は policy-controlled scout / critic / optional worker として使う
- すべて **ヘッドレス実行** を基本とする
- 書き込みタスクは isolated branch / worktree 前提

共通 role / context resume schema / Traceary memory 昇格ルールは
`conventions/ai/multi-ai-agent-operations.md` を source of truth とする。
Claude / Gemini / Codex の headless 調査は `~/.local/bin/multi-ai-research.sh`
（未 install 時は `scripts/multi-ai-research.sh`）を優先し、同一の workspace context packet を各 engine に渡して情報の偏りを避ける。

## 外部AIへのデータ送信境界

`multi-ai-review` / `context-resume` / `Claude Code` / `Gemini` / `Codex` / `ai-review` が明示され、かつ `~/.codex/config.toml` の `[auto_review].policy` を満たす場合、対象リポジトリの PR diff・関連 Issue・レビューコメント・該当ソース・テストログ・リポジトリ内の設計 artifact は configured external AI CLI（`claude` / `codex` / `gemini` / `ai-review`）へ渡してよい。これは multi-AI 協業の標準運用であり、同じ確認を毎回求めない。policy gate を満たさない場合は外部AI CLIを起動しない。

追加確認が必要なもの:

- secrets / token / API key / 認証情報 / `.env*`
- リポジトリ外の private file（例: `~/Downloads`, `~/Desktop`, 個人メモ）
- ユーザー個人情報・顧客データ・本番データの raw dump
- 外部サービスへの書き込み（メール送信、Slack 投稿、本番操作など）

agent 間で context を共有する場合は、Traceary / git / PR / Issue から resume packet に蒸留し、上記の境界を明記する。secrets を貼り付けない。repo 外 artifact を渡す必要がある場合は、その path と目的を明示して人間確認を取る。

## キャッシュ・作業ディレクトリの env 強制

Codex / Gemini / Claude サブエージェントを起動する前に、ビルドキャッシュ系 env を `$HOME` 配下に固定して export する。AI ツールが `$PWD/.cache` `$PWD/.gocache` `$PWD/.gopath` 等を勝手に作って ENOSPC を引き起こす事象を防ぐため。

```bash
export GOCACHE="$HOME/Library/Caches/go-build"
export GOMODCACHE="$HOME/go/pkg/mod"
export GOLANGCI_LINT_CACHE="$HOME/.cache/golangci-lint"
export PUB_CACHE="$HOME/.pub-cache"
```

- プロジェクトルートに `.cache/` `.gocache/` `.gopath/` `.golangci-cache/` `.gotmp/` 等を作らせない
- 既に作成されたらサイズ確認後に削除する（`du -sh .cache .gocache .gopath 2>/dev/null`）
- `.gitignore` で弾いていても物理削除しない限りディスクは消費する

## ヘッドレス実行コマンド

| ツール | 目的 | コマンド例 | 補足 |
|--------|------|-----------|------|
| Codex | review / plan / worker | `codex exec --full-auto - < <prompt> \| tee <file>` | `-c 'agents.default.config_file=...'` で役割付与 |
| Gemini | scout / review / planning / optional scoped worker | `gemini --approval-mode ${MULTI_AI_GEMINI_APPROVAL_MODE:-plan} -p ' ' -e none < <prompt> 2>&1 \| tee <output>` | `GEMINI_SYSTEM_MD=...` で役割付与。write 可否は local policy 優先 |
| Claude Code | design / implementation delegation | `claude -p < /tmp/claude-worker.md \| tee <output>` | `claude --print` も同じ headless 用途で使う |

> `gemini -e none` は公式にサポートされた「拡張を無効化する」指定。旧来の `-e ''` は使わない。

## 運用ルール

### Gemini
- 共有 dotfiles の既定は `--approval-mode plan`（安全側）
- repo-wide scan、既存パターン比較、docs / config / l10n drift 検出に使う
- 書き込み可否・無効化・approval mode は local policy を優先する
- 書き込みをさせる場合は、明示的に許可した isolated branch / worktree に限定する
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
- subagents / Task は sidecar 調査や UX/仕様判断の補助に使う
- Codex が current orchestrator の場合でも、ユーザー影響が大きい判断では Claude specialist として使う。Claude の orchestration 能力が高い局面では Claude が orchestrator role を担ってよい

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

## Context resume の標準パターン

### Traceary / git / PR → current orchestrator

- 手書き handoff を待たず、Traceary handoff / recent context / git status / PR / Issue から復元する
- resume packet には Objective / Current State / Scope / Forbidden Actions / Required Validation / Output Format を含める
- verifier の返却は `validated_commands` 付きの検証証跡を必須にする

### Claude → Claude Code

- UX を伴う UI 実装、設計意図の保持、大きめの統合実装は Claude Code に渡してよい
- headless (`claude -p` / `claude --print`) を優先し、ブラウザ認証プロンプトや secrets 要求が出たら停止する
- repo 外 artifact（デザイン zip 等）は、ユーザーがその path の送信を明示承認した場合だけ渡す

### Gemini → current orchestrator / Claude

- Gemini は local policy に従い、scout / critic / optional worker として使う
- 実装・検証が必要な場合は `context_resume_request`、UX / 統合判断が必要な場合は `handoff_to_claude` 相当の decision request を返す
- 実行は current orchestrator が行う。現状は Codex が多いが固定しない

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

ただし write 可否は local policy と worktree gate を必ず通す。

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
