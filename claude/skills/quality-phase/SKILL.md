---
name: quality-phase
description: スプリント完了後のアーキテクチャレビュー・探索的テスト・デザインチェックを実行する
---

# スプリント完了後品質フェーズ

## トリガー
`/sprint` の全 Issue 完了後に自動呼び出し。または手動で `/quality-phase`

## 手順

### 1. スプリント全体の差分取得
```bash
git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD
git diff $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD > /tmp/sprint-diff.txt
```

### 2. アーキテクチャレビュー（3AI多重）

スプリント全体の diff を対象に Architect ロール 3AI 並列実行:

#### Claude architect（サブエージェント）
`~/.claude/agents/architect.md` にスプリント全体 diff を渡す

#### Codex architect（CLI）
```bash
cat <<'PROMPT' > /tmp/codex-qp-architect.md
以下はスプリント全体の差分です。アーキテクチャ観点でレビューしてください。

$(cat /tmp/sprint-diff.txt)
PROMPT

codex exec --full-auto \
  -c 'agents.default.config_file="$HOME/.codex/agents/architect.toml"' \
  -o /tmp/codex-qp-architect-result.json \
  - < /tmp/codex-qp-architect.md 2>/tmp/codex-qp-architect.err
```

#### Gemini architect（CLI）
```bash
GEMINI_SYSTEM_MD=$HOME/.gemini/agents/architect.md \
  TERM=xterm-256color \
  gemini -p ' ' -e '' < /tmp/gemini-qp-architect.md > /tmp/gemini-qp-architect-result.json 2>&1
```

### 3. デザインチェック（Claude のみ）
`~/.claude/agents/designer.md` をサブエージェントとして起動。
プロジェクトの CLAUDE.md のデザインシステムセクションを参照させる。

### 4. 探索的テスト（Claude のみ）
`~/.claude/agents/qa.md` をサブエージェントとして起動。
スプリントでクローズした Issue の受け入れ条件からテストシナリオを導出・実行。

### 5. 結果統合 & トリアージ

全結果を統合し、重大度で分類:

| 重大度 | 基準 | 対応 |
|--------|------|------|
| **CRITICAL** | バグ・セキュリティ脆弱性・データ破損・クラッシュ | 即座に修正 & PR |
| **HIGH以下** | 技術的負債・改善・一貫性・デザイン・テスト追加 | `gh issue create` で同マイルストーンに登録 |

### 6. CRITICAL 修正
CRITICAL が検出された場合:
1. 修正ブランチ作成
2. 修正実装
3. 修正箇所のみ Claude reviewer で再レビュー
4. ドラフト PR → マージ

### 7. Issue 登録
HIGH 以下の指摘を Issue 化:
```bash
gh issue create \
  --title "<指摘タイトル>" \
  --body "<指摘内容と修正案>" \
  --milestone "<current milestone>" \
  --label "tech-debt"
```

### 8. 完了報告
- アーキテクチャレビュー結果（3AI統合）
- デザインチェック結果
- 探索的テスト結果（PASS/FAIL 一覧）
- CRITICAL 修正の有無
- 新規登録した tech-debt Issue 一覧
