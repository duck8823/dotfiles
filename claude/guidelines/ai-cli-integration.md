# AI CLI 連携（Gemini / Codex の呼び出し）

## ヘッドレス実行コマンド

| ツール | コマンド | 主要オプション |
|--------|---------|---------------|
| Codex | `codex exec "prompt"` | `-o <file>`: 最終メッセージをファイル出力、`--full-auto`: 承認なし実行 |
| Gemini | `gemini -p "prompt"` | `-e ''`: 拡張機能無効化、stdin 経由でプロンプト渡し |

対話的コマンド（`codex`, `gemini`）は使わない。必ずヘッドレスモードを使うこと。

## エージェント指定付き実行

### Codex（TOML エージェント定義を使用）
```bash
codex exec --full-auto \
  -c 'agents.default.config_file="$HOME/.codex/agents/<agent-name>.toml"' \
  -o /tmp/<agent>-result.json \
  - < /tmp/<agent>-prompt.md 2>/tmp/<agent>.err
```

### Gemini（MD エージェント定義をシステムプロンプトとして使用）
```bash
GEMINI_SYSTEM_MD=$HOME/.gemini/agents/<agent-name>.md \
  TERM=xterm-256color \
  gemini -p ' ' -e '' < /tmp/<agent>-prompt.md > /tmp/<agent>-result.json 2>&1
```

## 並列実行方式

### 第一選択: cmux（推奨）

cmux を使って Codex / Gemini を複数ペインで並列実行する。
結果はファイル出力（`-o` / リダイレクト）で回収し、Claude メインセッションが統合する。

```bash
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux

# ワークスペース作成（プロジェクトディレクトリで）
$CMUX new-workspace --cwd "$(pwd)"

# 4ペインに分割（2×2: Codex architect, Codex reviewer, Gemini architect, Gemini reviewer）
SURFACE_RIGHT=$($CMUX new-split right)
SURFACE_BOTTOM_LEFT=$($CMUX new-split down --surface surface:1)
SURFACE_BOTTOM_RIGHT=$($CMUX new-split down --surface "$SURFACE_RIGHT")

# 各ペインにヘッドレスコマンドを送信
$CMUX send --surface surface:1 'codex exec --full-auto \
  -c '\''agents.default.config_file="$HOME/.codex/agents/architect.toml"'\'' \
  -o /tmp/codex-architect-result.json \
  - < /tmp/codex-architect.md 2>/tmp/codex-architect.err && echo DONE'
$CMUX send-key --surface surface:1 Return

# ... 他のペインも同様

# 完了待ち: 結果ファイルの存在を監視
while [ ! -f /tmp/codex-architect-result.json ] || [ ! -f /tmp/gemini-architect-result.json ]; do
  sleep 5
done
```

### cmux 固有の便利機能

#### 結果の読み取り（ファイル出力が使えない場合のフォールバック）
```bash
$CMUX read-screen --surface surface:1 --scrollback --lines 200
```

#### 通知（タスク完了をハイライト）
```bash
$CMUX trigger-flash --surface surface:1
```

#### ブラウザペイン（E2E テスト・UI検証用）
```bash
$CMUX new-pane --type browser --url http://localhost:3000
$CMUX browser screenshot --out /tmp/screenshot.png
$CMUX browser snapshot  # DOM スナップショット取得
```

### 第二選択: Bash バックグラウンド実行

cmux が利用できない環境でのフォールバック。

```bash
# バックグラウンドで並列実行
codex exec --full-auto \
  -c 'agents.default.config_file="$HOME/.codex/agents/architect.toml"' \
  -o /tmp/codex-architect-result.json \
  - < /tmp/codex-architect.md 2>/tmp/codex-architect.err &
PID_CODEX=$!

GEMINI_SYSTEM_MD=$HOME/.gemini/agents/architect.md \
  TERM=xterm-256color \
  gemini -p ' ' -e '' < /tmp/gemini-architect.md > /tmp/gemini-architect-result.json 2>&1 &
PID_GEMINI=$!

# 完了待ち
wait $PID_CODEX $PID_GEMINI
```

### 第三選択: tmux（レガシー）

- Gemini を tmux で使う場合は `TERM=xterm-256color` 必須（`TERM=screen` でクラッシュする既知問題）
- プロンプトは必ずファイルに書き出してから stdin 経由で渡す（ARG_MAX 回避）

## エラーハンドリング

- stderr と stdout は分離保存する（`2>/tmp/tool.err`）
- 失敗時は1回だけリトライ、2回目失敗でスキップして失敗を記録
- Codex を非リポジトリで使う場合は `--skip-git-repo-check` を付ける
