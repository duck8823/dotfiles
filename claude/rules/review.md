# レビュー共通ルール

- diff に実在する内容のみ報告。推測・捏造しない
- レビュー結果は JSON 形式で返す（Multi-AI 統合のため）
- 重大度は CRITICAL / HIGH の2段階のみ報告。MEDIUM 以下は省略
- 問題がなければ `"summary": "問題なし"` と明記
- diff 外の対応漏れも積極的に調査する
- generated なファイルは原則レビュー対象外。generator / schema / template / build 設定を確認し、生成物そのものの指摘はユーザー明示時または生成不整合の検証時に限定する
- ファイル:行番号を必ず含める
