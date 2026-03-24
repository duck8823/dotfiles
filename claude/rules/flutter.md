---
globs: "**/*.dart"
---

# Flutter 共通ルール

- `flutter analyze` が通らない状態でコミットしない
- 例外は `implements Exception` の独自クラスとして定義し、一般的な `Exception` を直接 throw しない
- Freezed モデルは `@freezed` アノテーション付与。手書きの `copyWith` は作らない
- コード生成ファイル（`*.g.dart`, `*.freezed.dart`）は手書きしない（`build_runner` で生成）
- UI 文字列を追加する際は l10n ファイルにも追加する
- カラー・スペーシングはデザインシステム定数を使用。ハードコード禁止
- テストファイルは `test/` 以下にプロダクションコードと同じディレクトリ構成
