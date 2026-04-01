---
description: GitHubイシューを実装してPRを作成する
argument-hint: <issue-number>
allowed-tools: ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "Task"]
---

# イシュー実装ワークフロー

対象イシュー番号: **#$ARGUMENTS**

## ステップ1: イシュー確認

まず `gh issue view $ARGUMENTS` でイシューを確認し、タイトル・説明・ラベルを把握する。
番号に曖昧さがある場合はユーザーに確認してから進める。
**イシュー番号をタイトルと照合してダブルチェックすること。**

## ステップ2: 実装前の scout pass

コードを書く前に、最低限以下を実施する。

1. **Claude**: 関連ファイルを読んで既存パターンと制約を把握する
2. **Gemini**: 既存パターン、命名一貫性、diff 外で修正が必要なファイル、docs / config / l10n 更新要否を洗う
3. **Codex**: テスト戦略、エッジケース、セキュリティ観点、実装分割を洗う

Gemini は原則 read-only、Codex は scoped worker / verifier として使う。

## ステップ3: 実装担当の決定

### Claude が主担当になる条件
- UI を含む
- 仕様が曖昧でユーザー体験判断が必要
- 複数レイヤーを跨ぐ大きな変更
- 途中で設計を変える可能性が高い

### Codex に handoff する条件
- スコープが明確
- テスト追加・CI/CD・シェル・設定変更が中心
- セキュリティ修正やバリデーション追加
- 既存パターンに沿った backend / infrastructure 変更

### Gemini
- 実装担当にはしない
- scout / critic として設計とレビューに集中させる

## ステップ4: ブランチ作成

```bash
git checkout main
git pull origin main
git checkout -b feature/issue-$ARGUMENTS-<short-description>
```

Codex に handoff する場合も、isolated branch / worktree を前提にする。

## ステップ5: 実装

### Claude 実装
1. 関連ファイルを Glob/Grep で探索して既存パターンを把握
2. まず期待する振る舞いを定義するテストを書く
3. テストを通すための最小限のコードを実装
4. 全レイヤーにわたって実装（model, repository, service, UI, l10n, tests など）
5. 既存のコード規約・命名規約に厳密に従う

### Codex 実装
- `/handoff-to-codex` のフォーマットに従って依頼文を作る
- 完了条件に `test_command`, `analyze_command`, 残リスク報告を含める
- Codex の返答には **変更ファイル / 実行コマンド / 残リスク** を必ず含めさせる
- Claude が差分を読んで統合し、必要なら追修正する

## ステップ6: 品質チェック

プロジェクトの `CLAUDE.md` に `## AI レビュー設定` セクションがあればそこから読み取り、なければプロジェクト構造から判断する。

```bash
TEST_CMD=$(grep 'test_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/' | tr -d '\n')
ANALYZE_CMD=$(grep 'analyze_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/' | tr -d '\n')

[ -n "$TEST_CMD" ] && eval "$TEST_CMD"
[ -n "$ANALYZE_CMD" ] && eval "$ANALYZE_CMD"
```

- テストがすべて通るまで修正を繰り返す
- アナライザーの警告をすべて修正する
- diff 外の更新漏れがないか Gemini scout 結果で再確認する
- Codex 実装時も Claude がローカルで最終検証を再実行する

## ステップ7: コミット分割 & ドラフトPR作成

実装を論理的なコミットに分割する（1つの関心事につき1コミット）:

```bash
git add <変更したファイルを個別に指定>
git commit -m "<type>: <説明> (closes #$ARGUMENTS)"
git push -u origin HEAD
gh pr create --draft   --title "<タイトル>"   --body "$(cat <<'EOF'
## 概要
Closes #$ARGUMENTS

## 変更内容
-

## テスト確認
- [ ] ユニットテスト通過
- [ ] 静的解析エラーなし
- [ ] 動作確認済み
EOF
)"
```

## ステップ8: レビューへ進む

PR 作成後、続けて `/review-and-merge` を実行する。

## 注意事項

- AIアカウントをGitHubコラボレーターやレビュアーとして追加しない
- `gh pr review` がブロックされた場合は `gh pr comment` を使う
- 機密ファイル（.env など）をコミットしない
- Codex が実装した PR では Codex をレビュアーから外す
