---
description: GitHubイシューを実装してPRを作成する
argument-hint: <issue-number>
allowed-tools: ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "Task"]
---

# イシュー実装ワークフロー

対象イシュー番号: **#$ARGUMENTS**

## ステップ1: イシュー確認

まず `gh issue view $ARGUMENTS` でイシューを確認し、タイトル・説明・ラベルを把握する。
番号に曖昧さがある場合（例: 似た番号のイシューが複数存在する）はユーザーに確認してから進める。
**イシュー番号をタイトルと照合してダブルチェックすること。**

## ステップ2: ブランチ作成

```bash
git checkout main
git pull origin main
git checkout -b feature/issue-$ARGUMENTS-<short-description>
```

## ステップ3: テスト駆動で実装

1. 関連ファイルを Glob/Grep で探索して既存パターンを把握する
2. まず期待する振る舞いを定義するテストを書く
3. テストを通すための最小限のコードを実装する
4. 全レイヤーにわたって実装する（model, repository, service, UI, l10n, tests など）
5. 既存のコード規約・命名規約に厳密に従う

## ステップ4: 品質チェック

プロジェクトの `CLAUDE.md` に `## AI レビュー設定` セクションがあればそこから読み取り、なければプロジェクト構造から判断する。

```bash
# CLAUDE.md から test_command / analyze_command を読み取る
TEST_CMD=$(grep 'test_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/' | tr -d '\n')
ANALYZE_CMD=$(grep 'analyze_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/' | tr -d '\n')

# コマンドが取得できた場合は実行、できない場合はプロジェクト構造から判断
${TEST_CMD:+$TEST_CMD}
${ANALYZE_CMD:+$ANALYZE_CMD}
```

- テストがすべて通るまで修正を繰り返す
- アナライザーの警告をすべて修正する

## ステップ5: コミット分割 & ドラフトPR作成

実装を論理的なコミットに分割する（1つの関心事につき1コミット）:
```bash
git add <変更したファイルを個別に指定>
git commit -m "$(cat <<'EOF'
<type>: <説明> (closes #$ARGUMENTS)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git push -u origin HEAD
gh pr create --draft \
  --title "<タイトル>" \
  --body "$(cat <<'EOF'
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

## 注意事項

- AIアカウントをGitHubコラボレーターやレビュアーとして追加しない
- `gh pr review` がブロックされた場合は `gh pr comment` を使う
- 機密ファイル（.env など）をコミットしない
- PR作成後、続けて `/review-and-merge` を実行することを推奨
