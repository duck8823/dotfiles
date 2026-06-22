---
name: plan
description: マイルストーンのIssueを2AI並列で分析しスプリントを構成する
---

# スプリント計画（2AI並列 + Claude統合）

## トリガー
ユーザーが `/plan` を実行、またはスプリント計画を依頼したとき

## 手順

### 1. Issue 収集
```bash
gh issue list --milestone <current> --state open --json number,title,body,labels
```

### 2. 2AI 並列実行

#### Codex planner（CLI）
依存分析・Wave構成・フィジビリティ・リスク・担当判定を一括で分析。

```bash
ISSUES_JSON=$(gh issue list --milestone <current> --state open --json number,title,body,labels)
MILESTONE_JSON=$(gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.title=="<current>") | {title, description, due_on}')

cat > /tmp/codex-planner.md <<PROMPT
以下の Issue 一覧のスプリント計画を技術分析してください。
コードベースを実際に読んで、依存関係・影響範囲・Wave構成・リスク・担当判定を行ってください。
Structure-Behavior risk（概念モデル・責務分離・境界/IF・振る舞いテストの Design Note が必要か）も分類してください。

## Issue 一覧
${ISSUES_JSON}

## マイルストーン
${MILESTONE_JSON}
PROMPT

codex exec --full-auto \
  -c 'agents.default.config_file="$HOME/.codex/agents/planner.toml"' \
  -o /tmp/codex-planner-result.json \
  - < /tmp/codex-planner.md 2>/tmp/codex-planner.err
```

#### Antigravity planner（CLI）
優先度・スコープ妥当性・抜け漏れを評価。

```bash
ISSUES_JSON=$(gh issue list --milestone <current> --state open --json number,title,body,labels)
MILESTONE_JSON=$(gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.title=="<current>") | {title, description, due_on}')

cat > /tmp/antigravity-planner.md <<PROMPT
以下の Issue 一覧のスプリント計画を評価してください。

## Issue 一覧
${ISSUES_JSON}

## マイルストーン
${MILESTONE_JSON}
PROMPT

  RUNNER=$(command -v multi-ai-research.sh || printf '%s/.local/bin/multi-ai-research.sh' "$HOME")
  TERM=xterm-256color \
  "$RUNNER" --prompt-file /tmp/antigravity-planner.md --mode packet --packet /tmp/antigravity-planner.md --engines antigravity \
    --out-dir /tmp/antigravity-planner-bundle \
    > /tmp/antigravity-planner-result.json 2>&1
```

### 3. 結果統合（Claude Opus メイン）

2つの結果ファイルを読み込み統合:
- Codex planner: Wave構成・ファイル影響範囲・フィジビリティ・リスク・工数見積（技術的根拠）
- Antigravity planner: 優先度・マイルストーン整合・漏れ検出（戦略的根拠）

統合ルール:
- Wave 構成は Codex の依存分析ベース
- 各 Issue の順序は Codex のリスク + Antigravity の優先度を加味
- Antigravity の「漏れ検出」で新 Issue 作成を提案
- Codex の「過剰リスク」警告があれば Issue 分割を提案
- Medium / High の Structure-Behavior risk は、実装前に `structure-behavior-design` の Design Note を必須にする

### 4. ユーザーに提示

| Wave | Issue | タイトル | 種別 | サイズ | リスク | S/B risk | 担当 | 並列可 |
|------|-------|---------|------|--------|--------|----------|------|--------|

### 5. ユーザー承認後
- プロジェクトメモリにスプリント状態を保存
- `/sprint` で自律実行開始可能と案内
