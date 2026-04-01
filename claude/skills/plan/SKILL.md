---
name: plan
description: マイルストーンのIssueを3AI多重で分析しスプリントを構成する
---

# スプリント計画（3AI多重）

## トリガー
ユーザーが `/plan` を実行、またはスプリント計画を依頼したとき

## 手順

### 1. Issue 収集
```bash
gh issue list --milestone <current> --state open --json number,title,body,labels
```

### 2. 3AI 並列実行

#### Claude planner（サブエージェント）
`~/.claude/agents/planner.md` をサブエージェントとして起動。
Issue 一覧を渡し、コードベースを探索してファイル影響範囲・依存関係・Wave構成を分析させる。

#### Codex planner（CLI）
```bash
ISSUES_JSON=$(gh issue list --milestone <current> --state open --json number,title,body,labels)
MILESTONE_JSON=$(gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.title=="<current>") | {title, description, due_on}')

cat > /tmp/codex-planner.md <<PROMPT
以下の Issue 一覧のスプリント計画を評価してください。

## Issue 一覧
${ISSUES_JSON}

## マイルストーン
${MILESTONE_JSON}
PROMPT

codex exec --full-auto   -c 'agents.default.config_file="$HOME/.codex/agents/planner.toml"'   -o /tmp/codex-planner-result.json   - < /tmp/codex-planner.md 2>/tmp/codex-planner.err
```

#### Gemini planner（CLI）
```bash
ISSUES_JSON=$(gh issue list --milestone <current> --state open --json number,title,body,labels)
MILESTONE_JSON=$(gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.title=="<current>") | {title, description, due_on}')

cat > /tmp/gemini-planner.md <<PROMPT
以下の Issue 一覧のスプリント計画を評価してください。

## Issue 一覧
${ISSUES_JSON}

## マイルストーン
${MILESTONE_JSON}
PROMPT

GEMINI_SYSTEM_MD=$HOME/.gemini/agents/planner.md   TERM=xterm-256color   gemini --approval-mode plan -p ' ' -e none < /tmp/gemini-planner.md > /tmp/gemini-planner-result.json 2>&1
```

### 3. 結果統合（Claude Opus メイン）

3つの結果ファイルを読み込み統合:
- Claude planner: Wave構成・ファイル影響範囲（技術的依存の根拠）
- Codex planner: フィジビリティ・リスク・工数見積（実現可能性の根拠）
- Gemini planner: 優先度・マイルストーン整合・漏れ検出（戦略的根拠）

統合ルール:
- Wave 構成は Claude の依存分析ベース
- 各 Issue の順序は Codex のリスク + Gemini の優先度を加味
- Gemini の「漏れ検出」で新 Issue 作成を提案
- Codex の「過剰リスク」警告があれば Issue 分割を提案

### 4. ユーザーに提示

| Wave | Issue | タイトル | 種別 | サイズ | リスク | 並列可 |
|------|-------|---------|------|--------|--------|--------|

### 5. ユーザー承認後
- プロジェクトメモリにスプリント状態を保存
- `/sprint` で自律実行開始可能と案内
