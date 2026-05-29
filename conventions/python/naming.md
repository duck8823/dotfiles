# 命名規則

## 概要

命名規則です。一貫性のある命名により、コードの可読性と保守性を向上させます。PEP 8 を基準とし、ruff の `N` ルール（pep8-naming）で機械的に検証します。

## パッケージ・モジュール命名

### types パッケージの使用

* **値オブジェクト（domain/types）とDTO（application/types）を格納するパッケージとして** `types` を使用する
* 標準ライブラリの `typing` とは別物だが、プロジェクト内で一貫して使用する
* `types` という名前は Python 標準ライブラリにも存在するため、絶対 import（`from app.domain import types`）で参照し、`import types`（標準ライブラリ）との衝突を避ける

```python
# 推奨: パッケージ修飾で参照する
from app.domain import types

user_id = types.UserId.of("u-001")
```

### 一般方針

* **パッケージ・モジュール名: 小文字、短く、単語区切りはアンダースコアを避けて単語1つを基本とする（例:** `model`**,** `usecase`**,** `infrastructure`）
* 複数単語が避けられない場合のみ snake_case を許可する（例: `http_handler`）。ハイフンは使えない
* `src` レイアウトを採用し、トップレベルパッケージは配布名と一致させる（例: `src/app/`）

## 一般的な命名規則

### 基本方針

* PEP 8 の命名規則に従う
* **モジュール名: 小文字 snake_case（例:** `user_repository.py`）
* **クラス名: PascalCase（例:** `User`**,** `UserId`）
* **識別子値オブジェクトの頭字語は各単語頭大文字で統一する（例:** `UserId`**,** `OrderId`**。`UserID` のように頭字語を全大文字にしない。ただし標準型の `UUID` と enum メンバの全大文字は対象外）**
* **関数・変数名: snake_case（例:** `new_user`**,** `get_user`）
* **定数: UPPER_SNAKE_CASE（例:** `DEFAULT_TIMEOUT`）
* **型変数: PascalCase、短い名前（例:** `T`**,** `KT`**,** `VT`）

### 可視性（public / non-public）

Go の exported / unexported に相当する区別を、Python では **アンダースコア接頭辞** で表現します。

* **public: 接頭辞なし（例:** `User`**,** `new_user`）
* **non-public（モジュール内部・実装詳細）: 単一アンダースコア接頭辞（例:** `_internal_cache`**,** `_validate`）
* **name mangling が必要な属性: 二重アンダースコア接頭辞（例:** `__secret`**）。サブクラスとの名前衝突を避けたい場合に限り使用する**
* 単一アンダースコアの要素は公開 API ではないため、`__all__` に含めない

```python
__all__ = ["User", "new_user"]


def new_user(user_id: "types.UserId", display_name: str) -> "User":
    """ユーザーを生成する。"""
    _validate_display_name(display_name)
    return User(user_id=user_id, display_name=display_name)


def _validate_display_name(display_name: str) -> None:
    """表示名の不変条件を検証する（モジュール内部）。"""
    if not display_name:
        raise ValueError("display_name must not be empty")
```

## ドメインモデル特有の命名

### ファクトリ classmethod

Go の `New` / `Of` / `From` 関数に相当するものを、Python では **classmethod** として定義します。`from` は予約語のため `from_` を使用します。

* **エンティティの生成:** `new`**（例:** `User.new`**,** `DeliveryId` はエンティティではないため対象外）
* **同等の情報から値オブジェクトを生成:** `of`**（例:** `UserId.of`**,** `Content.of`）
* **変換して生成（例: 文字列から Enum）:** `from_`**（例:** `Platform.from_`**,** `DeliveryId.from_`）

詳細は [ドメインモデル設計規約](domain-model.md) のコンストラクタ命名規則を参照。

### 実装例

```python
from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from app.errors import ValidationError
from app.domain import types


class User:
    """ユーザーエンティティ。同一性は user_id で判定する。

    フィールドは非公開（``_xxx``）とし、値の取得は ``@property`` で公開する
    （カプセル化の詳細は [ドメインモデル設計規約](domain-model.md) を参照）。
    """

    def __init__(
        self,
        user_id: types.UserId,
        email: types.Email | None,
        display_name: str,
    ) -> None:
        self._user_id = user_id
        self._email = email
        self._display_name = display_name

    @classmethod
    def new(
        cls,
        user_id: types.UserId,
        email: types.Email | None,
        display_name: str,
    ) -> User:
        """ユーザーを新規生成する。"""
        return cls(user_id=user_id, email=email, display_name=display_name)

    @property
    def user_id(self) -> types.UserId:
        """ユーザーの識別子を返す。"""
        return self._user_id

    @property
    def email(self) -> types.Email | None:
        """メールアドレスを返す（未設定時は ``None``）。"""
        return self._email

    @property
    def display_name(self) -> str:
        """表示名を返す。"""
        return self._display_name


@dataclass(frozen=True)
class UserId:
    """ユーザー識別子の値オブジェクト。"""

    value: str

    @classmethod
    def of(cls, value: str) -> UserId:
        """同等の情報（文字列）から値オブジェクトを生成する。"""
        return cls(value=value)


class Platform(StrEnum):
    """配信プラットフォームの列挙。"""

    WEB = "web"
    MOBILE = "mobile"

    @classmethod
    def from_(cls, value: str) -> Platform:
        """文字列を変換して列挙値を生成する。"""
        try:
            return cls(value)
        except ValueError as e:
            raise ValidationError(f"unknown platform: {value}") from e
```

## 関連ドキュメント

* [ドメインモデル設計規約](domain-model.md) - エンティティ、値オブジェクト
* [型システムと Optional 規約](type-system.md) - ドメイン固有型、`T | None`
* [Linter 設定](linter.md) - ruff / mypy 設定

## 参考資料

* [PEP 8 - Naming Conventions](https://peps.python.org/pep-0008/#naming-conventions)
* [PEP 257 - Docstring Conventions](https://peps.python.org/pep-0257/)
* [ruff - pep8-naming (N)](https://docs.astral.sh/ruff/rules/#pep8-naming-n)
