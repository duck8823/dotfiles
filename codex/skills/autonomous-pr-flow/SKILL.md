---
name: autonomous-pr-flow
description: 自律実行を1Issueではなく全体進行（複数Issue/PR）で回すときに使う。ユーザーが「自律的に進めて」「止まらず進めて」「このフローで回して」と指示したら適用する。
---

# Autonomous PR Flow (Whole Delivery)

## 目的
ユーザーの追加指示待ちを最小化し、**実装→レビュー反映→マージ→次タスク着手**を全体ループで継続する。

## スコープ
このスキルは**単発PRの手順**ではなく、スプリント/マイルストーン全体の自律進行を対象とする。

## CLAUDE 構成との対応
- 全体ループ: `claude/commands/sprint.md`
- 作業対象ループ: `claude/commands/implement-issue.md`
- レビュー反映ループ: `claude/commands/review-and-merge.md`

## 体制（Claude と Codex の違い）
- 設計の最終意思決定は Claude 側で行う（Codex は選択肢とリスクを提示）
- レビューは Gemini/Codex が一次レビュー、Claude が最終レビューとマージ可否判断を担当
- Codex は指摘対応ループの実行担当として、最終ゲートは Claude 側ポリシーに従う

## 実行主体ごとのレビュー編成
- **Claude 主体**: Claude / Codex / Gemini の3AI体制で回す
  - Codex + Gemini を一次レビュー
  - Claude を最終レビュー
- **Codex 主体**: Codex / Gemini の2AI + PR上 `@codex review` で回す
  - Gemini を一次レビュー
  - PR上の Codex レビュー指摘を解消して収束させる

このスキルの標準動作は上記2モードとし、実行主体に応じて必ず切り替える。

## レベル1: 全体ループ（複数Issue/PR）
1. `main` を最新化し、Open Issue / Open PR / 直近マージ状況を確認する。
2. 次の作業対象を決定する（優先順位: ユーザー指定 > クリティカル/バグ > マイルストーン > 依存関係）。
3. レベル2（作業対象ループ）を実行する。
4. マージ後に `main` へ戻って同期し、次の対象に進む。
5. 停止条件（バックログ枯渇 / ユーザー停止指示）まで繰り返す。

## レベル2: 作業対象ループ（Issue/PR）
1. 実装
2. `lint / typecheck / test`
3. コミット分割（1コミット1関心事）
4. Draft PR 作成（Motivation必須）
5. Gemini レビュー依頼 → 指摘反映を繰り返し
6. Ready/Open + `@codex review`
7. Codex 指摘反映 → 再レビュー依頼を繰り返し
8. ブロッカー解消後にマージ

## 実行ルール
- ユーザーから明示指示がない限り `main` へ直接 push しない（全リポジトリ共通）。
- 各修正後に必ず `lint / typecheck / test` を再実行する。
- レビュー待機はポーリングで監視し、停止せず並行可能な作業を進める。
- 誤検知レビューは「却下理由 + 検証結果」をスレッドに残す。
- レビューコメント返信は「何をどう直したか」を簡潔に記録する。

## 推奨コマンド例
```bash
# Draft PR
gh pr create --draft --base main --head <branch>

# Codex再レビュー
gh pr comment <pr-number> --body "@codex review"

# レビューコメント一覧
gh api repos/<owner>/<repo>/pulls/<pr-number>/comments
```

## 完了条件
- 対象マイルストーン/スプリントの実装対象が処理済み
- Open PR が残っていない
- ローカルブランチが `main` に戻っている

## 禁止
- 「進めます」の宣言だけで停止
- テスト未実行のまま PR 更新
- 指摘未対応のまま自己判断でマージ
