# HTTPハンドラー・プレゼンテーション層規約

## 概要

FastAPI を用いた HTTPハンドラー（プレゼンテーション層）の実装規約です。OpenAPI 仕様に基づく API 設計と、Google AIP（API Improvement Proposals）を参考にした設計パターンを定めています。FastAPI は型注釈と Pydantic モデルから OpenAPI スキーマを自動生成するため、ハンドラー（path operation function）は薄く保ち、ドメイン・アプリケーション層への委譲に徹します。

## 基本方針

* **OpenAPI 仕様（FastAPI が生成するスキーマ）を API 契約の single source of truth とする**
* **Google AIP ガイドラインを参考にした API 設計**
* **ハンドラーは薄く保ち、ビジネスロジックは usecase / application 層へ委譲する**
* **リクエスト/レスポンス DTO は Pydantic モデルで定義し、ドメイン型との変換ロジックは専用モジュールに分離する**
* **依存性は `Depends` で注入し、ハンドラーは具体実装を直接 import しない**
* **ドメイン例外は専用のハンドラーで `HTTPException` にマッピングし、ハンドラー本体で if 分岐を増やさない**

## ディレクトリ構成

```plaintext
src/app/presentation/
└── http/
    ├── __init__.py
    ├── app.py                    # FastAPI アプリ生成・ルーター登録・例外ハンドラー登録
    ├── dependencies.py           # Depends で注入する usecase / 認証などの provider
    ├── error_handler.py          # ドメイン例外 → HTTPException マッピング
    ├── routers/
    │   ├── __init__.py
    │   └── users.py              # ルーター（path operation function）
    ├── schemas/
    │   ├── __init__.py
    │   ├── user.py               # Pydantic リクエスト/レスポンス DTO
    │   └── error.py              # 共通エラーレスポンス DTO
    └── converters/
        ├── __init__.py
        └── user.py               # DTO ⇄ ドメイン型の変換関数
```

テストは `src/` と同一構成で `tests/app/presentation/http/` 配下に配置します（詳細は [テストコード規約](testing.md) を参照）。

## OpenAPI 設計のベストプラクティス（AIP 推奨）

FastAPI ではルーターの `path` ・型注釈・Pydantic モデルから OpenAPI が生成されます。生成スキーマが AIP に沿うよう、パス・フィールド名・ステータスコードを以下の方針で記述します。

### リソース指向設計（AIP-121, AIP-122）

**基本方針:**

* **リソースは名詞の複数形**（例: `users`, `articles`, `notifications`）
* **リソースIDはパスパラメータ**（例: `/v1/users/{user_id}`）
* **コレクションとリソースの階層構造**

**実装例:**

```python
from fastapi import APIRouter

router = APIRouter(prefix="/v1/users", tags=["users"])


@router.get("", operation_id="listUsers", summary="ユーザー一覧取得")
async def list_users() -> ListUsersResponse: ...


@router.post("", operation_id="createUser", summary="ユーザー作成", status_code=201)
async def create_user() -> UserResponse: ...


@router.get("/{user_id}", operation_id="getUser", summary="ユーザー取得")
async def get_user(user_id: str) -> UserResponse: ...


@router.get(
    "/{user_id}/articles",
    operation_id="listUserArticles",
    summary="ユーザーの記事一覧取得",
)
async def list_user_articles(user_id: str) -> ListArticlesResponse: ...
```

### 標準メソッド（AIP-131-135）

**基本方針:**

* **List（一覧取得）:** `GET /v1/resources`
* **Get（単一取得）:** `GET /v1/resources/{id}`
* **Create（作成）:** `POST /v1/resources`
* **Update（更新）:** `PUT /v1/resources/{id}` または `PATCH /v1/resources/{id}`
* **Delete（削除）:** `DELETE /v1/resources/{id}`

**HTTPステータスコード:**

| メソッド | 成功時 | 説明 |
| --- | --- | --- |
| List | 200 OK | リソース一覧を返す |
| Get | 200 OK | リソースを返す |
| Create | 201 Created | 作成されたリソースを返す |
| Update | 200 OK | 更新されたリソースを返す |
| Delete | 204 No Content | レスポンスボディなし |

FastAPI ではデフォルトのステータスコードが 200 のため、Create は `status_code=201`、Delete は `status_code=204` をデコレーターで明示します。

### カスタムメソッド（AIP-136）

**基本方針:**

* **標準メソッドで表現できない操作はカスタムメソッドを使用**
* **形式:** `POST /v1/resources/{id}:customVerb`
* **動詞は小文字のキャメルケース**

**一般的なカスタムメソッド:**

| 動詞 | 用途 | 例 |
| --- | --- | --- |
| `:cancel` | 処理のキャンセル | `POST /v1/orders/{order_id}:cancel` |
| `:activate` | リソースの有効化 | `POST /v1/users/{user_id}:activate` |
| `:deactivate` | リソースの無効化 | `POST /v1/users/{user_id}:deactivate` |
| `:enable` | 機能の有効化 | `POST /v1/endpoints/{id}:enable` |
| `:disable` | 機能の無効化 | `POST /v1/endpoints/{id}:disable` |
| `:move` | リソースの移動 | `POST /v1/files/{file_id}:move` |
| `:search` | 複雑な検索 | `POST /v1/articles:search` |
| `:batch` | バッチ処理 | `POST /v1/users:batchGet` |

**実装例:**

コロンを含むパスは FastAPI でもそのまま記述できます。ハンドラーは DTO → ドメイン型の変換と usecase 呼び出しに徹し、例外はマッピング層に委譲します。

```python
@router.post("/{endpoint_id}:enable", operation_id="enableEndpoint", summary="エンドポイントを有効化")
async def enable_endpoint(
    endpoint_id: str,
    body: EnableEndpointRequest,
    usecase: Annotated[EndpointUsecase, Depends(provide_endpoint_usecase)],
) -> EndpointResponse:
    """エンドポイントを有効化する。

    Args:
        endpoint_id: 有効化対象のエンドポイント ID。
        body: 有効化リクエスト DTO。
        usecase: 注入されるエンドポイントユースケース。

    Returns:
        有効化されたエンドポイントのレスポンス DTO。
    """
    parsed_id = to_endpoint_id(endpoint_id)
    endpoint_type = to_endpoint_type(body.type)
    endpoint = await usecase.enable(parsed_id, endpoint_type)
    return to_endpoint_response(endpoint)
```

無効な ID や種別は `to_endpoint_id` / `to_endpoint_type` がドメイン例外を送出し、例外ハンドラーが 400 に変換します（後述）。ハンドラー内で `raise HTTPException(...)` を直接書かないことで、ハンドラーを薄く保ちます。

### フィールド命名規則（AIP-140, AIP-142）

**基本方針:**

* **API のフィールド名は小文字のスネークケース**（例: `user_id`, `created_at`, `display_name`）
* **時刻フィールドは** `*_time` または `*_at` サフィックス（例: `create_time`, `created_at`）
* **ブール値は** `is_*`, `has_*`, `can_*` プレフィックス（例: `is_active`, `has_permission`）
* **列挙型（enum）は小文字のスネークケース**（例: `regular`, `premium`, `ios`, `android`）

Python の属性名も PEP 8 のスネークケースであるため、Pydantic モデルの属性名がそのまま JSON のフィールド名になります。エイリアス変換は不要です。

**実装例（schemas/user.py）:**

```python
from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, EmailStr, Field


class UserType(StrEnum):
    """API 上のユーザー種別。"""

    REGULAR = "regular"
    PREMIUM = "premium"
    TRIAL = "trial"


class UserResponse(BaseModel):
    """ユーザーのレスポンス DTO。"""

    user_id: str = Field(description="ユーザーID")
    email: EmailStr | None = Field(default=None, description="メールアドレス")
    display_name: str = Field(description="表示名")
    is_active: bool = Field(description="有効かどうか")
    user_type: UserType = Field(description="ユーザー種別")
    created_at: datetime = Field(description="作成日時")
    updated_at: datetime = Field(description="更新日時")
```

### ページネーション（AIP-158）

**基本方針:**

* **ページネーションには** `page_size` と `page_token` を使用
* **レスポンスには** `next_page_token` を含める
* **最大ページサイズを定義**（例: 100件）

クエリパラメータの制約は FastAPI の `Query` で表現し、OpenAPI の `minimum` / `maximum` / `default` に反映させます。

**実装例:**

```python
from typing import Annotated

from fastapi import Query


class ListUsersResponse(BaseModel):
    """ユーザー一覧のレスポンス DTO。"""

    users: list[UserResponse] = Field(description="ユーザー一覧")
    next_page_token: str | None = Field(
        default=None,
        description="次のページのトークン（最終ページの場合は None）",
    )


@router.get("", operation_id="listUsers", summary="ユーザー一覧取得")
async def list_users(
    usecase: Annotated[UserUsecase, Depends(provide_user_usecase)],
    page_size: Annotated[int, Query(ge=1, le=100, description="1ページあたりの件数")] = 25,
    page_token: Annotated[str | None, Query(description="ページネーショントークン")] = None,
) -> ListUsersResponse:
    """ユーザー一覧をページネーション付きで取得する。

    Args:
        usecase: 注入されるユーザーユースケース。
        page_size: 1 ページあたりの件数（1〜100、既定 25）。
        page_token: 前回レスポンスの next_page_token。先頭ページでは None。

    Returns:
        ユーザー一覧と次ページトークンを含むレスポンス DTO。
    """
    page = await usecase.list_users(page_size=page_size, page_token=page_token)
    return to_list_users_response(page)
```

### エラーレスポンス（AIP-193 参考）

**基本方針:**

* **エラーレスポンスは統一されたスキーマを使用**
* **エラーコードとメッセージを含める**
* **詳細情報が必要な場合は** `details` フィールドを使用

**実装例（schemas/error.py）:**

```python
from pydantic import BaseModel, Field


class ErrorDetail(BaseModel):
    """エラー詳細の 1 要素。"""

    field: str = Field(description="エラーが発生したフィールド")
    reason: str = Field(description="エラー理由")


class ErrorResponse(BaseModel):
    """統一エラーレスポンス DTO。"""

    code: str = Field(description="エラーコード", examples=["VALIDATION_ERROR"])
    message: str = Field(description="エラーメッセージ", examples=["無効な入力値です"])
    details: list[ErrorDetail] | None = Field(
        default=None,
        description="エラー詳細（オプション）",
    )
```

エラーレスポンスを OpenAPI に反映させるため、ルーターの `responses` 引数でステータスコードごとに `ErrorResponse` を登録します。

```python
@router.get(
    "/{user_id}",
    operation_id="getUser",
    summary="ユーザー取得",
    responses={
        404: {"model": ErrorResponse, "description": "リソースが見つからない"},
        400: {"model": ErrorResponse, "description": "リクエストが不正"},
    },
)
async def get_user(...) -> UserResponse: ...
```

## ハンドラーと依存性注入

### 基本方針

* **ハンドラーは「DTO → ドメイン型変換」「usecase 呼び出し」「ドメイン型 → DTO 変換」の 3 ステップに収める**
* **usecase・リポジトリ・認証情報は `Depends` で注入し、ハンドラーは具体実装を import しない**
* **provider 関数は `dependencies.py` に集約する**

ドメイン層のリポジトリは `typing.Protocol` で定義し、依存方向を内向きに保ちます（[アーキテクチャ設計規約](architecture.md) を参照）。`dependencies.py` の provider が具体実装を組み立て、ハンドラーには抽象だけを渡します。

### 実装例（dependencies.py）

```python
from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.user_usecase import UserUsecase
from app.infrastructure.datasource.user import UserDatasource
from app.presentation.http.db import provide_session


def provide_user_usecase(
    session: Annotated[AsyncSession, Depends(provide_session)],
) -> UserUsecase:
    """UserUsecase を組み立てて返す provider。

    Args:
        session: リクエストスコープの DB セッション。

    Returns:
        リポジトリを注入済みの UserUsecase。
    """
    datasource = UserDatasource(session)
    return UserUsecase(user_repository=datasource)
```

### 実装例（routers/users.py）

```python
from typing import Annotated

from fastapi import APIRouter, Depends

from app.application.user_usecase import UserUsecase
from app.presentation.http.converters.user import to_user_id, to_user_response
from app.presentation.http.dependencies import provide_user_usecase
from app.presentation.http.schemas.user import UserResponse

router = APIRouter(prefix="/v1/users", tags=["users"])


@router.get("/{user_id}", operation_id="getUser", summary="ユーザー取得")
async def get_user(
    user_id: str,
    usecase: Annotated[UserUsecase, Depends(provide_user_usecase)],
) -> UserResponse:
    """ユーザーを取得する。

    Args:
        user_id: 取得対象のユーザー ID。
        usecase: 注入されるユーザーユースケース。

    Returns:
        ユーザーのレスポンス DTO。

    Raises:
        UserNotFoundError: 該当ユーザーが存在しない場合（例外ハンドラーが 404 に変換）。
    """
    parsed_id = to_user_id(user_id)
    user = await usecase.get_user(parsed_id)
    return to_user_response(user)
```

usecase が `UserNotFoundError` を送出した場合、ハンドラーでは捕捉せず、登録済みの例外ハンドラーが 404 に変換します。これによりハンドラー本体に存在チェックの分岐が混入しません。

## リクエスト/レスポンス変換パターン

### 基本方針

* **変換ロジックは** `converters/` 配下のモジュールに集約する
* **`to_*` は DTO・プリミティブ → ドメイン型、`to_*_response` はドメイン型 → DTO** という命名で方向を表す
* **変換関数は public（モジュール先頭が小文字でないこと自体は Python では不問だが、命名で意図を示す）。テスト容易性のため副作用を持たせない**
* **DTO ⇄ ドメイン型の双方向変換を 1 箇所にまとめ、ハンドラー・テストから再利用する**

`types` パッケージで値オブジェクト・DTO を統一管理する方針に従い、ID やメールアドレスなどの値オブジェクトはファクトリ classmethod（`of` / `from_`）で生成します。NULL 許容値は `T | None` を明示します（[ドメインモデル規約](domain-model.md) / [型システム規約](type-system.md) を参照）。

### 実装例（converters/user.py）

```python
from app.domain.model.user import User
from app.domain.types.email import Email
from app.domain.types.user_id import UserId
from app.domain.types.user_type import UserType as DomainUserType
from app.presentation.http.schemas.user import UserResponse, UserType


def to_user_id(raw: str) -> UserId:
    """文字列をユーザー ID 値オブジェクトに変換する。

    Args:
        raw: パスパラメータから受け取った ID 文字列。

    Returns:
        検証済みの UserId。

    Raises:
        ValidationError: ID 形式が不正な場合。
    """
    return UserId.of(raw)


def to_email(raw: str | None) -> Email | None:
    """オプショナルなメールアドレス文字列を値オブジェクトに変換する。

    Args:
        raw: メールアドレス文字列。None の場合は変換しない。

    Returns:
        Email 値オブジェクト。入力が None の場合は None。
    """
    if raw is None:
        return None
    return Email.of(raw)


def to_user_type(api_type: UserType) -> DomainUserType:
    """API のユーザー種別をドメイン型に変換する。

    Args:
        api_type: API 上の UserType。

    Returns:
        対応するドメインの UserType。
    """
    return DomainUserType(api_type.value)


def to_user_response(user: User) -> UserResponse:
    """ドメインモデルをレスポンス DTO に変換する。

    Args:
        user: ドメインのユーザーエンティティ。

    Returns:
        ユーザーのレスポンス DTO。
    """
    email = user.email
    return UserResponse(
        user_id=str(user.user_id),
        email=str(email) if email is not None else None,
        display_name=user.display_name,
        is_active=user.is_active,
        user_type=UserType(user.user_type.value),
        created_at=user.created_at,
        updated_at=user.updated_at,
    )
```

Go 版では `ptr` ヘルパーや `Optional[T]` の変換が必要でしたが、Python では `T | None` をそのまま扱えるため、変換は値の有無で分岐するだけです。`Any` を使った汎用ヘルパーは導入しません。

## バリデーションとエラーレスポンス

### 基本方針

* **入力バリデーションは Pydantic と `Query` / `Path` の制約に任せる。FastAPI は不正入力を自動で 422 に変換する**
* **ドメイン由来のエラーは独自例外階層で表現し、例外ハンドラーで HTTP ステータスにマッピングする**
* **ハンドラー内で `raise HTTPException(...)` を直接書かない**（マッピングを 1 箇所に集約するため）

**ステータスコードの対応:**

* **入力スキーマ違反は 422 Unprocessable Entity**（FastAPI 既定）
* **ドメインのバリデーションエラーは 400 Bad Request**
* **認証エラーは 401 Unauthorized**
* **認可エラーは 403 Forbidden**
* **リソース未発見は 404 Not Found**
* **未捕捉の例外は 500 Internal Server Error**（ログに記録）

ドメイン例外は基底 `AppError` から派生させ、`raise X from e` で連鎖させます。bare `Exception` を直接 raise / except しません（[エラーハンドリング規約](error-handling.md) を参照）。

### 実装例（error_handler.py）

```python
import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.errors import (
    AuthorizationError,
    NotFoundError,
    ValidationError,
)
from app.presentation.http.schemas.error import ErrorResponse

logger = logging.getLogger(__name__)


def register_error_handlers(app: FastAPI) -> None:
    """ドメイン例外を HTTP レスポンスにマッピングするハンドラーを登録する。

    Args:
        app: 例外ハンドラーを登録する FastAPI アプリ。
    """

    @app.exception_handler(ValidationError)
    async def _handle_validation(
        _request: Request,
        exc: ValidationError,
    ) -> JSONResponse:
        body = ErrorResponse(code="VALIDATION_ERROR", message=str(exc))
        return JSONResponse(status_code=400, content=body.model_dump())

    @app.exception_handler(NotFoundError)
    async def _handle_not_found(
        _request: Request,
        exc: NotFoundError,
    ) -> JSONResponse:
        body = ErrorResponse(code="NOT_FOUND", message=str(exc))
        return JSONResponse(status_code=404, content=body.model_dump())

    @app.exception_handler(AuthorizationError)
    async def _handle_authorization(
        _request: Request,
        exc: AuthorizationError,
    ) -> JSONResponse:
        body = ErrorResponse(code="FORBIDDEN", message=str(exc))
        return JSONResponse(status_code=403, content=body.model_dump())

    @app.exception_handler(Exception)
    async def _handle_unexpected(
        _request: Request,
        exc: Exception,
    ) -> JSONResponse:
        # 未捕捉の例外はスタックトレースをログに記録してから 500 を返す
        logger.exception("予期しないエラーが発生しました", exc_info=exc)
        body = ErrorResponse(code="INTERNAL_ERROR", message="内部エラーが発生しました")
        return JSONResponse(status_code=500, content=body.model_dump())
```

### アプリ生成（app.py）

ルーターと例外ハンドラーの登録を 1 箇所に集約し、ハンドラーがマッピングを意識せずに済むようにします。

```python
from fastapi import FastAPI

from app.presentation.http.error_handler import register_error_handlers
from app.presentation.http.routers import users


def create_app() -> FastAPI:
    """FastAPI アプリを生成し、ルーターと例外ハンドラーを登録する。

    Returns:
        設定済みの FastAPI アプリ。
    """
    app = FastAPI(title="App API", version="1.0.0")
    app.include_router(users.router)
    register_error_handlers(app)
    return app
```

### 作成系ハンドラーの例

```python
@router.post("", operation_id="createUser", summary="ユーザー作成", status_code=201)
async def create_user(
    body: CreateUserRequest,
    usecase: Annotated[UserUsecase, Depends(provide_user_usecase)],
) -> UserResponse:
    """ユーザーを作成する。

    Args:
        body: ユーザー作成リクエスト DTO。
        usecase: 注入されるユーザーユースケース。

    Returns:
        作成されたユーザーのレスポンス DTO。

    Raises:
        ValidationError: 種別などのドメイン制約に違反した場合（400 に変換）。
    """
    user_type = to_user_type(body.user_type)
    email = to_email(body.email)
    user = await usecase.create_user(
        display_name=body.display_name,
        email=email,
        user_type=user_type,
    )
    return to_user_response(user)
```

リクエストボディの必須/型チェックは `CreateUserRequest`（Pydantic）が担い、欠落・型不一致は自動的に 422 になります。ドメイン制約（種別の妥当性など）に違反した場合のみ usecase / 変換層が `ValidationError` を送出し、400 に変換されます。

## 関連ドキュメント

* [アーキテクチャ設計規約](architecture.md) - レイヤー構成・依存方向
* [ドメインモデル規約](domain-model.md) - 値オブジェクト・ファクトリ classmethod
* [型システム規約](type-system.md) - 型注釈方針・`T | None`
* [エラーハンドリング規約](error-handling.md) - 独自例外階層・例外連鎖
* [テストコード規約](testing.md) - ハンドラー・変換関数のテスト
* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成・src レイアウト

## 参考資料

* [Google API Improvement Proposals (AIP)](https://google.aip.dev/)
* [AIP-121: Resource-oriented design](https://google.aip.dev/121)
* [AIP-122: Resource names](https://google.aip.dev/122)
* [AIP-131-135: Standard methods](https://google.aip.dev/131)
* [AIP-136: Custom methods](https://google.aip.dev/136)
* [AIP-140: Field names](https://google.aip.dev/140)
* [AIP-158: Pagination](https://google.aip.dev/158)
* [AIP-193: Errors](https://google.aip.dev/193)
* [FastAPI 公式ドキュメント](https://fastapi.tiangolo.com/)
* [FastAPI - Dependencies](https://fastapi.tiangolo.com/tutorial/dependencies/)
* [FastAPI - Handling Errors](https://fastapi.tiangolo.com/tutorial/handling-errors/)
* [Pydantic 公式ドキュメント](https://docs.pydantic.dev/)
