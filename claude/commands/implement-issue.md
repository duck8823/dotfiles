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
2. **Antigravity**: 既存パターン、命名一貫性、diff 外で修正が必要なファイル、docs / config / l10n 更新要否を洗う
3. **Codex**: テスト戦略、エッジケース、セキュリティ観点、実装分割を洗う

Antigravity は local policy に従う scout / critic / optional worker、Codex は現状の orchestrator candidate / scoped worker / verifier として使う。Orchestrator は固定 AI 名ではなく、task / local policy / 可用性 / 能力で選ぶ role として扱う。

Medium / High risk（新しい振る舞い・IF・複数ファイル変更、public API、DB、auth/authz、billing、migration、cross-module architecture）の場合は、ここで `structure-behavior-design` skill を適用し、要求・概念モデル・責務表・境界/IF・振る舞いテスト・TDD plan を `.ai/spec/<issue>.md` または PR description に残す。

## ステップ3: 実装担当の決定

### Claude が主担当になる条件
- UI を含む
- 仕様が曖昧でユーザー体験判断が必要
- 複数レイヤーを跨ぐ大きな変更
- 途中で設計を変える可能性が高い

### Codex を current orchestrator / worker として進める条件
- スコープが明確
- テスト追加・CI/CD・シェル・設定変更が中心
- セキュリティ修正やバリデーション追加
- 既存パターンに沿った backend / infrastructure 変更

### Antigravity
- 共有デフォルトでは scout / critic として設計とレビューに集中させる
- local policy が明示的に許可した場合だけ scoped branch / worktree で write 可能
- local policy で無効なら起動せず skip 理由を記録する

## ステップ4: ブランチ作成

```bash
git checkout main
git pull origin main
git checkout -b feature/<short-description>  # or fix/ or maintenance/（CLAUDE.md のブランチ命名規則に従う）
```

Codex / Antigravity / Claude のいずれに write させる場合も、isolated branch / worktree を前提にする。

## ステップ5: 実装

### Claude 実装
1. 関連ファイルを Glob/Grep で探索して既存パターンを把握
2. Medium / High risk では Design Note の概念・責務・境界を先に確認する
3. まず期待する振る舞いを定義するテストを書く
4. テストを通すための最小限のコードを実装
5. 全レイヤーにわたって実装（model, repository, service, UI, l10n, tests など）
6. 既存のコード規約・命名規約に厳密に従う

### Codex 実装
- Traceary / git / PR / Issue から `context-resume` 形式で objective / scope / validation / forbidden actions を復元する
- 完了条件に `test_command`, `analyze_command`, 残リスク報告を含める
- Medium / High risk では Structure-Behavior Design Note と `structure-reviewer` 観点を依頼文に含める
- Codex の返答には **変更ファイル / 実行コマンド / 残リスク** を必ず含めさせる
- 現在の orchestrator が差分を読んで統合し、必要なら追修正する

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
- diff 外の更新漏れがないか Antigravity scout 結果で再確認する
- Codex / 外部 agent 実装時も orchestrator がローカルで最終検証を再実行する

## ステップ7: コミット分割 & ドラフトPR作成

実装を論理的なコミットに分割する（1つの関心事につき1コミット）。チケット番号は PR body で紐付け、コミットメッセージには入れない:

```bash
git add <変更したファイルを個別に指定>
git commit -m "<type>: <何を・なぜ変えたか>"
git push -u origin HEAD
PR_BODY=$(mktemp)
cat >"$PR_BODY" <<'EOF'
## 概要
Closes #$ARGUMENTS

## 変更内容
-

## テスト確認
- [ ] ユニットテスト通過
- [ ] 静的解析エラーなし
- [ ] 動作確認済み
EOF
gh pr create --draft --title "<タイトル>" --body-file "$PR_BODY"
rm -f "$PR_BODY"
```

## ステップ8: レビューへ進む

PR 作成後、続けて `/review-and-merge` を実行する。

## 注意事項

- AIアカウントをGitHubコラボレーターやレビュアーとして追加しない
- `gh pr review` がブロックされた場合は `gh pr comment` を使う
- 機密ファイル（.env など）をコミットしない
- 実装担当と同じ engine の自己レビューだけで完結しない
