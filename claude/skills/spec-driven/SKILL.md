---
name: spec-driven
description: Issueから3AI多重で仕様書を生成し、仕様ベースで実装を進める
---

# 仕様駆動開発（3AI多重）

## トリガー
`/sprint` 内の各 Issue 実装前に自動呼び出し。または手動で `/spec-driven <issue番号>`

## 手順

### 1. Issue 確認
```bash
gh issue view <番号> --json number,title,body,labels
```

### 2. 3AI 並列仕様生成

#### Claude spec-writer（サブエージェント）
`~/.claude/agents/spec-writer.md` をサブエージェントとして起動。
Issue 内容を渡し、コードベースを探索してファイルスコープ・実装手順・完了条件を生成させる。

#### Codex spec-writer（CLI）
```bash
ISSUE_JSON=$(gh issue view <番号> --json number,title,body)

cat > /tmp/codex-spec.md <<PROMPT
以下の Issue の実装仕様をテスト・セキュリティ観点で評価してください。

## Issue
${ISSUE_JSON}
PROMPT

codex exec --full-auto   -c 'agents.default.config_file="$HOME/.codex/agents/spec-writer.toml"'   -o /tmp/codex-spec-result.json   - < /tmp/codex-spec.md 2>/tmp/codex-spec.err
```

#### Gemini spec-writer（CLI）
```bash
ISSUE_JSON=$(gh issue view <番号> --json number,title,body)

cat > /tmp/gemini-spec.md <<PROMPT
以下の Issue の実装仕様を既存パターン・影響範囲観点で評価してください。

## Issue
${ISSUE_JSON}
PROMPT

GEMINI_SYSTEM_MD=$HOME/.gemini/agents/spec-writer.md   TERM=xterm-256color   gemini --approval-mode plan -p ' ' -e none < /tmp/gemini-spec.md > /tmp/gemini-spec-result.json 2>&1
```

### 3. 統合して .spec 生成

3つの結果を統合し `.ai/spec/<issue番号>.md` を生成:

```markdown
# Issue #<番号>: <タイトル>

## スコープ
（Claude: ファイル一覧 + Gemini: 影響範囲外のファイルも追加）

## スコープ外
（Claude: 触らないファイル）

## 実装手順
（Claude: ファイル単位の変更内容）

## 実装パターン
（Gemini: 既存パターンの参照。「lib/xxx.dart の YYY と同じパターンで」）

## 完了条件
（Claude: テストパス + Codex: テストケース）

## テストケース
（Codex: 正常系・異常系・境界値・セキュリティ）

## 注意事項
（Codex: セキュリティ考慮・エッジケース）
（Gemini: ドキュメント更新・l10n 更新）
```

### 4. 実装開始
- .spec を参照しながら実装
- 完了条件のテストが通ることを確認

### 5. クリーンアップ
- PR マージ後に .spec ファイルを削除
