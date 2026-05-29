# エラーハンドリング規約

## 概要

エラーハンドリングの規約です。独自例外階層による分類と、原因の連鎖（chained exception）の保持を実現するための実装指針を定めています。

## 独自例外階層

### 基本方針

* **アプリケーション固有の例外は基底クラスから派生させた階層で定義する**
* 基底例外（例: `AppError`）を一つ用意し、すべての独自例外をそこから派生させる
* 組み込みの `Exception` を直接 `raise` しない。呼び出し側が `except AppError` で自分のドメインの例外だけを捕捉できるようにする
* 例外名は何が起きたのかを表す名詞句にし、末尾を `Error` で揃える

### 実装例

```python
"""アプリケーション共通の例外階層。"""


class AppError(Exception):
    """アプリケーション固有の例外の基底クラス。"""


class NotFoundError(AppError):
    """要求されたリソースが存在しない場合に送出する。"""


class ValidationError(AppError):
    """ドメインの不変条件に違反した場合に送出する。"""


class InfrastructureError(AppError):
    """DB・外部 API・ファイルシステム等のインフラ操作に失敗した場合に送出する。"""
```

基底クラスを起点にすることで、捕捉の粒度を呼び出し側が選べます。フレームワーク境界（例: HTTP ハンドラ）では `except AppError` でまとめて捕捉し、HTTP ステータスへマッピングできます。

値オブジェクトの不変条件違反（`__post_init__` 等での検証失敗）は、この階層の `ValidationError` を `raise` する。組み込みの `ValueError` やその場限りの未定義例外は使わない。

## 原因の連鎖（raise X from e）

### 基本方針

* **例外を捕捉して別の例外を送出する場合は** `raise X from e` **で原因を連鎖させる**
* `raise X from e` は `__cause__` に元の例外を保持し、トレースバックに「The above exception was the direct cause of ...」を出力するため、デバッグが容易になる
* `from e` を省いた `raise X` は文脈（`__context__`）が暗黙に残るだけで、意図的な連鎖か握りつぶしかが曖昧になる。原因を引き継ぐ意図がある場合は必ず `from e` を明記する
* 元の例外を意図的に断ち切る場合のみ `raise X from None` を使い、理由をコメントで残す

### 実装例

```python
from app.domain.types import UserId
from app.domain.user import User
from app.errors import AppError, NotFoundError, ValidationError


def get_user(self, user_id: UserId) -> User:
    """ユーザーを取得して検証する。

    Args:
        user_id: 取得対象のユーザー ID。

    Returns:
        検証済みのユーザーエンティティ。

    Raises:
        NotFoundError: 指定 ID のユーザーが存在しない場合。
        ValidationError: ユーザーがドメインの不変条件に違反している場合。
    """
    try:
        user = self._user_repo.find_by_id(user_id)
    except RepositoryError as e:
        raise NotFoundError(f"ユーザーの取得に失敗しました: {user_id}") from e

    if user is None:
        raise NotFoundError(f"ユーザーが見つかりません: {user_id}")

    try:
        self._validate_user(user)
    except ValueError as e:
        raise ValidationError("ユーザーのバリデーションに失敗しました") from e

    return user
```

### エラーメッセージの記述方法

* 日本語で分かりやすく記述する（OSS・外部コントリビューション前提の公開プロジェクトでは英語を優先）
* 何が失敗したのかを明確に示す
* 識別子など特定に役立つ情報をメッセージに含める。ただしパスワード・トークン等の秘匿情報は含めない
* 原因となった例外がある場合は `from e` で連鎖させ、メッセージで原因を文字列展開して握りつぶさない

## 例外の捕捉（narrow except）

### 基本方針

* **捕捉する例外は処理できる最も狭い型に絞る（narrow except）**
* `except Exception:` や `except BaseException:` での包括捕捉、引数を省いた `except:`（bare except）は禁止する。`KeyboardInterrupt` / `SystemExit` まで飲み込み、想定外のバグを隠す
* 捕捉した例外は「変換して再送出する」「ログを残して再送出する」「回復処理を行う」のいずれかを行う。何もしない `pass` は禁止する
* リソース解放のみが目的なら `try/finally` か `with`（コンテキストマネージャ）を使い、`except` で握りつぶさない

### 実装例

```python
import logging

from app.errors import AppError

logger = logging.getLogger(__name__)


# 良い例: 狭い型で捕捉し、ドメイン例外へ変換して連鎖
def load_config(path: str) -> Config:
    """設定ファイルを読み込む。

    Raises:
        ConfigError: ファイルが存在しないか不正な形式の場合。
    """
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except FileNotFoundError as e:
        raise ConfigError(f"設定ファイルが見つかりません: {path}") from e
    return _parse_config(raw)


# 悪い例: bare except / 包括捕捉で握りつぶす（禁止）
def load_config_bad(path: str) -> Config:
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except Exception:  # 想定外のバグまで隠れ、原因が追えなくなる
        return Config.default()
    return _parse_config(raw)
```

### ログと再送出の使い分け

* 同一の例外を捕捉・ログ出力・再送出する際は、`logger.exception(...)`（トレースバック付き）を使い、`logging` への記録は最も外側の境界（HTTP ハンドラやエントリポイント）で一度だけ行う。各層で重複ログを出さない
* ログを出すだけで処理を継続できないなら、再送出して上位に判断を委ねる

## ruff / mypy との統合

### 包括捕捉・bare except の検出

`ruff` の対応ルールを有効化し、包括的な例外捕捉や `from` 欠落を機械的に検出します。`# noqa` で無効化する場合は理由コメントを必須とします（`# type: ignore` も同様）。

```toml
# pyproject.toml
[tool.ruff.lint]
select = [
    "E",    # pycodestyle
    "F",    # pyflakes
    "B",    # flake8-bugbear: B902/B904 など例外周りを含む
    "BLE",  # flake8-blind-except: bare/包括 except を検出
    "TRY",  # tryceratops: try/except のアンチパターンを検出
]

# B904: except 節での raise には from を付ける
# BLE001: ブラインドな except を禁止
```

例外の連鎖（`raise X from e`）漏れは `B904` で、ブラインドな捕捉は `BLE001` で検出されます。意図的に握りつぶす稀なケースでは、`# noqa: BLE001  <理由>` のように理由を添えて抑制します。

### 型注釈との整合

* 送出しうる例外は docstring の `Raises:` セクションに明記する（mypy は例外型を追跡しないため、契約はドキュメントで担保する）
* `Optional[T]` 相当の「値が無い」状態を例外ではなく `T | None` で表現できる場合は、例外送出より戻り値での表現を優先する（型システムで検査できるため）

## 関連ドキュメント

* [インフラストラクチャパターン規約](infrastructure.md) - ログ記録、Graceful Shutdown
* [Linter設定](linter.md) - ruff / mypy 設定

## 参考資料

* [Python 公式: Errors and Exceptions](https://docs.python.org/3/tutorial/errors.html)
* [PEP 3134 – Exception Chaining and Embedded Tracebacks](https://peps.python.org/pep-3134/)
* [Ruff Rules](https://docs.astral.sh/ruff/rules/)
