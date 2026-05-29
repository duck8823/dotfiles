# Python 共通ルール

- アーキテクチャ: レイヤードアーキテクチャ（Presentation → Application → Domain ← Infrastructure）。リポジトリインターフェースは Domain 層に `typing.Protocol` で定義し、依存方向は内向き
- エラーハンドリング: 独自例外階層を定義し、`raise <DomainError>(...) from e` で連鎖（traceback を保持）。bare `Exception` を直接 raise / except しない。エラーメッセージは日本語で記述（OSS プロジェクトでは英語を優先）
- ドメインモデル: ファクトリ classmethod は `new`（エンティティ生成）/ `of`（値オブジェクト・同等の情報から）/ `from_`（変換、`from` は予約語のため）。エンティティは識別子を持つ可変クラス（同一性は id）、値オブジェクトは `@dataclass(frozen=True)`（値等価）。不変条件は `__post_init__` で検証
- インフラストラクチャ: SQL は `.sql` ファイルに外出し（`importlib.resources` でロード）。datasource パターンで単一クラスがリポジトリとクエリサービスを同時実装
- 型: PEP 484 / 585 / 604 準拠。public API は型注釈必須、`Any` は理由なく使わない。`mypy --strict` を通る状態でコミットする
- Linter / 整形: `ruff`（lint + format）+ `mypy`（strict）を有効化。`# noqa` / `# type: ignore` 使用時は必ず理由コメント
- テスト: `pytest` + `@pytest.mark.parametrize`（テーブル駆動）。テストファイルは `tests/` 以下にプロダクションコードと同じディレクトリ構成。テストケース名は日本語で条件を表現（OSS プロジェクトでは英語を優先）
- ドキュメント: 公開モジュール・クラス・関数に docstring（PEP 257 / Google style）を必須化
- 命名: PEP 8 準拠（`snake_case`=関数・変数・モジュール、`PascalCase`=クラス、`UPPER_SNAKE_CASE`=定数）。`types` パッケージで値オブジェクト・DTO を統一管理
- NULL 許容値は `T | None` を明示的に扱う（暗黙の `None` を避ける）
- 依存管理は `uv` + `pyproject.toml`（PEP 621）、`src` レイアウトを基本とする

詳細: `conventions/python/` 配下の各規約ファイルを参照
