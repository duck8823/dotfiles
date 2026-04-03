---
description: 計画専用セッション。コード実装は行わず、イシュートリアージ・マイルストーン整理・スプリント計画のみ実行する
argument-hint: [milestone-name] (省略時は現在のマイルストーン)
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]
---

# 計画専用ワークフロー

**コードの実装は一切行わない。計画とイシュー整理のみ。**

対象マイルストーン: **$ARGUMENTS** (省略時は直近のオープンマイルストーン)

## ステップ1: 現状把握

```bash
# マイルストーン一覧
gh api repos/{owner}/{repo}/milestones --jq '.[] | "\(.title) (open: \(.open_issues), closed: \(.closed_issues))"'

# 対象マイルストーンのオープンイシュー
gh issue list --milestone "<milestone>" --state open --json number,title,body,labels,assignees
```

## ステップ2: 2AI 並列で計画を多面的に評価

### Codex planner
- コードベースを実読して Issue 間の依存・ファイル競合・Wave 構成を出す
- フィジビリティ、技術リスク、実装分割、どの Issue を Codex worker に寄せやすいかを出す

### Gemini planner
- マイルストーン整合、優先度、スコープ過多、抜けている Issue を出す

外部 CLI をヘッドレスで起動して結果を保存し、Claude メインセッションが統合する。

## ステップ3: イシュー品質チェック

各オープンイシューに対して:
1. `gh issue view <number>` で詳細を確認
2. 技術的な詳細説明があるか確認
3. 不足している場合は具体的な技術仕様や受け入れ条件の追記を提案
4. 影響範囲が曖昧なら Gemini / Codex の結果も参照して補足する

## ステップ4: スプリント構成

以下を満たすように構成する:

- ユーザー価値のある Issue を最低1つ含める
- tech-debt だけで埋めない
- ファイル競合が少ない並び順にする
- 大きすぎる Issue は分割提案を出す
- Codex worker に寄せる Issue と Claude foreground に残す Issue を分ける

## ステップ5: スプリント計画サマリー

以下のフォーマットで提示:

```markdown
## スプリント計画: <マイルストーン名>

### 優先順位順イシュー
1. #XXX: タイトル [ラベル] — 推定規模: S/M/L — 主担当: Claude / Codex
2. #XXX: タイトル [ラベル] — 推定規模: S/M/L — 主担当: Claude / Codex

### Wave 構成
- Wave 1: #123, #128
- Wave 2: #135

### 注意事項
- 依存関係があるイシュー
- 技術的リスクが高いイシュー
- diff 外で先に揃えるべき設定 / ドキュメント

### 不足しているイシュー（提案）
- 必要だが未作成のイシュー
```

## ステップ6: 永続化

- 計画結果は GitHub イシューのコメントかプロジェクトメモリに保存する
- 次回 `/sprint` で参照できるよう、Wave と担当分担を残す

## 注意事項

- このセッションではコードを一切書かない・編集しない
- Gemini は read-only scout として扱う
- Codex は worker 観点の計画支援に使うが、このセッションで実装はさせない
