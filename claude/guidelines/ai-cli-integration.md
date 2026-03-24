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
  -c 'agents.default.config_file=".codex/agents/<agent-name>.toml"' \
  -o /tmp/<agent>-result.json \
  - < /tmp/<agent>-prompt.md 2>/tmp/<agent>.err
```

### Gemini（MD エージェント定義をシステムプロンプトとして使用）
```bash
GEMINI_SYSTEM_MD=.gemini/agents/<agent-name>.md \
  TERM=xterm-256color \
  gemini -p ' ' -e '' < /tmp/<agent>-prompt.md > /tmp/<agent>-result.json 2>&1
```

## 実行方式の使い分け

**第一選択: Bash ツールで直接実行（同期）**

```bash
# Gemini（ARG_MAX 回避のため stdin 経由）
TERM=xterm-256color gemini -p ' ' -e '' < /tmp/prompt.md > /tmp/output.md 2>&1

# Codex（stdin 経由 + --full-auto）
codex exec --full-auto -o /tmp/output.md - < /tmp/prompt.md 2>/tmp/output.err
```

**第二選択: tmux（複数タスクの並列実行）**

- Gemini を tmux で使う場合は `TERM=xterm-256color` 必須（`TERM=screen` でクラッシュする既知問題）
- プロンプトは必ずファイルに書き出してから stdin 経由で渡す（ARG_MAX 回避）

## エラーハンドリング

- stderr と stdout は分離保存する（`2>/tmp/tool.err`）
- 失敗時は1回だけリトライ、2回目失敗でスキップして失敗を記録
- Codex を非リポジトリで使う場合は `--skip-git-repo-check` を付ける
