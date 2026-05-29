# インフラストラクチャパターン規約

## 概要

インフラストラクチャ層の設計パターンと実装規約です。ログ記録、Graceful Shutdown、ミドルウェアなど、本番環境で必要となる横断的関心事を扱います。

## ログ記録規約

### 基本方針

* **構造化ログ** を使用する（JSON 形式を推奨）
* **コンテキスト情報**（リクエスト ID など）を含める
* **適切なログレベル** を使用する（DEBUG、INFO、WARNING、ERROR）
* **機密情報**（パスワード、トークン、ユーザー ID など）はログに出力しない
* **標準の** `logging` パッケージを使用する。JSON 整形には `structlog` などのアダプタを用いてもよいが、依存追加の根拠を残す

### 実装例

```python
"""アプリケーションのロギング設定。"""

import json
import logging
import os
import sys
from typing import Any


class JsonFormatter(logging.Formatter):
    """ログレコードを JSON 1 行に整形するフォーマッタ。"""

    def format(self, record: logging.LogRecord) -> str:
        """ログレコードを JSON 文字列へ変換する。"""
        payload: dict[str, Any] = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # extra= で渡した構造化フィールドを取り込む
        if hasattr(record, "context"):
            payload.update(record.context)  # type: ignore[attr-defined]  # extra 由来の動的属性
        return json.dumps(payload, ensure_ascii=False)


def configure_logging() -> None:
    """環境に応じたログレベルで JSON ロガーを初期化する。"""
    env = os.getenv("ENV", "production")
    level = logging.DEBUG if env == "development" else logging.INFO

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

    logging.getLogger(__name__).info(
        "アプリケーションを起動",
        extra={"context": {"env": env, "version": "1.0.0"}},
    )
```

### コンテキストへのフィールド追加

リクエスト ID などの共通情報をログへ伝播させる場合、`contextvars` を使用します。グローバル変数や引数の引き回しは避け、非同期処理でも安全にコンテキストを引き継ぎます。

```python
"""リクエスト ID をコンテキスト経由で伝播させるミドルウェア。"""

import uuid
from collections.abc import Awaitable, Callable
from contextvars import ContextVar

from starlette.requests import Request
from starlette.responses import Response

# context key は専用の ContextVar を使用する（グローバル変数の共有は禁止）
_request_id: ContextVar[str | None] = ContextVar("request_id", default=None)


def request_id_from_context() -> str | None:
    """現在のコンテキストからリクエスト ID を取得する。"""
    return _request_id.get()


async def request_id_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """リクエストごとに ID を採番しコンテキストへ格納する。"""
    request_id = str(uuid.uuid4())
    token = _request_id.set(request_id)
    try:
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response
    finally:
        _request_id.reset(token)
```

## Graceful Shutdown

### 基本方針

* **シグナル（SIGTERM、SIGINT）を受信したら、新しいリクエストを拒否** する
* **処理中のリクエストは完了するまで待機** する（タイムアウトあり）
* **データベース接続やメッセージキューなどのリソースを適切にクローズ** する

### 実装例

FastAPI では `lifespan` コンテキストマネージャで起動・終了処理を一元管理します。`yield` 前で接続を確立し、`yield` 後でクローズします。`uvicorn` は SIGTERM / SIGINT を受信すると新規リクエストを止め、処理中のリクエスト完了を待ってから `lifespan` の終了処理を呼びます。

```python
"""アプリケーションのライフサイクル管理。"""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """起動時に接続を確立し、終了時に確実にクローズする。"""
    engine: AsyncEngine = create_async_engine(
        "postgresql+asyncpg://localhost/app",
        pool_size=10,
    )
    app.state.engine = engine
    logger.info("データベース接続プールを初期化")
    try:
        yield
    finally:
        # SIGTERM/SIGINT 後、処理中リクエスト完了を待ってから呼ばれる
        await engine.dispose()
        logger.info("データベース接続プールをクローズ")


def create_app() -> FastAPI:
    """ライフサイクル付きの FastAPI アプリを生成する。"""
    return FastAPI(lifespan=lifespan)
```

FastAPI に依存しないワーカープロセスでは、`asyncio` のシグナルハンドラで停止フラグを立て、処理ループを抜けてからリソースをクローズします。

```python
"""非同期ワーカーの Graceful Shutdown。"""

import asyncio
import logging
import signal

logger = logging.getLogger(__name__)


async def run_worker() -> None:
    """シグナル受信まで処理ループを回し、受信後に停止する。"""
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    logger.info("ワーカーを起動")
    try:
        while not stop.is_set():
            # 1 件処理して、停止要求があれば次のループで抜ける
            await _process_one()
    finally:
        # タイムアウト付きで後処理を完了させる
        await asyncio.wait_for(_cleanup(), timeout=30.0)
        logger.info("ワーカーを正常に停止しました")


async def _process_one() -> None:
    """キューから 1 件取り出して処理する（実装は省略）。"""


async def _cleanup() -> None:
    """接続クローズなどの後処理を行う（実装は省略）。"""
```

## ミドルウェア

### 基本方針

* **ASGI ミドルウェア / 依存性注入** を使用して横断的関心事を処理する
* **ログ記録、認証、認可、メトリクス収集** などに活用する
* **HTTP ミドルウェア**（ASGI）と **依存関係**（`Depends`）を用途で使い分ける。リクエスト全体に共通する処理はミドルウェア、エンドポイント単位の前提条件は `Depends` に置く

### 実装例

```python
"""リクエストのログ記録ミドルウェア。"""

import logging
import time
from collections.abc import Awaitable, Callable

from starlette.requests import Request
from starlette.responses import Response

logger = logging.getLogger(__name__)


async def logging_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """リクエストの開始・完了・失敗を構造化ログへ記録する。"""
    start = time.perf_counter()
    method = f"{request.method} {request.url.path}"
    logger.info("リクエスト開始", extra={"context": {"method": method}})

    try:
        response = await call_next(request)
    except Exception:
        duration = time.perf_counter() - start
        logger.exception(
            "リクエスト失敗",
            extra={"context": {"method": method, "duration": duration}},
        )
        raise

    duration = time.perf_counter() - start
    logger.info(
        "リクエスト完了",
        extra={
            "context": {
                "method": method,
                "status": response.status_code,
                "duration": duration,
            },
        },
    )
    return response
```

## データストアアクセスパターン

### 基本方針

* **リポジトリパターン** を使用してデータアクセスを抽象化する
* **サードパーティライブラリのクライアントは Protocol で抽象化** する（テスタビリティ向上）
* **DTO（Data Transfer Object）** でドメインモデルとデータストア形式を変換する

### サードパーティクライアントの Protocol 化

サードパーティライブラリ（データベース SDK、ストレージ SDK など）を直接使用せず、必要なメソッドのみを持つ `typing.Protocol` を定義します。`Protocol` は構造的部分型であり、SDK のクライアントが実装を宣言せずともそのまま代入できるため、テストではフェイク実装を渡せます。

#### Protocol 命名規則

サードパーティ SDK のクライアントを抽象化する際は、**SDK のクラス名と同じ名前を使用** し、import alias で名前衝突を回避します。

```python
"""SNS クライアントの Protocol 定義。"""

from typing import Protocol

# import alias を使用して SDK のクラス名との衝突を避ける
from aws_sdk_sns import models as sns_models


class Client(Protocol):
    """SNS クライアントの Protocol。

    AWS SDK のクラス名 (sns.Client) と同じ名前を使用する。
    """

    def create_platform_endpoint(
        self, params: sns_models.CreatePlatformEndpointInput
    ) -> sns_models.CreatePlatformEndpointOutput:
        """プラットフォームエンドポイントを作成する。"""
        ...

    def create_platform_application(
        self, params: sns_models.CreatePlatformApplicationInput
    ) -> sns_models.CreatePlatformApplicationOutput:
        """プラットフォームアプリケーションを作成する。"""
        ...
```

#### 命名規則の比較

| パターン | 例 | 評価 | 理由 |
| --- | --- | --- | --- |
| SDK クラス名と一致 | `sns.Client` | ○ 推奨 | SDK の命名に準拠、直感的 |
| パッケージ名と重複 | `sns.SNSClient` | × 非推奨 | 冗長、lint 警告の対象 |
| 独自命名 | `sns.AwsClient` | × 非推奨 | SDK の命名と不一致 |

### リポジトリ実装（DynamoDB 例）

リポジトリインターフェースは Domain 層に `Protocol` で定義し（依存は内向き）、Infrastructure 層の datasource クラスがそれを構造的に満たします。`Optional[T]` 相当の戻り値は `T | None` で明示します。

```python
"""DynamoDB を使ったユーザーリポジトリ実装。"""

from app.domain.types import UserId
from app.domain.user import User
from app.infrastructure.dynamodb.client import Client
from app.infrastructure.dynamodb.user_item import UserItem


class UserDataSource:
    """User リポジトリの DynamoDB 実装。"""

    def __init__(self, client: Client, table_name: str) -> None:
        """クライアントとテーブル名を受け取る。"""
        self._client = client
        self._table_name = table_name

    async def find_by_id(self, user_id: UserId) -> User | None:
        """ID でユーザーを取得する。存在しなければ None を返す。"""
        result = await self._client.get_item(
            table_name=self._table_name, key={"user_id": user_id.value}
        )
        if result is None:
            return None
        item = UserItem.from_dynamodb(result)
        return item.to_user()
```

### DTO パターン

ドメインモデルとデータストアの形式を変換する DTO を定義します。DTO は値オブジェクトと同様に `@dataclass(frozen=True)` とし、変換メソッドで往復します。

```python
"""DynamoDB アイテム形式の DTO。"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from app.domain.types import UserId
from app.domain.user import User


@dataclass(frozen=True)
class UserItem:
    """データストアのアイテム形式（不変・値等価）。"""

    user_id: str
    display_name: str
    created_at: datetime
    updated_at: datetime
    email: str | None = None

    @classmethod
    def from_dynamodb(cls, raw: dict[str, Any]) -> "UserItem":
        """DynamoDB の生データから DTO を復元する。"""
        ...

    @classmethod
    def from_user(cls, user: User) -> "UserItem":
        """ドメインモデルから DTO へ変換する。"""
        ...

    def to_user(self) -> User:
        """DTO からドメインモデルへ変換する。"""
        ...
```

## PostgreSQL + SQLAlchemy 2.0 パターン

PostgreSQL を使用するリポジトリ実装では、SQLAlchemy 2.0（async）と `importlib.resources` による SQL 外出しパターンを使用します。生 SQL を `text()` で実行する場合も、SQL 文字列はコードに直書きせず `.sql` ファイルへ外出しします。

### エンジン生成関数

`create_engine` 関数で `AsyncEngine` を返します。接続プール設定（`pool_size` など）の決定は呼び出し元（`lifespan` / アプリ起動部）で行います。

```python
"""PostgreSQL エンジンの生成。"""

from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine


def create_engine(dsn: str, *, pool_size: int = 10) -> AsyncEngine:
    """非同期エンジンを生成して返す。

    プールサイズなどの運用パラメータは呼び出し元で決定する。
    """
    return create_async_engine(dsn, pool_size=pool_size)
```

### SQL ファイルの外出し（importlib.resources）

SQL クエリは `sql/` サブパッケージに `.sql` ファイルとして外出しし、`importlib.resources` で読み込みます。SQL をコード内に文字列定数として埋め込まないことで、SQL の可読性・管理性を保ちます。`go:embed` に相当するのが `importlib.resources.files(...).read_text()` です。

```
src/app/infrastructure/postgres/
├── sql/
│   ├── __init__.py
│   ├── find_user_associations.sql          # LIMIT あり
│   └── find_all_user_associations.sql      # LIMIT なし
├── __init__.py
└── user_association_datasource.py
```

```python
"""外出し SQL の読み込みヘルパ。"""

from importlib.resources import files

_SQL = files("app.infrastructure.postgres.sql")

# モジュール読み込み時に一度だけ読み込む（go:embed 相当）
FIND_ALL_QUERY: str = _SQL.joinpath("find_all_user_associations.sql").read_text(
    encoding="utf-8"
)
FIND_QUERY: str = _SQL.joinpath("find_user_associations.sql").read_text(
    encoding="utf-8"
)
```

### datasource パターンと named parameter

datasource パターンでは、単一クラスがリポジトリ（書き込み）とクエリサービス（読み取り）を同時に実装します。フィルター条件には SQLAlchemy の `text()` と named parameter（`:param_name` 形式）を使用します。未指定フィールドは `None` を渡して SQL 側の `IS NULL` チェックに対応させます。トランザクション境界は `async with engine.begin()` で明示します。

```python
"""user_association の datasource（repository + query service）。"""

from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine

from app.domain.types import SourceFilter
from app.domain.user_association import UserAssociation
from app.infrastructure.postgres.dto.user_association import UserAssociationRecords
from app.infrastructure.postgres.sql import FIND_ALL_QUERY


class UserAssociationDataSource:
    """UserAssociation の取得・永続化を担う datasource。"""

    def __init__(self, engine: AsyncEngine) -> None:
        """エンジンを受け取る。"""
        self._engine = engine

    async def find_all(self, filter_: SourceFilter) -> list[UserAssociation]:
        """フィルターに合致する関連を全件取得する。"""
        params: dict[str, Any] = {
            "platform_type": None,
            "sp_uid": None,
            "platform_user_id": None,
        }
        if (platform := filter_.platform) is not None:
            params["platform_type"] = platform.value
        if (sp_uid := filter_.sp_uid) is not None:
            params["sp_uid"] = sp_uid.value
        if (store_id := filter_.store_id) is not None:
            params["platform_user_id"] = store_id.value

        # 読み取りトランザクション境界を明示
        async with self._engine.connect() as conn:
            result = await conn.execute(text(FIND_ALL_QUERY), params)
            records = UserAssociationRecords.of(result.mappings().all())
        return records.aggregate()
```

### LIMIT の扱い: SQL ファイルを分ける

`LIMIT` の有無でクエリが変わる場合は、SQL ファイルを分けます。**Python 側でのスライスカット**（取得後に `rows[:limit]` する後処理）はアンチパターンです。

```sql
-- sql/find_all_user_associations.sql（LIMIT なし）
SELECT sp_uid, platform_user_id, platform_type
FROM user_association
WHERE (:platform_type IS NULL OR platform_type = :platform_type)
  AND (:sp_uid IS NULL OR sp_uid = :sp_uid)
  AND (:platform_user_id IS NULL OR platform_user_id = :platform_user_id)
ORDER BY sp_uid ASC
```

```sql
-- sql/find_user_associations.sql（LIMIT あり）
SELECT sp_uid, platform_user_id, platform_type
FROM user_association
WHERE (:platform_type IS NULL OR platform_type = :platform_type)
  AND (:sp_uid IS NULL OR sp_uid = :sp_uid)
  AND (:platform_user_id IS NULL OR platform_user_id = :platform_user_id)
ORDER BY sp_uid ASC
LIMIT :limit
```

`:limit` も他の named parameter と同じく params dict に渡すだけで実行できます。呼び出し側では `limit` の有無でクエリを切り替えます。

```python
async def find_all(self, filter_: SourceFilter) -> list[UserAssociation]:
    """limit 指定の有無で実行する SQL を切り替える。"""
    if filter_.limit is not None:
        return await self._find_with_limit(filter_)
    return await self._find_all(filter_)
```

### DTO + aggregate パターン（PostgreSQL）

DB の各行を表す `Record`（`@dataclass(frozen=True)`）と、そのコレクションを包む `Records` クラスを定義します。`Records` に `aggregate()` メソッドを持たせ、ドメインモデルリストへの一括変換を担わせます。`_to_model()` は非公開（先頭アンダースコア）とし、`aggregate()` からのみ呼び出します。生成ファクトリは `of`（同等の行データから）に従います。

```python
"""user_association テーブルの読み取り用 DTO。"""

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from app.domain.types import Platform, SpUid, StoreId
from app.domain.user_association import UserAssociation


@dataclass(frozen=True)
class UserAssociationRecord:
    """user_association テーブルの 1 行に対応する読み取り用 DTO。"""

    sp_uid: int
    platform_user_id: str
    platform_type: str

    @classmethod
    def of(cls, row: Mapping[str, Any]) -> "UserAssociationRecord":
        """行マッピングから Record を生成する。"""
        return cls(
            sp_uid=row["sp_uid"],
            platform_user_id=row["platform_user_id"],
            platform_type=row["platform_type"],
        )

    def _to_model(self) -> UserAssociation:
        """非公開。aggregate() からのみ呼び出す。"""
        store_id = StoreId.from_(self.platform_user_id)
        platform = Platform.from_(self.platform_type)
        return UserAssociation.of(SpUid.of(self.sp_uid), store_id, platform)


@dataclass(frozen=True)
class UserAssociationRecords:
    """UserAssociationRecord のコレクション。"""

    records: tuple[UserAssociationRecord, ...]

    @classmethod
    def of(cls, rows: list[Mapping[str, Any]]) -> "UserAssociationRecords":
        """行マッピングのリストからコレクションを生成する。"""
        return cls(tuple(UserAssociationRecord.of(row) for row in rows))

    def aggregate(self) -> list[UserAssociation]:
        """DB レコード群をドメインモデルリストへ変換する。"""
        return [record._to_model() for record in self.records]
```

#### DTO のテスト

`aggregate()` を公開メソッドとして直接テストします。`_to_model()` は非公開のため、`aggregate()` 経由で間接的に検証します。テストはテーブル駆動（`@pytest.mark.parametrize`）とし、`tests/` は `src/` と同一構成に配置します（[テストコード規約](testing.md) 参照）。不正値で `from_` がドメイン例外を送出する経路も網羅します。

```python
"""UserAssociationRecords の変換テスト。"""

import pytest

from app.domain.types import Platform, SpUid, StoreId
from app.domain.user_association import UserAssociation
from app.errors import ValidationError
from app.infrastructure.postgres.dto.user_association import UserAssociationRecords


@pytest.mark.parametrize(
    ("rows", "want"),
    [
        pytest.param(
            [{"sp_uid": 1, "platform_user_id": "token-ios-1", "platform_type": "ios"}],
            [UserAssociation.of(SpUid.of(1), StoreId.from_("token-ios-1"), Platform.from_("ios"))],
            id="ios レコードをドメインモデルに変換できる",
        ),
        pytest.param(
            [],
            [],
            id="空の結果セットは空リストに変換される",
        ),
    ],
)
def test_aggregate(rows: list[dict[str, object]], want: list[UserAssociation]) -> None:
    """行マッピングからドメインモデルへ正しく変換できる。"""
    got = UserAssociationRecords.of(rows).aggregate()
    assert got == want


@pytest.mark.parametrize(
    "rows",
    [
        pytest.param(
            [{"sp_uid": 1, "platform_user_id": "", "platform_type": "ios"}],
            id="platform_user_id が空文字の場合はエラー",
        ),
        pytest.param(
            [{"sp_uid": 1, "platform_user_id": "token-1", "platform_type": "invalid"}],
            id="platform_type が不正な値の場合はエラー",
        ),
    ],
)
def test_aggregate_invalid(rows: list[dict[str, object]]) -> None:
    """不正な行はドメイン例外を送出する。"""
    with pytest.raises(ValidationError):
        UserAssociationRecords.of(rows).aggregate()
```

### Protocol 適合の確認

リポジトリインターフェースは Domain 層の `Protocol` として定義し、datasource クラスがそれを構造的に満たすことを mypy で静的に保証します。明示的に確認したい場合は、型注釈付きの代入で検査できます。

```python
"""SourceRepository Protocol への適合をコンパイル時に保証する。"""

from app.domain.user_association import SourceRepository
from app.infrastructure.postgres.user_association_datasource import (
    UserAssociationDataSource,
)

# mypy が UserAssociationDataSource を SourceRepository とみなせない場合は型エラーになる
_repo_check: SourceRepository = UserAssociationDataSource(engine=...)  # type: ignore[arg-type]  # 適合確認用ダミー
```

実運用では `Protocol` の構造的部分型により、datasource をそのまま `SourceRepository` を要求する箇所へ注入できます。mypy strict 下では未実装メソッドが型エラーとして検出されます。

## asyncpg を使う場合

ORM を介さず生 SQL のみで完結させたい場合は `asyncpg` を直接使用します。プレースホルダは `$1, $2, ...` の位置パラメータです。SQL の外出しと datasource パターンは SQLAlchemy 版と同一の方針を踏襲し、トランザクション境界は `async with conn.transaction()` で明示します。

```python
"""asyncpg を使った datasource の書き込み例。"""

import asyncpg

from app.domain.user_association import UserAssociation
from app.infrastructure.postgres.sql import INSERT_QUERY


class UserAssociationDataSource:
    """asyncpg による UserAssociation datasource。"""

    def __init__(self, pool: asyncpg.Pool) -> None:
        """コネクションプールを受け取る。"""
        self._pool = pool

    async def save(self, association: UserAssociation) -> None:
        """関連を永続化する。トランザクション境界を明示する。"""
        async with self._pool.acquire() as conn, conn.transaction():
            await conn.execute(
                INSERT_QUERY,
                association.sp_uid.value,
                association.store_id.value,
                association.platform.value,
            )
```

## 関連ドキュメント

* [アーキテクチャ設計規約](architecture.md) - レイヤー構成、依存性注入
* [エラーハンドリング規約](error-handling.md) - 例外階層、`raise ... from e` による連鎖
* [テストコード規約](testing.md) - DTO のテスト、フェイク・モック使用
* [ローカル開発環境規約](local-dev.md) - docker-compose、alembic マイグレーション

## 参考資料

* [Python logging](https://docs.python.org/3/library/logging.html)
* [FastAPI Lifespan Events](https://fastapi.tiangolo.com/advanced/events/)
* [SQLAlchemy 2.0 asyncio](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)
* [asyncpg](https://magicstack.github.io/asyncpg/current/)
* [importlib.resources](https://docs.python.org/3/library/importlib.resources.html)
