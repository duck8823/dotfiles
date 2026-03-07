---
description: 現在のPRを2-AI並列レビュー + Claude最終レビューで全員APPROVEまで修正を繰り返してマージする
argument-hint: [pr-number] (省略時は現在のブランチのPR)
allowed-tools: ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "Task"]
---

# PRレビュー & マージワークフロー

対象PR: **$ARGUMENTS** (省略時は `gh pr view` で現在のブランチのPRを使用)

## ステップ1: PR情報の取得

```bash
gh pr view $ARGUMENTS
gh pr diff $ARGUMENTS
```

PR番号・タイトル・変更ファイルを把握する。

## ステップ2: 2-AI 並列レビュー

Gemini と Codex を使って並列レビューを実施する。**忖度なしの厳格なレビュー**を行うこと。
問題がないコードでも無理に問題を作り出す必要はないが、発見した問題は重大度に関わらずすべて報告する。

Claude Code はこのステップではレビューしない（ステップ5で最終レビューを行う）。

### レビュアー構成
| # | AI | 実行方法 | 役割 |
|---|-----|---------|------|
| 1 | Gemini CLI | tmux + `gemini -p` (ヘッドレスモード) | 1st pass（設計・アーキテクチャ観点） |
| 2 | Codex CLI | tmux + `codex exec` (ヘッドレスモード) | 1st pass（セキュリティ・実装品質・テスト観点） |

### コンテキスト収集

ステップ1 で取得した PR 番号を使い、レビューに必要なコンテキストを収集する。
**diff のみのレビューは禁止。** 必ず Issue・PR説明・過去レビュー・PRコメント・CI結果を付与する。

**重要: プロンプトは必ずファイルに書き出してから渡すこと。シェル引数への直接埋め込みは ARG_MAX 超過で失敗する。**

- **Gemini**: プロンプトファイルを stdin でパイプ渡し（`gemini < /tmp/prompt.md`）
- **Codex**: リポジトリ内で動作するため diff を埋め込まず最小プロンプトにし、`git diff` を自力実行させる

```bash
PR_NUMBER=<number>
PROJECT=<project>   # プロジェクト名（tmux セッション名・ファイル名に使用）

# 変更ファイル一覧
CHANGED_FILES=$(git diff origin/main..HEAD --stat)

PR_INFO=$(gh pr view $PR_NUMBER --json number,title,body \
  --template 'PR #{{.number}}: {{.title}}{{"\n\n"}}{{.body}}')

# PRのbodyから #123 形式のIssue番号を抽出して取得
ISSUE_INFO=""
for n in $(gh pr view $PR_NUMBER --json body --jq '.body' | grep -oE '#[0-9]+' | tr -d '#'); do
  ISSUE_INFO+=$(gh issue view $n --json number,title,body \
    --template 'Issue #{{.number}}: {{.title}}{{"\n\n"}}{{.body}}' 2>/dev/null || true)
  ISSUE_INFO+=$'\n'
done

# 過去のレビューコメント（APPROVED/CHANGES_REQUESTED/COMMENTED）
PREV_REVIEWS=$(gh pr view $PR_NUMBER --json reviews \
  --jq '.reviews[] | "【" + .state + "】" + .author.login + "\n" + .body' 2>/dev/null || true)

# インラインコメント（ファイル:行番号付き）
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PREV_COMMENTS=$(gh api repos/$REPO/pulls/$PR_NUMBER/comments \
  --jq '.[] | .path + " L" + (.line|tostring) + ": " + .body' 2>/dev/null || true)

# PRコメント（会話コメント）
PR_COMMENTS=$(gh pr view $PR_NUMBER --json comments \
  --jq '.comments[] | "【" + .author.login + "】" + .createdAt + "\n" + .body' 2>/dev/null || true)

# CI チェック結果
CI_STATUS=$(gh pr checks $PR_NUMBER --json name,status,conclusion \
  --jq '.[] | .name + ": " + (.conclusion // .status)' 2>/dev/null || true)

# プロジェクト規約（## レビュー規約セクションを優先、なければ先頭80行）
PROJECT_CONTEXT=""
if [ -f CLAUDE.md ]; then
  REVIEW_SECTION=$(awk '/^## レビュー規約$/{f=1} f{print} f && /^## / && !/^## レビュー規約$/{exit}' CLAUDE.md)
  PROJECT_CONTEXT="${REVIEW_SECTION:-$(head -80 CLAUDE.md)}"
fi

# CLAUDE.md から Codex 用コマンドを読み取る
CODEX_TEST_CMD=$(grep 'test_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/')
CODEX_ANALYZE_CMD=$(grep 'analyze_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/')
```

### プロンプトファイルの生成

**Gemini 用プロンプトファイル（diff のみ — 全ソース含有は Gemini のトークン上限でエコー/失敗するため禁止）:**

```bash
GEMINI_PROMPT_FILE="/tmp/${PROJECT}-pr${PR_NUMBER}-gemini-prompt.md"
DIFF=$(git diff origin/main..HEAD --unified=10)

{
  echo "以下の情報を踏まえて、忖度なしで厳格にコードレビューを行ってください。"
  echo "良い点があれば良い、悪い点があれば遠慮なく指摘すること。"
  echo ""
  echo "## プロジェクト規約"
  echo "${PROJECT_CONTEXT:-（なし）}"
  echo ""
  echo "## 関連 Issue"
  echo "${ISSUE_INFO:-（なし）}"
  echo ""
  echo "## PR 概要"
  echo "$PR_INFO"
  echo ""
  echo "## これまでのレビューコメント"
  echo "${PREV_REVIEWS:-（なし）}"
  echo ""
  echo "## インラインコメント履歴"
  echo "${PREV_COMMENTS:-（なし）}"
  echo ""
  echo "## PRコメント（会話）"
  echo "${PR_COMMENTS:-（なし）}"
  echo ""
  echo "## CI チェック結果"
  echo "${CI_STATUS:-（なし）}"
  echo ""
  echo "## 変更ファイル一覧"
  echo "$CHANGED_FILES"
  echo ""
  echo "## 変更差分（前後10行コンテキスト付き）"
  echo '```diff'
  echo "$DIFF"
  echo '```'
  echo ""
  echo "## レビュー観点"
  echo "- Issue の要件・受け入れ条件を満たしているか"
  echo "- PR の意図と実装が一致しているか"
  echo "- 前回レビューの指摘が適切に反映されているか"
  echo "- CI の失敗・警告に対して対処されているか"
  echo "- プロジェクト規約・アーキテクチャ方針に沿っているか"
  echo "- セキュリティ: 認証・認可の抜け、データ露出リスク、入力バリデーション"
  echo "- アーキテクチャ: レイヤー分離、依存方向、既存パターンとの一貫性、SOLID原則"
  echo "- 品質: テストカバレッジ、エッジケース、バグ、パフォーマンス、フレームワーク固有のベストプラクティス"
  echo "- コード: 命名規約、重複コード、エラーハンドリング、i18n の完全性"
  echo "- diff 外の対応漏れ（テスト・ドキュメント・関連モジュール）"
  echo ""
  echo "各指摘を Critical / Major / Minor の3段階で分類し、ファイル名:行番号付きで報告してください。"
  echo "最終判定を APPROVE（問題なし）または REQUEST_CHANGES（要修正）で明示してください。"
} > "$GEMINI_PROMPT_FILE"
```

**Codex 用プロンプトファイル（最小版 — diff・テストは自力で実行させる）:**

```bash
CODEX_PROMPT_FILE="/tmp/${PROJECT}-pr${PR_NUMBER}-codex-prompt.md"

cat > "$CODEX_PROMPT_FILE" << PROMPT_EOF
以下の情報を踏まえて、まず以下のコマンドを順番に実行して変更内容と品質を確認してから、忖度なしで厳格にコードレビューを行ってください:
1. \`git diff origin/main..HEAD --unified=10\`
${CODEX_TEST_CMD:+2. \`$CODEX_TEST_CMD\`}
${CODEX_ANALYZE_CMD:+3. \`$CODEX_ANALYZE_CMD\`}


## プロジェクト規約
${PROJECT_CONTEXT:-（なし）}

## 関連 Issue
${ISSUE_INFO:-（なし）}

## PR 概要
${PR_INFO}

## これまでのレビューコメント
${PREV_REVIEWS:-（なし）}

## インラインコメント履歴
${PREV_COMMENTS:-（なし）}

## PRコメント（会話）
${PR_COMMENTS:-（なし）}

## CI チェック結果
${CI_STATUS:-（なし）}

## 変更ファイル一覧
${CHANGED_FILES}

## レビュー観点
- Issue の要件・受け入れ条件を満たしているか
- PR の意図と実装が一致しているか
- 前回レビューの指摘が適切に反映されているか
- CI の失敗・警告に対して対処されているか
- プロジェクト規約・アーキテクチャ方針に沿っているか
- セキュリティ: 認証・認可の抜け、データ露出リスク、入力バリデーション
- アーキテクチャ: レイヤー分離、依存方向、既存パターンとの一貫性、SOLID原則
- 品質: テストカバレッジ、エッジケース、バグ、パフォーマンス、フレームワーク固有のベストプラクティス
- コード: 命名規約、重複コード、エラーハンドリング、i18n の完全性
- diff 外の対応漏れ（テスト・ドキュメント・関連モジュール）

各指摘を Critical / Major / Minor の3段階で分類し、ファイル名:行番号付きで報告してください。
最終判定を APPROVE（問題なし）または REQUEST_CHANGES（要修正）で明示してください。
PROMPT_EOF
```

### tmux でのレビュアー起動手順

セッション名にはプロジェクト名・PR番号・対象コマンドを含める（例: `myapp-pr42-gemini`, `myapp-pr42-codex`）。

#### Gemini CLI（stdin 経由でプロンプトファイルを渡す）

```bash
tmux new-session -d -s ${PROJECT}-pr${PR_NUMBER}-gemini \
  "TERM=xterm-256color gemini -p ' ' -e '' < $GEMINI_PROMPT_FILE > /tmp/${PROJECT}-pr${PR_NUMBER}-gemini-review.md 2>&1; \
   echo \"EXIT_CODE=\$?\" >> /tmp/${PROJECT}-pr${PR_NUMBER}-gemini-review.md; \
   tmux wait-for -S ${PROJECT}-pr${PR_NUMBER}-gemini-done"
```

#### Codex CLI（stdin 経由でプロンプトファイルを渡す — diff・テストは自力実行）

`--full-auto` でコマンドを承認待ちなしに実行させる。
プロンプトは stdin から渡す（`-` 指定）ことで ARG_MAX 超過とバッククォート展開問題を両方回避。

```bash
tmux new-session -d -s ${PROJECT}-pr${PR_NUMBER}-codex \
  "cd <project-dir> && codex exec --full-auto \
   -o /tmp/${PROJECT}-pr${PR_NUMBER}-codex-review.md - \
   < $CODEX_PROMPT_FILE \
   2>/tmp/${PROJECT}-pr${PR_NUMBER}-codex-review.err; \
   echo \"EXIT_CODE=\$?\" >> /tmp/${PROJECT}-pr${PR_NUMBER}-codex-review.md; \
   tmux wait-for -S ${PROJECT}-pr${PR_NUMBER}-codex-done"
```

#### 結果の待機と取得
```bash
tmux wait-for <project>-pr<number>-gemini-done &
tmux wait-for <project>-pr<number>-codex-done &
wait

cat /tmp/<project>-pr<number>-gemini-review.md
cat /tmp/<project>-pr<number>-codex-review.md
```

### 重要: ヘッドレスモードを使う理由
- **`codex exec`**: 対話的 TUI を起動せず TTY 不要。tmux 内での表示崩れ・ハング・SIGHUP 問題を全回避
- **`gemini -p`**: ヘッドレスモードで TUI を起動しない。`TERM=xterm-256color` を設定しないとグラデーション描画でクラッシュする既知問題あり
- **絶対に対話モード（`codex` / `gemini`）を tmux で使わない** — TTY 問題で不安定になる

### クォータ・エラー時のフォールバック
- tmux セッションの出力ファイルが空、または `EXIT_CODE` が 0 以外の場合は失敗と判定
- 失敗した場合は1回リトライ（同じ tmux セッション名を `tmux kill-session` で削除してから再作成）
- 2回目も失敗した場合は、**Claude Code の Task エージェントを追加起動**して補完する
- 最低1レビュアーが成功すればレビューを続行する
- tmux セッションはレビュー完了後に `tmux kill-session -t <session>` でクリーンアップする

## ステップ3: レビュー結果の統合 & 修正

2レビュアーの結果を統合する。

### Critical / Major Issues がある場合:
1. Critical Issues をすべて修正
2. Major Issues をすべて修正
3. テストを再実行して修正が既存コードを壊していないことを確認
4. 修正内容を関心事ごとに適切に分割してコミットする（**日本語メッセージ**）
   - **禁止**: 「レビュー指摘対応」「レビュー修正」などレビュー起点であることを示すコミットメッセージ
   - **正しい例**: `fix: ユーザー入力のバリデーションを追加` / `refactor: 依存方向をレイヤー規約に従って修正`
5. **ステップ2 に戻って再レビュー**を実施

### Minor Issues のみ / Issues がない場合:
- 次のステップに進む

## ステップ4: 残課題の Issue 登録

マージ前に以下を確認する:

1. レビューで指摘された Minor Issues を洗い出す
2. 実装中に発見したがスコープ外の改善点を洗い出す
3. Claude Code が各 Minor Issue について対応要否を判断する
4. Issue 登録する場合:
```bash
gh issue create --title "..." --body "..." --label "..."
gh issue edit <new-number> --milestone "v1.0.0"
```

## ステップ5: Claude Code 最終レビュー

Claude Code が最終レビュアーとして、以下の観点で総合判定を行う。

1. Gemini / Codex のレビュー指摘が適切に反映されているか確認
2. diff 全体を改めて読み、見落としがないかチェック
3. diff 外の対応漏れ（テスト・ドキュメント・関連モジュール）を確認
4. プロジェクト規約・アーキテクチャ方針との整合性を検証

### レビュー結果の投稿

```bash
gh pr comment <number> --body "$(cat <<'EOF'
## 🤖 AI コードレビュー結果

### レビュアー
- Gemini CLI (tmux): ✅ / ❌
- Codex CLI (tmux): ✅ / ❌
- Claude Code (最終レビュー): ✅ / ❌

### 🔴 Critical Issues (マージ前に必須修正)
- ...

### 🟠 Major Issues (修正推奨)
- ...

### 🟡 Minor Issues (検討事項)
- ...

### ✅ 良い点
- ...

**総合判定:** APPROVE / REQUEST_CHANGES
EOF
)"
```

**重要:** `gh pr review` は使わず、必ず `gh pr comment` を使う。

## ステップ6: マージ

```bash
gh pr checks <number>
gh pr merge <number> --merge --delete-branch
```

マージ後:
1. 関連する GitHub イシューをクローズする
2. 次に着手するべきイシューの候補を `gh issue list` から提案する

## 注意事項

- **コミットメッセージは必ず日本語**で記述する
- **レビューは忖度なし** — 問題があれば遠慮なく指摘、問題がなければ素直に APPROVE
- tmux レビュアーは必ずヘッドレスモード（`codex exec` / `gemini -p`）で起動する — 対話モードは使わない
- レビューエージェントが失敗した場合は1回リトライし、それでも失敗したら Claude Code Task エージェントで補完
- `gh pr review` がブロックされたら即座に `gh pr comment` にフォールバック
- SHA キャッシュの問題でマージが失敗した場合は、PR をクローズして再オープンする
