---
name: multi-ai-review
description: Architect/Reviewerロールを3AI×2ロール=6並列で実行し結果を統合する
---

# Multi-AI 多重レビュー（6並列）

## トリガー
ドラフト PR 作成後に自動呼び出し。または手動で `/multi-ai-review`

## 手順

### 1. 差分準備
```bash
git diff origin/main...HEAD > /tmp/diff.txt
```

### 2. Claude サブエージェント（2体並列起動）
- `~/.claude/agents/architect.md` をサブエージェントとして起動（diff を渡す）
- `~/.claude/agents/reviewer.md` をサブエージェントとして起動（diff を渡す）

### 3. Codex + Gemini（4体並列、cmux）

cmux で4ペインを作成し、Codex 2体 + Gemini 2体を並列実行する。
（cmux が利用できない場合は Bash バックグラウンド実行でフォールバック。詳細は `~/.claude/guidelines/ai-cli-integration.md`）

#### プロンプトファイル準備
```bash
cat <<'PROMPT' > /tmp/codex-architect.md
以下の差分をアーキテクチャ観点でレビューしてください。
プロジェクトの CLAUDE.md のアーキテクチャ方針に従ってください。

$(cat /tmp/diff.txt)
PROMPT

cat <<'PROMPT' > /tmp/codex-reviewer.md
以下の差分をセキュリティ・エッジケース観点でレビューしてください。

$(cat /tmp/diff.txt)
PROMPT

cat <<'PROMPT' > /tmp/gemini-architect.md
以下の差分をアーキテクチャ観点でレビューしてください。
プロジェクト全体のソースも参照して俯瞰的に判断してください。

$(cat /tmp/diff.txt)
PROMPT

cat <<'PROMPT' > /tmp/gemini-reviewer.md
以下の差分を既存パターン・一貫性観点でレビューしてください。
プロジェクト全体のソースも参照して判断してください。

$(cat /tmp/diff.txt)
PROMPT
```

#### cmux 並列実行
```bash
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux

# 結果ファイルをクリア
rm -f /tmp/{codex,gemini}-{architect,reviewer}-result.json

# ワークスペース作成 + 4ペイン分割
$CMUX new-workspace --cwd "$(pwd)"
$CMUX new-split right
$CMUX new-split down --surface surface:1
$CMUX new-split down --surface surface:2

# Codex Architect (surface:1)
$CMUX send --surface surface:1 "codex exec --full-auto -c 'agents.default.config_file=\"\$HOME/.codex/agents/architect.toml\"' -o /tmp/codex-architect-result.json - < /tmp/codex-architect.md 2>/tmp/codex-architect.err"
$CMUX send-key --surface surface:1 Return

# Codex Reviewer (surface:3)
$CMUX send --surface surface:3 "codex exec --full-auto -c 'agents.default.config_file=\"\$HOME/.codex/agents/reviewer.toml\"' -o /tmp/codex-reviewer-result.json - < /tmp/codex-reviewer.md 2>/tmp/codex-reviewer.err"
$CMUX send-key --surface surface:3 Return

# Gemini Architect (surface:2)
$CMUX send --surface surface:2 "GEMINI_SYSTEM_MD=\$HOME/.gemini/agents/architect.md TERM=xterm-256color gemini -p ' ' -e '' < /tmp/gemini-architect.md > /tmp/gemini-architect-result.json 2>&1"
$CMUX send-key --surface surface:2 Return

# Gemini Reviewer (surface:4)
$CMUX send --surface surface:4 "GEMINI_SYSTEM_MD=\$HOME/.gemini/agents/reviewer.md TERM=xterm-256color gemini -p ' ' -e '' < /tmp/gemini-reviewer.md > /tmp/gemini-reviewer-result.json 2>&1"
$CMUX send-key --surface surface:4 Return
```

#### 完了待ち
結果ファイル4つの出現を監視する。タイムアウト10分。
```bash
TIMEOUT=600; ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  [ -f /tmp/codex-architect-result.json ] && [ -f /tmp/codex-reviewer-result.json ] && \
  [ -f /tmp/gemini-architect-result.json ] && [ -f /tmp/gemini-reviewer-result.json ] && break
  sleep 10; ELAPSED=$((ELAPSED + 10))
done
```

### 5. 結果統合（Claude Opus メイン）

6つの結果を読み込み:
1. 重複排除（同じファイル:行の指摘を統合）
2. 信頼度判定（3AI中2AI以上が指摘 → 高信頼）
3. 1AIのみの指摘 → ソースコード実読で誤検出フィルタ
4. CRITICAL は無条件採用
5. 統合結果を `gh pr comment` で投稿

### 6. 投稿フォーマット
```markdown
## Multi-AI Review Results

### CRITICAL
| 指摘 | ファイル:行 | 検出AI | 修正案 |

### HIGH
| 指摘 | ファイル:行 | 検出AI | 修正案 |

### 統計
| AI | Architect | Reviewer |
| Claude | N件 | N件 |
| Codex | N件 | N件 |
| Gemini | N件 | N件 |
```

### 7. 修正ループ
- CRITICAL → 即修正 → 修正箇所のみ Claude reviewer で再レビュー（6並列は不要）
- 全 CRITICAL 解消 → マージ判断へ

### エラーハンドリング
- Codex/Gemini が失敗 → 1回リトライ → 2回目失敗 → スキップして記録
- 失敗した AI の結果なしで統合を続行（残りの AI 結果で判断）
