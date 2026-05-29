# Linter設定

## 概要

`ruff`（lint + format）と `mypy`（strict）の設定規約です。コード品質を保ちながら、プロジェクト固有の要件に合わせた設定を行っています。ツールは `uv` で管理し、設定はすべて `pyproject.toml`（PEP 621）に集約します。

## 有効化するツール

### 基本方針

* `ruff (lint)`: コーディングスタイル・バグパターン・import 整理のチェック
* `ruff (format)`: コード整形（`black` 互換）。`lint` と同一バイナリで完結させる
* `mypy (strict)`: 静的型解析による型安全性の検証

`ruff` が高速なスタイル・バグ検出を担い、`mypy` が型レベルのバグ検出を担います。両者は守備範囲が重なる箇所もあるため、後述のとおり責務を分けて二重指摘を避けます。

## 完全な設定ファイル

本ファイル（linter.md）を ruff / mypy 設定の single source of truth とします。他の規約ファイルに登場する `pyproject.toml` の設定例は抜粋であり、設定の正は本セクションを参照してください。

`pyproject.toml` の Linter 関連設定：

```toml
[tool.ruff]
src = ["src", "tests"]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
# select で有効化するルールを明示する（extend-select より優先）
select = [
    "E",    # pycodestyle (error)
    "W",    # pycodestyle (warning)
    "F",    # pyflakes
    "I",    # isort: import 順序
    "N",    # pep8-naming: 命名規則
    "UP",   # pyupgrade: 新しい構文への置き換え
    "B",    # flake8-bugbear: バグになりやすいパターン
    "BLE",  # flake8-blind-except: ブラインドな except
    "TRY",  # tryceratops: try/except のアンチパターン
    "ANN",  # flake8-annotations: 型注釈の欠落
    "D",    # pydocstyle: docstring
    "RUF",  # Ruff 固有ルール
]
ignore = []
# ANN401（Any を引数・戻り値に許す）は恒久 ignore しない。
# Any を多用するレガシー層など、限定的に許容する場合は per-file-ignores で対象を絞る。

[tool.ruff.lint.per-file-ignores]
# テストでは docstring 必須・assert 警告を緩和する
"tests/**/*.py" = ["D", "S101"]
# レガシー層など Any を限定的に許容する場合のみ ANN401 をファイル単位で抑制する
# "src/legacy/**/*.py" = ["ANN401"]

[tool.ruff.lint.pydocstyle]
convention = "google"  # PEP 257 Google style

[tool.ruff.format]
quote-style = "double"
docstring-code-format = true

[tool.mypy]
python_version = "3.12"
strict = true            # 厳格モードの一括有効化
warn_unreachable = true
warn_redundant_casts = true
# 個別の # type: ignore に必ずエラーコードを書かせる
enable_error_code = ["ignore-without-code", "redundant-expr", "truthy-bool"]

[[tool.mypy.overrides]]
# 型スタブを提供しないサードパーティのみ、欠落 import を黙認する（理由を明記）
module = ["thirdparty_without_stubs.*"]
ignore_missing_imports = true
```

`ignore` は「プロジェクト全体で恒久的に無効化する」ルールに限定します。一時的・局所的な抑制は後述の `# noqa` / `# type: ignore` で行います。`Any` の扱いについては [型システムと Optional 規約](type-system.md) を参照してください。

## 各ツールの役割

### ruff (lint)

* Python のコーディングスタイル・命名・バグパターンをチェックする
* `select` で有効化するルールを明示し、`extend-select` ではなく `select` を基準集合とする（ルールセットを一目で把握できるようにするため）
* 命名規則（`N`）と docstring（`D`）は [命名規則](naming.md) の方針に合わせる
* `I`（isort）で import 順序を自動整理し、整形は `ruff format` に委ねる

### ruff (format)

* `black` 互換の整形を行い、整形と lint を同一ツールに統一する
* `docstring-code-format = true` で docstring 内のコード例も整形対象にする
* フォーマット起因の差分を lint で重ねて指摘しないよう、整形は `format`、論理的なスタイルは `lint` と責務を分ける

### mypy (strict)

* 静的型解析で型レベルのバグを検出する
* `strict = true` により、`disallow_untyped_defs` / `disallow_any_generics` / `no_implicit_optional` などをまとめて有効化する。public API の型注釈漏れ（`ANN` と相補的）、暗黙の `Optional`、ジェネリックの素の使用などを禁止する
* 型スタブを提供しないサードパーティに対する `Missing imports` のみ `overrides` で黙認し、自前コードの型エラーは黙認しない
* `enable_error_code = ["ignore-without-code"]` により、`# type: ignore` にエラーコードの明示を強制する

## `# noqa` / `# type: ignore` の使用

### 基本方針

* lint / 型エラーを個別に抑制する必要がある場合は `# noqa: <ルールコード>` / `# type: ignore[<エラーコード>]` を使用する
* **必ず理由をコメントで記載する**
* **コードを省略した一括抑制（blanket ignore）は禁止する**。`# noqa`（コードなし）や `# type: ignore`（コードなし）は、対象外のエラーまで黙らせ、将来のバグを隠す
* プロジェクト全体で抑制すべきルールは `pyproject.toml` の `[tool.ruff.lint] ignore` / `[[tool.mypy.overrides]]` を使用する

### 使用例

#### サードパーティライブラリのインターフェース化

サードパーティライブラリのクライアントをテスタビリティのために `typing.Protocol` でインターフェース化する場合、ライブラリ側の型が `Any` を返すなどで `mypy` の strict ルールに抵触することがあります。この場合、元のライブラリの型定義を尊重するため、エラーコードを明示して抑制します。

```python
from typing import Protocol

import thirdparty


class ThirdPartyClient(Protocol):
    """サードパーティライブラリのクライアントインターフェース。

    テスタビリティのために必要な操作のみを定義する。
    """

    def operation(self, params: thirdparty.Input) -> thirdparty.Output:
        """単一の操作を実行する。"""
        ...


def call(client: ThirdPartyClient, params: thirdparty.Input) -> thirdparty.Output:
    """クライアントを呼び出す。"""
    # thirdparty.invoke は型スタブ未提供で Any を返すため、Protocol の戻り値型へ明示的に確定する
    return client.operation(params)  # type: ignore[no-any-return]  # スタブ未提供
```

#### 特定の行のみ抑制（ruff）

```python
API_KEY = "key"  # noqa: N816  # 外部仕様で定数名が定められているため命名規則から外れる
```

#### 複数のルールを抑制（ruff）

```python
def legacy_function():  # noqa: ANN201, D103  # 段階的移行中のレガシー関数。次期 PR で型注釈と docstring を付与
    ...
```

#### 型エラーの抑制（mypy）

```python
# 動的にロードしたプラグインの戻り値型を静的に確定できないため、呼び出し側で検証する
plugin = load_plugin(name)  # type: ignore[assignment]  # プラグインの型は実行時に検証する
```

### 抑制すべきでないケース

以下のような場合は `# noqa` / `# type: ignore` を使用せず、コードを修正してください：

* 自分で定義した型・関数・変数の命名規則違反
* 不要な変数や import（`F401` / `F841`）
* public API の型注釈・docstring の欠落（`ANN` / `D`）
* `T | None` で表現すべき箇所を `Any` で握りつぶしている型エラー
* 明らかなバグや非効率なコード

## 実行方法

```shell
# lint の実行
uv run ruff check .

# 自動修正可能な問題を修正
uv run ruff check --fix .

# 整形（差分チェックは --check）
uv run ruff format .
uv run ruff format --check .

# 型チェック
uv run mypy src
```

`pre-commit` で `ruff check` / `ruff format` / `mypy` を commit 時に実行する運用は [ローカル開発環境規約](local-dev.md) を参照してください。

## 関連ドキュメント

* [エラーハンドリング規約](error-handling.md) - `BLE` / `TRY` / `B904`、`raise X from e`
* [命名規則](naming.md) - `N`（pep8-naming）、`types` パッケージ命名
* [型システムと Optional 規約](type-system.md) - `Any` の扱い、`T | None`、mypy strict
* [ローカル開発環境規約](local-dev.md) - uv、pre-commit での lint / 型チェック

## 参考資料

* [Ruff Configuration](https://docs.astral.sh/ruff/configuration/)
* [Ruff Rules](https://docs.astral.sh/ruff/rules/)
* [The Ruff Formatter](https://docs.astral.sh/ruff/formatter/)
* [mypy - The mypy configuration file](https://mypy.readthedocs.io/en/stable/config_file.html)
