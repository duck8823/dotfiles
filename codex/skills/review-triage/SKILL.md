---
name: review-triage
description: レビュー指摘を MUST / SHOULD / NIT に分類し、再現手順、影響範囲、修正優先順、対応方針を整理するときに使う。Gemini 1st pass と Claude 最終レビューの接続にも使う。
---

# Review Triage

## 入力
- レビュー指摘一覧
- 対象 diff / ファイル
- 受け入れ条件
- 既知の制約

## 手順
1. 指摘を事実ベースで正規化する。
2. 重大度を分類する。
   - MUST: リリース阻害
   - SHOULD: 品質低下の主要因
   - NIT: 任意改善
3. 各指摘に再現手順と影響範囲を付与する。
4. 修正順を決める（MUST優先）。
5. 却下する指摘は理由を明記する。

## Structure-Behavior 観点の分類
- MUST: 認可・課金・契約・migration・public API などで責務配置ミスや境界漏れが事故に直結する
- MUST: テストがなく、状態遷移・不変条件・エラー処理の破壊を検出できない
- SHOULD: handler / controller / usecase / service が core rule を抱え、次変更で肥大化する
- SHOULD: data-only model、primitive obsession、hidden side effect、decision logic と IO の混在がある
- SHOULD: oversized interface、boolean flag、infra DTO leakage により境界が脆くなっている
- NIT: 命名や小さな抽象化の改善だが、現時点で変更容易性を大きく阻害しない

## 出力フォーマット
- 優先度付き指摘リスト（MUST/SHOULD/NIT）
- 各項目の根拠・再現手順・修正方針
- より良い責務 owner / boundary（該当する場合）
- 未対応項目と理由
- マージ可否判断（可 / 条件付き可 / 不可）

## 禁止
- 重大度なしの羅列
- 再現手順なしの指摘
- 根拠なしの「問題なし」判定
