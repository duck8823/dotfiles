---
globs: "**/*.gd,**/*.tscn,**/*.tres"
---

# Godot 共通ルール

- tscn ファイルを手動（テキストエディタ/コード）で編集しない。Godot エディタで行う
- `@export` で調整可能な数値を外部公開する（マジックナンバー禁止）
- 1ファイル1クラス
- シグナルは `snake_case`、接続は `_on_XXX_YYY()` 命名
- `.uid` ファイルはバージョン管理に含める（Godot 4.4+ 公式推奨）
- スクリプト/シェーダーを移動する際は `.uid` ファイルも一緒に移動
- GDScript スタイルガイド準拠: snake_case（変数・関数）、PascalCase（クラス・ノード）、UPPER_SNAKE_CASE（定数）
