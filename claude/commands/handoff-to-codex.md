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

0. データ送信境界を確認する
   - 渡してよい: 対象リポジトリのソース、PR diff、関連 Issue、レビューコメント、テストログ、リポジトリ内 artifact
   - 追加確認が必要: secrets / 認証情報 / `.env*` / repo 外 private file / 本番・個人データ raw dump
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

## Approved Input / Data Boundary
- May use: repository files, PR diff, related Issue / PR comments, review comments, test logs, repo-local design artifacts
- Do not include or request: secrets, tokens, credentials, `.env*`, repo-external private files, raw production/personal data
- Repo-external artifact approved for this task: <none | explicit path and reason>

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
- Do not revert edits made by other agents; this is a multi-AI workspace

## Required Validation
- <test command 1>
- <test command 2>

## Output Format
Return the following fields:
- Summary of changes
- File list
- Test results
- Remaining risks / open questions
- Verification evidence JSON:

```json
{
  "source": "codex-worker",
  "validated_commands": ["<commands actually run>"],
  "results": {"passed": [], "failed": []},
  "residual_risks": [],
  "findings": []
}
```
```

## 注意
- 曖昧語（適切に、いい感じに）は禁止
- 受け入れ条件が書けないタスクは分割して再定義する
