---
name: spec-driven
description: Issueから2AI並列で仕様書を生成し、仕様ベースで実装を進める
---

# 仕様駆動開発（2AI並列 + Claude統合）

## トリガー
`/sprint` 内の各 Issue 実装前に自動呼び出し。または手動で `/spec-driven <issue番号>`

## 手順

### 1. Issue 確認
```bash
gh issue view <番号> --json number,title,body,labels
```

### 2. 2AI 並列仕様生成

#### Codex spec-writer（CLI）
テスト戦略・セキュリティ・検証計画 + ファイルスコープ・実装手順を生成。

```bash
ISSUE_JSON=$(gh issue view <番号> --json number,title,body)

cat > /tmp/codex-spec.md <<PROMPT
以下の Issue の実装仕様を生成してください。
コードベースを実際に読んで、変更対象ファイル・実装手順・テスト戦略・セキュリティ考慮を含めてください。

## Issue
${ISSUE_JSON}
PROMPT

codex exec --full-auto \
  -c 'agents.default.config_file="$HOME/.codex/agents/spec-writer.toml"' \
  -o /tmp/codex-spec-result.json \
  - < /tmp/codex-spec.md 2>/tmp/codex-spec.err
```

#### Gemini reviewer（CLI）— 既存パターン・影響範囲のスカウト
```bash
ISSUE_JSON=$(gh issue view <番号> --json number,title,body)

cat > /tmp/gemini-spec-scout.md <<PROMPT
以下の Issue の実装に先立ち、既存パターン・影響範囲を調査してください。
参考にすべき既存実装、命名規約、diff 外で影響を受けるファイル、ドキュメント更新の要否を報告してください。

## Issue
${ISSUE_JSON}
PROMPT

GEMINI_SYSTEM_MD=$HOME/.gemini/agents/reviewer.md \
  TERM=xterm-256color \
  gemini --approval-mode plan -p ' ' -e none < /tmp/gemini-spec-scout.md > /tmp/gemini-spec-scout-result.json 2>&1
```

### 3. 統合して .ai/spec 生成（Claude メインセッション）

2つの結果を統合し `.ai/spec/<issue番号>.md` を生成:

```markdown
# Issue #<番号>: <タイトル>

## スコープ
（Codex: ファイル一覧）

## スコープ外
（Codex: 触らないファイル）

## 実装手順
（Codex: ファイル単位の変更内容）

## 実装パターン
（Gemini: 既存パターンの参照。「lib/xxx.dart の YYY と同じパターンで」）

## 完了条件
（Codex: テストパス + テストケース）

## テストケース
（Codex: 正常系・異常系・境界値・セキュリティ）

## 注意事項
（Codex: セキュリティ考慮・エッジケース）
（Gemini: ドキュメント更新・l10n 更新・diff外影響）
```

### 4. 実装開始
- .ai/spec を参照しながら実装
- 完了条件のテストが通ることを確認

### 5. クリーンアップ
- PR マージ後に .ai/spec ファイルを削除
