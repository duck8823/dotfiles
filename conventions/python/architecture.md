# アーキテクチャ設計規約

## 概要

アーキテクチャ設計のパターンと依存関係の規約です。レイヤードアーキテクチャを採用し、各層の責務と依存関係を明確にします。パッケージ/依存管理は uv + `pyproject.toml`（PEP 621）、src レイアウトを前提とします。

## レイヤー構成

### 4層アーキテクチャ

```plaintext
┌─────────────────────────────────────┐
│  Presentation Layer                 │  ← HTTP ハンドラ（FastAPI）
├─────────────────────────────────────┤
│  Application Layer                  │  ← ユースケース、クエリサービス
├─────────────────────────────────────┤
│  Domain Layer                       │  ← エンティティ、値オブジェクト、リポジトリIF
├─────────────────────────────────────┤
│  Infrastructure Layer               │  ← DB実装、外部API、メッセージング
└─────────────────────────────────────┘
```

### 依存関係の方向

* **上位層から下位層への依存のみ許可**
* **Infrastructure → Domain への依存は インターフェース（`typing.Protocol`）経由**
* **循環参照は禁止**

```plaintext
Presentation → Application → Domain ← Infrastructure
```

依存方向は import 文として現れます。`domain` パッケージは `application` / `infrastructure` / `presentation` を import してはいけません。リポジトリの実体（Infrastructure）への依存はドメイン層に置いた `Protocol` を介し、実装は依存性注入で外部から差し込みます。

## パッケージ構成

src レイアウトを採用し、トップパッケージ配下に層ごとのサブパッケージを置きます。

```plaintext
src/app/
├── domain/
│   ├── model/
│   └── types/
├── application/
│   ├── usecase/
│   ├── queryservice/
│   └── types/
├── infrastructure/
└── presentation/
```

### domain パッケージ

ビジネスロジックの中核を担います。エンティティは識別子を持つ可変クラスとして定義し、同一性は id で判定します。生成系のファクトリは classmethod の `new`（エンティティ生成）/ `of`（同等情報からの復元）として公開します。

```python
# src/app/domain/model/user.py
"""ユーザーエンティティを定義するモジュール。"""

from __future__ import annotations

import datetime as dt

from app.domain.types.user import Email, UserId, UserType


def _now() -> dt.datetime:
    """現在時刻を返す（テストで差し替え可能にするため関数で分離する）。"""
    return dt.datetime.now(dt.UTC)


class User:
    """ユーザーを表すエンティティ。

    同一性は ``user_id`` で判定する。属性は可変だが、不変条件を破る変更は
    メソッド経由でのみ許可する。
    """

    def __init__(
        self,
        user_id: UserId,
        email: Email | None,
        display_name: str,
        user_type: UserType,
        created_at: dt.datetime,
        updated_at: dt.datetime,
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
        user_id: UserId,
        email: Email | None,
        display_name: str,
        user_type: UserType,
    ) -> User:
        """新しい User を生成する（時刻は内部で設定する）。"""
        now = _now()
        return cls(user_id, email, display_name, user_type, now, now)

    @classmethod
    def of(
        cls,
        user_id: UserId,
        email: Email | None,
        display_name: str,
        user_type: UserType,
        created_at: dt.datetime,
        updated_at: dt.datetime,
    ) -> User:
        """フィールドと同等の情報から User を生成する（DB等からの復元用）。"""
        return cls(user_id, email, display_name, user_type, created_at, updated_at)

    @property
    def user_id(self) -> UserId:
        """ユーザーの識別子。"""
        return self._user_id

    @property
    def email(self) -> Email | None:
        """ユーザーのメールアドレス（未設定なら ``None``）。"""
        return self._email

    @property
    def display_name(self) -> str:
        """表示名。"""
        return self._display_name

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, User):
            return NotImplemented
        return self._user_id == other._user_id

    def __hash__(self) -> int:
        return hash(self._user_id)
```

### domain/types パッケージ

値オブジェクトと DTO を統一管理します。値オブジェクトは `@dataclass(frozen=True)` で定義し、値等価とし、不変条件は `__post_init__` で検証します。同等情報からの生成は classmethod `of` を用います。

```python
# src/app/domain/types/user.py
"""ユーザー関連の値オブジェクトを定義するモジュール。"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum

from app.errors import ValidationError

_EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


@dataclass(frozen=True)
class UserId:
    """ユーザーの識別子を表す値オブジェクト。"""

    value: str

    def __post_init__(self) -> None:
        if not self.value:
            raise ValidationError("UserId は空にできません")

    @classmethod
    def of(cls, value: str) -> UserId:
        """文字列から UserId を生成する。"""
        return cls(value)

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class Email:
    """メールアドレスを表す値オブジェクト。"""

    value: str

    def __post_init__(self) -> None:
        if not _EMAIL_PATTERN.match(self.value):
            raise ValidationError(f"不正なメールアドレス形式です: {self.value}")

    @classmethod
    def of(cls, value: str) -> Email:
        """文字列から Email を生成する（形式を検証する）。"""
        return cls(value)


class UserType(StrEnum):
    """ユーザー種別。"""

    NORMAL = "normal"
    ADMIN = "admin"
```

NULL 許容値は `T | None` を型注釈で明示します。ポインタ的なラッパー型を独自に作らず、標準の Optional 表現（`X | None`）を用います。

### リポジトリインターフェース

ドメイン層に `typing.Protocol` でインターフェースを定義し、インフラ層で実装します。`Protocol` を用いることで、ドメイン層がインフラ層を import せずに済み、依存方向を内向きに保てます。

```python
# src/app/domain/model/user_repository.py
"""ユーザーリポジトリのインターフェースを定義するモジュール。"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from app.domain.model.user import User
from app.domain.types.user import UserId


@runtime_checkable
class UserRepository(Protocol):
    """ユーザーリポジトリのインターフェース。"""

    async def find_by_id(self, user_id: UserId) -> User | None:
        """ID でユーザーを取得する。存在しなければ ``None`` を返す。"""
        ...

    async def save(self, user: User) -> None:
        """ユーザーを保存する。"""
        ...

    async def delete(self, user_id: UserId) -> None:
        """ユーザーを削除する。"""
        ...
```

## application パッケージ

### ユースケース

ビジネスロジックのオーケストレーションを担当します。依存するリポジトリはコンストラクタ引数として Protocol 型で受け取り（コンストラクタインジェクション）、具象実装には依存しません。

```python
# src/app/application/usecase/user_usecase.py
"""ユーザー関連のユースケースを定義するモジュール。"""

from __future__ import annotations

from app.domain.model.user import User
from app.domain.model.user_repository import UserRepository
from app.domain.types.user import UserId


class UserUsecase:
    """ユーザー関連のユースケース。

    リポジトリは ``UserRepository`` プロトコルとして受け取り、具象実装には
    依存しない。
    """

    def __init__(self, user_repo: UserRepository) -> None:
        self._user_repo = user_repo

    async def get_user(self, user_id: UserId) -> User | None:
        """ユーザーを取得する。"""
        return await self._user_repo.find_by_id(user_id)
```

### クエリサービス

読み取り専用の複雑なクエリを担当します。インターフェースは `Protocol` で定義します。

```python
# src/app/application/queryservice/user_query_service.py
"""ユーザークエリサービスのインターフェースを定義するモジュール。"""

from __future__ import annotations

from typing import Protocol

from app.application.types.user import UserDto


class UserQueryService(Protocol):
    """ユーザークエリサービスのインターフェース。"""

    async def list_users(self, limit: int, offset: int) -> list[UserDto]:
        """ユーザー一覧を取得する。"""
        ...

    async def search_users(self, query: str) -> list[UserDto]:
        """条件に合致するユーザーを検索する。"""
        ...
```

### application/types パッケージ

アプリケーション層固有の型を定義します。

**原則はクエリサービス用の DTO** ですが、ドメイン層で定義するには不適切かつアプリケーション層の複数ユースケースで共有される型（ユースケース固有エンティティ・進捗管理型など）も例外的にここに置きます。DTO は値等価で扱うため `@dataclass(frozen=True)` を用います。

```python
# src/app/application/types/user.py
"""ユーザーの読み取り用 DTO を定義するモジュール。"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass


@dataclass(frozen=True)
class UserDto:
    """ユーザーの読み取り用 DTO。"""

    id: str
    email: str | None
    display_name: str
    created_at: dt.datetime
```

## infrastructure パッケージ

### datasource パターン

リポジトリとクエリサービスを **単一のクラス（datasource）で実装** します。Protocol は構造的部分型のため `implements` 宣言は不要ですが、適合を静的に保証するために mypy 用の型注釈（`UserRepository = UserDatasource(...)` のような代入や、明示的な型付き変数）で確認します。

```python
# src/app/infrastructure/postgres/user_datasource.py
"""ユーザーのデータソース実装を定義するモジュール。"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.application.types.user import UserDto
from app.domain.model.user import User
from app.domain.types.user import UserId


class UserDatasource:
    """ユーザーのデータソース。

    ``UserRepository`` と ``UserQueryService`` の双方を実装する（構造的部分型）。
    SQL は ``.sql`` に外出しし、``importlib.resources`` 経由で読み込む。
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def find_by_id(self, user_id: UserId) -> User | None:
        """ユーザーを ID で取得する（Repository 実装）。"""
        raise NotImplementedError

    async def save(self, user: User) -> None:
        """ユーザーを保存する（Repository 実装）。"""
        raise NotImplementedError

    async def delete(self, user_id: UserId) -> None:
        """ユーザーを削除する（Repository 実装）。"""
        raise NotImplementedError

    async def list_users(self, limit: int, offset: int) -> list[UserDto]:
        """ユーザー一覧を取得する（QueryService 実装）。"""
        raise NotImplementedError

    async def search_users(self, query: str) -> list[UserDto]:
        """ユーザーを検索する（QueryService 実装）。"""
        raise NotImplementedError
```

Protocol への適合は、組み立て箇所での型付き変数により mypy が検証します。

```python
from app.domain.model.user_repository import UserRepository
from app.application.queryservice.user_query_service import UserQueryService

# 適合しなければ mypy がエラーを報告する
_repo: UserRepository = UserDatasource(session)
_query: UserQueryService = UserDatasource(session)
```

### datasource パターンの利点

* **単一責任**: 1つのエンティティに対する DB 操作を1箇所に集約
* **コードの重複削減**: Repository と QueryService で共通のヘルパーを利用可能
* **テスト容易性**: 1つのクラスを差し替えれば両方のインターフェースをテスト可能

## 依存性注入

### エントリポイントでの組み立て

層の組み立て（ワイヤリング）はエントリポイント（`main` / アプリケーションファクトリ）に集約し、各層は具象実装を import しないようにします。FastAPI では `Depends` を DI として用い、ファクトリ関数で依存を解決します。

```python
# src/app/main.py
"""アプリケーションのエントリポイント。"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.application.usecase.user_usecase import UserUsecase
from app.infrastructure.postgres.user_datasource import UserDatasource
from app.presentation.user_router import build_user_router


def build_usecase(session: AsyncSession) -> UserUsecase:
    """セッションからユースケースを組み立てる。

    Datasource（Repository + QueryService）をユースケースへ注入する。
    """
    datasource = UserDatasource(session)
    return UserUsecase(datasource)


def create_app() -> FastAPI:
    """アプリケーションを生成する（依存の組み立てを行う）。"""
    engine = create_async_engine("postgresql+asyncpg://...")
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        yield
        await engine.dispose()

    app = FastAPI(lifespan=lifespan)
    app.include_router(build_user_router(session_factory))
    return app
```

ハンドラ層では `Depends` でユースケースを解決し、ハンドラ自体は薄く保ちます（詳細は [HTTP ハンドラ規約](http-handler.md)）。

## 関連ドキュメント

* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成、src レイアウト、uv
* [ドメインモデル設計規約](domain-model.md) - エンティティ、値オブジェクト、集約
* [型システムと Optional 規約](type-system.md) - `T | None`、ドメイン固有型
* [HTTP ハンドラ規約](http-handler.md) - FastAPI、Depends、例外マッピング
* [インフラストラクチャ規約](infrastructure.md) - SQLAlchemy、SQL 外出し、トランザクション境界

## 参考資料

* [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
* [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture/)
* [PEP 544 – Protocols: Structural subtyping](https://peps.python.org/pep-0544/)
