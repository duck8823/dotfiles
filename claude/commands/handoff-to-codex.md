---
description: ClaudeからCodexへ実装/調査タスクを引き継ぐための依頼文を生成する
argument-hint: <task-summary>
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Write", "Edit"]
---

# Codex引き継ぎコマンド

対象タスク: **$ARGUMENTS**

## 目的
Claudeの制限節約と品質維持のため、Codexへ渡す依頼文を標準化する。

## 手順
1. 関連情報を収集する
   - 仕様/Issue/PR/関連ファイル
   - ブランチ名、制約、期限
2. スコープを固定する
   - 何をやるか
   - 何をやらないか（非対象）
3. 検証条件を固定する
   - 必須テストコマンド
   - 完了条件（受け入れ条件）
4. Codexへの依頼文を以下フォーマットで1本化する

## Codex依頼文テンプレート（出力）
```markdown
# Task for Codex

## Objective
- <達成したいこと>

## Acceptance Criteria
- [ ] <検証可能な条件1>
- [ ] <検証可能な条件2>

## Out of Scope
- <非対象1>
- <非対象2>

## Constraints
- Branch: <branch>
- Files/Modules: <対象範囲>
- Prohibitions: <禁止事項>

## Required Validation
- <test command 1>
- <test command 2>

## Output Format
- Summary of changes
- File list
- Test results
- Remaining risks / open questions
```

## 注意
- 曖昧語（適切に、いい感じに）は禁止
- 受け入れ条件が書けないタスクは分割して再定義する
