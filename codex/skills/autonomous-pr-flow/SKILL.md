---
name: autonomous-pr-flow
description: 実装からPR作成・Geminiレビュー反映・Codexレビュー反映・マージまでを止まらず自律実行するときに使う。ユーザーが「自律的に進めて」「止まらず進めて」「このフローで回して」と指示したら適用する。
---

# Autonomous PR Flow

## 目的
ユーザーの追加指示待ちを最小化し、**実装→レビュー反映→マージ**までを一気通貫で進める。

## 入力
- 対象リポジトリ / ブランチ戦略
- 受け入れ条件（Issue / PR description / 指示）
- レビュー方針（Gemini, Codex）

## 標準フロー
1. `main` を最新化し、作業ブランチを作成する。
2. 実装する（必要なら合理的仮定で前進）。
3. `lint / typecheck / test` を実行する。
4. 関心事ごとにコミットを分割する（1コミット1関心事）。
5. Draft PR を作成し、Motivation（何を達成するか）を明記する。
6. Gemini レビューを実行し、指摘を `MUST/SHOULD/NIT` でトリアージして反映する。
7. Gemini がブロッカーなしになるまで 6 を繰り返す。
8. PR を Ready/Open にし、`@codex review` を依頼する。
9. レビュー結果をポーリングで監視しつつ、止まらず次の実作業を進める。
10. Codex 指摘を反映し、再レビュー依頼を繰り返す。
11. Codex の issue が解消したらマージし、`main` に戻して同期する。

## 実行ルール
- ユーザーから明示指示がない限り、`main` へ直接 push しない。
- レビュー返信はスレッドに残し、何を直したかを簡潔に書く。
- 各修正後に必ず `lint / typecheck / test` を再実行する。
- 長時間待機は避け、ポーリングで状態確認しながら他タスクを進める。
- 誤検知レビューは「却下理由 + 検証結果」を残してクローズする。

## 推奨コマンド例
```bash
# PR作成（Draft）
gh pr create --draft --base main --head <branch>

# Codex再レビュー依頼
gh pr comment <pr-number> --body "@codex review"

# レビューコメント確認
gh api repos/<owner>/<repo>/pulls/<pr-number>/comments
```

## 完了条件
- 対象実装が `main` にマージ済み
- Open PR が残っていない
- ローカルブランチが `main` に戻っている

## 禁止
- 「進めます」の宣言だけで停止
- テスト未実行のまま PR 更新
- 指摘未対応のまま自己判断でマージ
