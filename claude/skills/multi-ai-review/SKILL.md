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

### 3. Codex（2体並列、tmux）

#### Architect
```bash
cat <<'PROMPT' > /tmp/codex-architect.md
以下の差分をアーキテクチャ観点でレビューしてください。
AGENTS.md のアーキテクチャ方針に従ってください。

$(cat /tmp/diff.txt)
PROMPT

codex exec --full-auto \
  -c 'agents.default.config_file="/Users/duck8823/.codex/agents/architect.toml"' \
  -o /tmp/codex-architect-result.json \
  - < /tmp/codex-architect.md 2>/tmp/codex-architect.err
```

#### Reviewer
```bash
cat <<'PROMPT' > /tmp/codex-reviewer.md
以下の差分をセキュリティ・エッジケース観点でレビューしてください。

$(cat /tmp/diff.txt)
PROMPT

codex exec --full-auto \
  -c 'agents.default.config_file="/Users/duck8823/.codex/agents/reviewer.toml"' \
  -o /tmp/codex-reviewer-result.json \
  - < /tmp/codex-reviewer.md 2>/tmp/codex-reviewer.err
```

### 4. Gemini（2体並列、tmux）

#### Architect
```bash
cat <<'PROMPT' > /tmp/gemini-architect.md
以下の差分をアーキテクチャ観点でレビューしてください。
プロジェクト全体のソースも参照して俯瞰的に判断してください。

$(cat /tmp/diff.txt)
PROMPT

GEMINI_SYSTEM_MD=/Users/duck8823/.gemini/agents/architect.md \
  TERM=xterm-256color \
  gemini -p ' ' -e '' < /tmp/gemini-architect.md > /tmp/gemini-architect-result.json 2>&1
```

#### Reviewer
```bash
cat <<'PROMPT' > /tmp/gemini-reviewer.md
以下の差分を既存パターン・一貫性観点でレビューしてください。
プロジェクト全体のソースも参照して判断してください。

$(cat /tmp/diff.txt)
PROMPT

GEMINI_SYSTEM_MD=/Users/duck8823/.gemini/agents/reviewer.md \
  TERM=xterm-256color \
  gemini -p ' ' -e '' < /tmp/gemini-reviewer.md > /tmp/gemini-reviewer-result.json 2>&1
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
