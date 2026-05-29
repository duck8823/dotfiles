# ドメインモデル設計規約

## 概要

ドメインモデルの設計規約です。ビジネスロジックを適切にモデル化します。

## エンティティと集約ルート

### 基本方針

* **エンティティは集約ルート** として設計する
* **識別子（id）を持つ可変クラス** として実装する（同一性は id で判定する）
* **フィールドはコンストラクタ経由で初期化** し、外部からの無秩序な再代入を避ける（更新はメソッド経由）
* **値の更新にはビジネスロジックを含むメソッド** を提供する
* **生成は `new` classmethod、永続化層からの復元は `of` classmethod** で行い、`__init__` を直接呼ばせない

エンティティは値ではなく同一性で識別されるため、不変（frozen）にはしない。値オブジェクトとは異なり `@dataclass(frozen=True)` を使わず、可変クラスとして実装する。

### 実装例

```python
"""ユーザーエンティティを定義するモジュール。"""

from __future__ import annotations

import datetime

from app.domain.model import _clock
from app.domain.types import Email, UserId, UserType


class User:
    """ユーザーを表すエンティティ。

    同一性は ``user_id`` で判定する。プロフィールの更新はメソッド経由で行い、
    更新日時などの副作用を内部で完結させる。
    """

    def __init__(
        self,
        *,
        user_id: UserId,
        email: Email | None,
        display_name: str,
        user_type: UserType,
        created_at: datetime.datetime,
        updated_at: datetime.datetime,
    ) -> None:
        self._user_id = user_id
        self._email = email
        self._display_name = display_name
        self._user_type = user_type
        self._created_at = created_at
        self._updated_at = updated_at

    @classmethod
    def new(
        cls,
        *,
        user_id: UserId,
        email: Email | None,
        display_name: str,
        user_type: UserType,
    ) -> User:
        """新しい User を生成する。

        生成時刻は ``_clock.now`` で注入された現在時刻を使用する。
        """
        now = _clock.now()
        return cls(
            user_id=user_id,
            email=email,
            display_name=display_name,
            user_type=user_type,
            created_at=now,
            updated_at=now,
        )

    @classmethod
    def of(
        cls,
        *,
        user_id: UserId,
        email: Email | None,
        display_name: str,
        user_type: UserType,
        created_at: datetime.datetime,
        updated_at: datetime.datetime,
    ) -> User:
        """フィールドと同等の情報（永続化層からの復元など）から User を生成する。"""
        return cls(
            user_id=user_id,
            email=email,
            display_name=display_name,
            user_type=user_type,
            created_at=created_at,
            updated_at=updated_at,
        )

    @property
    def user_id(self) -> UserId:
        """ユーザーの識別子を返す。"""
        return self._user_id

    @property
    def email(self) -> Email | None:
        """メールアドレスを返す（未設定時は ``None``）。"""
        return self._email

    @property
    def display_name(self) -> str:
        """表示名を返す。"""
        return self._display_name

    @property
    def user_type(self) -> UserType:
        """ユーザー種別を返す。"""
        return self._user_type

    @property
    def created_at(self) -> datetime.datetime:
        """作成日時を返す。"""
        return self._created_at

    @property
    def updated_at(self) -> datetime.datetime:
        """更新日時を返す。"""
        return self._updated_at

    def update_profile(self, *, email: Email | None, display_name: str) -> None:
        """プロフィール（メールアドレスと表示名）を更新する。

        更新日時の再設定という副作用を内部で完結させる。
        """
        self._email = email
        self._display_name = display_name
        self._updated_at = _clock.now()

    def __eq__(self, other: object) -> bool:
        """同一性（``user_id``）で等価性を判定する。"""
        if not isinstance(other, User):
            return NotImplemented
        return self._user_id == other._user_id

    def __hash__(self) -> int:
        """``user_id`` でハッシュ値を算出する。"""
        return hash(self._user_id)
```

#### `__eq__` / `__hash__` 方針

* **エンティティは識別子（id）で等価性を判定** する。フィールド全体の値比較ではない
* `__eq__` は型が一致しない場合 `NotImplemented` を返す（`==` のフォールバックを正しく機能させるため）
* `__eq__` を定義したら **`__hash__` も id ベースで定義** する。set / dict のキーとして使えるようにし、ミュータブルなフィールドをハッシュに含めない
* 値の取得には `@property` を使い、フィールド（`_xxx`）は非公開にする

## 値オブジェクト（types）

### 基本方針

* **値オブジェクトは不変** である（`@dataclass(frozen=True)`）
* **値等価で比較** する（`@dataclass(frozen=True)` が `__eq__` / `__hash__` を自動生成する）
* **不変条件は `__post_init__` で検証** し、不正な値ではインスタンスを生成させない

### 実装パターンの使い分け

値オブジェクトには2つの実装パターンがある。型の性質に応じて使い分ける。

#### パターン1: `StrEnum`（enum・ステータスなど固定の選択肢を持つ型）

バリデーション以外に追加ロジックが不要な、取りうる値が有限集合の型に使用する。文字列値を持つドメイン enum は `StrEnum` を用いる。

```python
"""プラットフォームを表す enum を定義するモジュール。"""

from __future__ import annotations

from enum import StrEnum


class Platform(StrEnum):
    """配信対象のプラットフォームを表す enum。"""

    IOS = "ios"
    ANDROID = "android"
    UNKNOWN = "unknown"

    @classmethod
    def from_(cls, value: str) -> Platform:
        """文字列から Platform を変換して生成する。

        Raises:
            ValueError: 既知のプラットフォームに該当しない場合。
        """
        try:
            return cls(value)
        except ValueError as e:
            raise ValueError(f"unknown platform: {value!r}") from e

    def is_known(self) -> bool:
        """既知のプラットフォーム（iOS / Android）かどうかを返す。"""
        return self in (Platform.IOS, Platform.ANDROID)
```

#### パターン2: `@dataclass(frozen=True)`（識別子・複合値・検証を伴う型）

UUID を内包する識別子、複数フィールドを持つ複合型、または生成時に不変条件の検証を必要とする型に使用する。

```python
"""配信リクエストの識別子を定義するモジュール。"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field


@dataclass(frozen=True)
class DeliveryId:
    """配信リクエストの識別子を表す値オブジェクト。"""

    value: uuid.UUID

    @classmethod
    def new(cls) -> DeliveryId:
        """新しい DeliveryId を生成する。"""
        return cls(value=uuid.uuid4())

    @classmethod
    def from_(cls, value: str) -> DeliveryId:
        """文字列から DeliveryId を変換して生成する。

        Raises:
            ValueError: UUID として解釈できない場合。
        """
        try:
            return cls(value=uuid.UUID(value))
        except ValueError as e:
            raise ValueError(f"invalid DeliveryId format: {value!r}") from e

    def __str__(self) -> str:
        """UUID の文字列表現を返す。"""
        return str(self.value)
```

```python
"""エンドポイント識別子を定義するモジュール。"""

from __future__ import annotations

from dataclasses import dataclass

from app.errors import ValidationError


@dataclass(frozen=True)
class EndpointId:
    """エンドポイントの識別子を表す値オブジェクト。

    空文字を許容しない不変条件を ``__post_init__`` で検証する。
    """

    value: str

    def __post_init__(self) -> None:
        """不変条件を検証する。

        Raises:
            ValidationError: 値が空文字の場合。
        """
        if not self.value:
            raise ValidationError("EndpointId must not be empty")

    def __str__(self) -> str:
        """識別子の文字列表現を返す。"""
        return self.value
```

```python
"""メッセージ内容を表す複合値オブジェクトを定義するモジュール。"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Content:
    """メッセージの内容を表す複合値オブジェクト。"""

    body: str
    title: str | None = None

    @classmethod
    def of(cls, *, body: str, title: str | None = None) -> Content:
        """同等の情報から Content を生成する。"""
        return cls(body=body, title=title)
```

#### `__post_init__` での不変条件検証

* **不正な値ではインスタンスを生成させない**。検証は `__post_init__` に集約し、呼び出し側に検証責務を漏らさない
* `frozen=True` のフィールドを `__post_init__` で正規化（再代入）する場合は `object.__setattr__` を使う。ただし正規化は最小限にとどめ、原則として呼び出し側で正しい値を渡す
* 検証失敗時は独自例外階層またはドメイン例外を `raise ... from e` で連鎖させる（[エラーハンドリング規約](error-handling.md) を参照）

### コンストラクタ命名規則

`__init__` は直接呼ばず、意図を表す classmethod を入口にする。

| 命名 | 用途 | 例 |
| --- | --- | --- |
| `new` | モデル/値オブジェクトの新規生成 | `User.new(...)`, `DeliveryId.new()` |
| `of` | モデル/値オブジェクトをフィールドと同等の情報から生成 | `User.of(...)`, `Content.of(...)` |
| `from_` | 値オブジェクトを変換して生成（例: 文字列から enum / UUID） | `DeliveryId.from_(s)`, `Platform.from_(s)` |

* `from` は予約語のため、変換ファクトリは末尾アンダースコアの `from_` を用いる
* `@dataclass(frozen=True)` の値オブジェクトでも、生成意図を明示するため可能な限り `new` / `of` / `from_` を入口にする

## 可変性の使い分け

| 型 | 可変性 | 等価性 | 理由 |
| --- | --- | --- | --- |
| **エンティティ（model）** | 可変クラス | 識別子（id）で判定 | 状態を持ち、ライフサイクルを通じて変化するため |
| **値オブジェクト（types）** | 不変 `@dataclass(frozen=True)` | 値等価（全フィールド比較） | 不変であり、値そのものが同一性を表すため |

**エンティティは可変クラスで id ベースの `__eq__` / `__hash__`**、**値オブジェクトは `@dataclass(frozen=True)` で自動生成の値等価**で統一する。

## 属性の更新

* **更新時には必要な副作用（例: 更新日時の設定）** も同時に処理する
* **一部の属性のみを更新し、他の属性（例: 種別、作成日時）は維持** する
* 値オブジェクトは不変のため「更新」せず、新しいインスタンスへの差し替えで表現する

```python
def update_profile(self, *, email: Email | None, display_name: str) -> None:
    """プロフィールを更新し、更新日時を再設定する。"""
    self._email = email
    self._display_name = display_name
    self._updated_at = _clock.now()
```

## テスト容易性

### 時刻の注入

生成時刻に依存するエンティティをテスト可能にするため、現在時刻の取得を差し替え可能な関数に集約する。

```python
"""ドメイン層で使用する時刻取得を集約するモジュール。"""

from __future__ import annotations

import datetime
from collections.abc import Callable

_now_func: Callable[[], datetime.datetime] = lambda: datetime.datetime.now(datetime.UTC)


def now() -> datetime.datetime:
    """現在時刻を返す。テスト時は ``set_now`` で固定できる。"""
    return _now_func()


def set_now(func: Callable[[], datetime.datetime]) -> None:
    """時刻取得関数を差し替える（テスト用）。"""
    global _now_func
    _now_func = func


def reset_now() -> None:
    """時刻取得関数を既定値に戻す（テスト用）。"""
    global _now_func
    _now_func = lambda: datetime.datetime.now(datetime.UTC)
```

* 実運用ではグローバル差し替えではなく、`Clock` プロトコルをコンストラクタ注入する構成も採用してよい。どちらを使うかはプロジェクトの DI 方針に合わせる（[アーキテクチャ設計規約](architecture.md) を参照）
* テストでは `pytest` の fixture で `set_now` / `reset_now` を setup / teardown する

## リポジトリインターフェースとファクトリパターン

リポジトリやサービスに複数の実装が存在する場合:

* **インターフェースはドメイン層に `typing.Protocol` で定義** する
* **実装はインフラ層（infrastructure）に配置** する
* **依存性の組み立て（DI）はエントリポイントまたは Presentation 層**（FastAPI の `Depends` など）で行う

```python
"""ユーザーリポジトリのインターフェースを定義するモジュール。"""

from __future__ import annotations

from typing import Protocol

from app.domain.model.user import User
from app.domain.types import UserId


class UserRepository(Protocol):
    """ユーザーの永続化を担うリポジトリのインターフェース。"""

    async def find_by_id(self, user_id: UserId) -> User | None:
        """識別子で User を取得する。存在しなければ ``None`` を返す。"""
        ...

    async def save(self, user: User) -> None:
        """User を永続化する。"""
        ...

    async def delete(self, user_id: UserId) -> None:
        """識別子で User を削除する。"""
        ...
```

* `Protocol` は構造的部分型のため、実装側に明示的な継承は不要。実装漏れを mypy で検出するため、実装クラスに `UserRepository` 型注釈を付ける変数で受けるか、明示的に `class UserDatasource(UserRepository)` と継承させて静的検査を効かせる
* インフラ層の実装（datasource パターン）とトランザクション境界は [インフラストラクチャ規約](infrastructure.md) を参照

## 関連ドキュメント

* [型システムと型注釈規約](type-system.md) - `T | None`、ドメイン固有型、`Protocol`
* [アーキテクチャ設計規約](architecture.md) - レイヤー構成、依存性注入
* [プロジェクト構成規約](project-structure.md) - src レイアウト、ディレクトリ構成
* [エラーハンドリング規約](error-handling.md) - 独自例外階層、`raise ... from e`

## 参考資料

* [Domain-Driven Design Reference](https://www.domainlanguage.com/ddd/reference/)
* [PEP 557 – Data Classes](https://peps.python.org/pep-0557/)
