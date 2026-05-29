# プロジェクト構成規約

## 概要

プロジェクト構成とビルドツールの規約です。Makefile の自己文書化パターンや src レイアウトの標準化により、開発者がプロジェクトをすぐに理解できるようにします。パッケージ・依存管理は uv + `pyproject.toml`（PEP 621）に統一します。

## Makefile 自己文書化

### 基本方針

* **Makefile にヘルプ機能** を提供する
* **各ターゲットにコメント（** `##` ）で説明 を追加する
* `make` または `make help` で使用可能なコマンド一覧を表示する
* **ターゲット名は** `カテゴリ/アクション` 形式 を使用する（例: `code/lint`, `image/build`）
* `.PHONY` は動的に自動生成する
* **タスクは uv 経由で実行** する（ `uv run` で同一環境を保証する）

### 実装例

```makefile
.PHONY: $(shell egrep -o ^[a-zA-Z_/.-]+: $(MAKEFILE_LIST) | sed 's/://')
SHELL=/bin/bash

help: ## ヘルプを表示する
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z].+:.*?## / {printf "\\033[36m%-30s\\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

code/lint: ## コードを静的解析する
	@uv run ruff check .
	@uv run mypy src

code/test: ## コードをテストする
	@uv run pytest

code/fmt: ## コードのフォーマットを整える
	@uv run ruff format .
	@uv run ruff check --fix .

db/migrate: ## マイグレーションを適用する
	@uv run alembic upgrade head

image/build: ## Dockerイメージをビルドする
	@docker build -t app:latest --platform=linux/amd64 .

install: ## 依存関係をインストールする
	@uv sync --all-extras
```

### 使用例

```shell
$ make
Usage: make [target]

Targets:
code/fmt                       コードのフォーマットを整える
code/lint                      コードを静的解析する
code/test                      コードをテストする
db/migrate                     マイグレーションを適用する
help                           ヘルプを表示する
image/build                    Dockerイメージをビルドする
install                        依存関係をインストールする
```

### ポイント

* **自動 PHONY 宣言**: `egrep` で全ターゲットを抽出して `.PHONY` に設定
* **カラー表示**: ANSI カラーコード（ `\\033[36m]` ）で見やすく
* **30文字幅で整形**: AWK の `printf` で左詰め表示
* **uv run の活用**: `uv run ruff`, `uv run mypy`, `uv run pytest` など同一の仮想環境で実行

## プロジェクト構造

### 基本方針

* **src レイアウトを採用** する（パッケージは `src/<package>/` 以下に配置し、インストールされた状態でのみ import できるようにする）
* **各サブパッケージに** `__init__.py` を配置 し、必要に応じて公開 API（ `__all__` ）とパッケージの目的を docstring で説明する（**必須**）
* **エントリポイントは** `pyproject.toml` の `[project.scripts]` で公開 する（`__main__.py` を併用する）
* **依存関係の方向を明確** にする（上位層→下位層、依存は内向き）

### ディレクトリ構成例

```plaintext
app/
├── src/
│   └── app/
│       ├── __init__.py
│       ├── __main__.py               # エントリポイント（python -m app）
│       ├── domain/                   # ドメイン層
│       │   ├── __init__.py
│       │   ├── model/                # エンティティと集約ルート
│       │   │   ├── __init__.py
│       │   │   ├── user.py
│       │   │   └── user_repository.py    # リポジトリインターフェース（Protocol）
│       │   ├── types/                # 値オブジェクト
│       │   │   ├── __init__.py
│       │   │   ├── user_id.py
│       │   │   └── email.py
│       │   └── errors.py             # ドメイン例外階層
│       ├── application/              # アプリケーション層
│       │   ├── __init__.py
│       │   ├── usecase/              # ユースケース実装
│       │   │   ├── __init__.py
│       │   │   └── user_usecase.py
│       │   ├── queryservice/         # クエリサービスインターフェース（Protocol）
│       │   │   ├── __init__.py
│       │   │   └── user_query_service.py
│       │   └── types/                # アプリケーション層固有の型（クエリサービス用DTO・ユースケース固有型等）
│       │       ├── __init__.py
│       │       └── user_dto.py
│       ├── infrastructure/           # インフラストラクチャ層
│       │   ├── __init__.py
│       │   ├── postgres/             # PostgreSQL 実装
│       │   │   ├── __init__.py
│       │   │   ├── user_datasource.py
│       │   │   └── sql/              # 外出しした SQL（importlib.resources で読み込む）
│       │   │       └── find_user_by_id.sql
│       │   ├── dynamodb/             # DynamoDB 実装
│       │   │   ├── __init__.py
│       │   │   └── client.py
│       │   ├── s3/                   # S3 実装
│       │   │   ├── __init__.py
│       │   │   └── uploader.py
│       │   ├── redis/                # Redis 実装
│       │   │   ├── __init__.py
│       │   │   └── cache.py
│       │   └── httpcli/              # HTTP クライアント（必要に応じて追加）
│       │       ├── __init__.py
│       │       └── client.py
│       └── presentation/            # プレゼンテーション層
│           ├── __init__.py
│           ├── api/                 # FastAPI ルーター
│           │   ├── __init__.py
│           │   ├── user_router.py       # ルーター実装
│           │   ├── request.py           # リクエスト→ドメイン型変換
│           │   ├── response.py          # ドメイン型→レスポンス変換
│           │   ├── dependencies.py      # Depends による DI
│           │   ├── exception_handlers.py # 例外→HTTP マッピング
│           │   └── middleware/          # ミドルウェア
│           │       ├── __init__.py
│           │       ├── auth_middleware.py
│           │       └── request_log_middleware.py
│           └── cli/                 # CLI コマンド
│               ├── __init__.py
│               └── root.py
├── tests/                            # テスト（src と同一構成）
│   ├── __init__.py
│   ├── conftest.py
│   ├── domain/
│   │   └── model/
│   │       └── test_user.py
│   ├── application/
│   │   └── usecase/
│   │       └── test_user_usecase.py
│   ├── infrastructure/
│   │   └── postgres/
│   │       └── test_user_datasource.py
│   └── presentation/
│       └── api/
│           ├── test_user_router.py
│           ├── test_request.py
│           └── test_response.py
├── migrations/                       # alembic マイグレーション
│   ├── env.py
│   └── versions/
│       └── 0001_create_users.py
├── Makefile                          # ビルドタスク
├── Dockerfile                        # Docker イメージ定義
├── compose.yml                       # ローカル開発環境
├── pyproject.toml                    # プロジェクト定義（PEP 621）・ツール設定
├── uv.lock                           # uv ロックファイル
├── .pre-commit-config.yaml           # pre-commit フック設定
└── README.md                         # プロジェクト概要
```

### src レイアウトの理由

* **テストが配布物を import する**: `src/` 以下に置くことで、テストはインストール済みパッケージを import する。リポジトリルートからの暗黙の import が混入せず、`pyproject.toml` のパッケージ設定漏れを早期に検出できる
* **import の曖昧さ排除**: カレントディレクトリが `sys.path` に入る挙動による「ローカルでは通るが配布物では通らない」事故を防ぐ
* **層ごとのパッケージ分割**: `domain` / `application` / `infrastructure` / `presentation` をサブパッケージとして分離し、依存方向を内向きに固定する（アーキテクチャ規約を参照）

### `__init__.py` と公開 API

* 各サブパッケージの `__init__.py` には docstring でパッケージの目的を記述する（**必須**）
* 公開する型・関数のみ `__all__` に列挙し、内部実装は公開しない
* 再 export による循環 import を避けるため、`__init__.py` での重い import は最小限に留める

```python
"""ユーザードメインのエンティティと集約ルートを提供する。"""

from app.domain.model.user import User
from app.domain.model.user_repository import UserRepository

__all__ = ["User", "UserRepository"]
```

### types パッケージの配置

* **値オブジェクト・DTO は専用の** `types` パッケージに集約 する。ドメイン層の値オブジェクトは `domain/types/`、アプリケーション層固有の DTO は `application/types/` に分離する
* 値オブジェクトは `@dataclass(frozen=True)` で定義し、不変条件は `__post_init__` で検証する（ドメインモデル規約を参照）
* NULL 許容値は `T | None` を明示し、暗黙の `None` 伝播を避ける（独自の `Optional[T]` 型は定義しない）

```python
"""ユーザー識別子を表す値オブジェクト。"""

from dataclasses import dataclass
from uuid import UUID, uuid4


@dataclass(frozen=True)
class UserId:
    """ユーザーを一意に識別する値オブジェクト。"""

    value: UUID

    @classmethod
    def new(cls) -> "UserId":
        """新しいユーザー識別子を生成する。"""
        return cls(value=uuid4())

    @classmethod
    def of(cls, raw: str) -> "UserId":
        """文字列表現から識別子を復元する。"""
        return cls(value=UUID(raw))

    def __str__(self) -> str:
        return str(self.value)
```

## プレゼンテーション層の構成

プレゼンテーション層（ `presentation/` ）は、外部からのリクエストを受け付け、アプリケーション層のユースケースに委譲して、適切なレスポンスを返す役割を担います。Web では FastAPI を採用し、ルーターは薄く保ちます。

### ディレクトリ構造

```plaintext
presentation/
├── __init__.py
├── api/                       # FastAPI ルーター
│   ├── __init__.py
│   ├── user_router.py         # ルーター実装（薄く usecase へ委譲）
│   ├── request.py             # リクエストDTO→ドメイン型変換
│   ├── response.py            # ドメイン型→レスポンスDTO変換
│   ├── dependencies.py        # Depends による DI
│   ├── exception_handlers.py  # 例外→HTTP マッピング
│   └── middleware/            # ミドルウェア
│       ├── __init__.py
│       ├── auth_middleware.py
│       └── request_log_middleware.py
└── cli/                       # CLI コマンド
    ├── __init__.py
    └── root.py
```

### ファイルの役割

| ファイル | 役割 | 責務 |
| --- | --- | --- |
| `*_router.py` | ルーター実装 | リクエストの受付、ユースケースの呼び出し、レスポンスの返却 |
| `request.py` | リクエスト変換 | Pydantic リクエストDTO → ドメイン型への変換ロジック |
| `response.py` | レスポンス変換 | ドメイン型 → Pydantic レスポンスDTO への変換ロジック |
| `dependencies.py` | DI 定義 | `Depends` で注入するユースケース・リポジトリの組み立て |
| `exception_handlers.py` | 例外マッピング | ドメイン例外 → HTTP ステータス・エラーレスポンスへの変換 |

> **Note:** リクエスト・レスポンスの DTO は Pydantic モデルで定義し、ドメイン型とは明確に分離します。ルーター内にビジネスロジックを書かず、変換ロジックは `request.py` / `response.py` に隔離します。

### 設計のポイント

* **変換ロジックの分離**: リクエスト変換とレスポンス変換を別ファイルに分離し、ルーターの責務（受付・委譲・返却）を明確にする
* **ドメイン駆動**: API スキーマ型ではなくドメイン型を中心にビジネスロジックを記述する
* **薄いハンドラ**: ルーターはユースケースを呼び出すだけに留め、分岐・検証はユースケース／ドメイン層へ寄せる
* **例外マッピングの集約**: ドメイン例外を `exception_handlers.py` に集約し、ルーターで `try/except` を散らさない（エラーハンドリング規約を参照）
* **テスト容易性**: 変換ロジックを独立した関数に分離することで、ルーターを介さない単体テストが書きやすくなる

### 実装例

**user_router.py（ルーター）**

```python
"""ユーザーリソースの HTTP ルーター。"""

from fastapi import APIRouter, Depends, HTTPException, status

from app.application.usecase.user_usecase import UserUsecase
from app.presentation.api.dependencies import get_user_usecase
from app.presentation.api.request import to_user_id
from app.presentation.api.response import UserResponse, to_user_response

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    usecase: UserUsecase = Depends(get_user_usecase),
) -> UserResponse:
    """ユーザーを 1 件取得する。

    Args:
        user_id: 取得対象のユーザー識別子。
        usecase: 注入されたユーザーユースケース。

    Returns:
        ユーザー情報を表すレスポンス DTO。

    Raises:
        HTTPException: ユーザーが存在しない場合（404）。
    """
    # リクエストからドメイン型へ変換し、ユースケースへ委譲する
    user = await usecase.get_user(to_user_id(user_id))
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="ユーザーが見つかりません",
        )
    # ドメイン型からレスポンス DTO へ変換する
    return to_user_response(user)
```

**request.py（リクエスト変換）**

```python
"""HTTP リクエストからドメイン型への変換。"""

from app.domain.types.email import Email
from app.domain.types.user_id import UserId


def to_user_id(raw: str) -> UserId:
    """文字列を UserId に変換する。"""
    return UserId.of(raw)


def to_email(raw: str) -> Email:
    """文字列を Email に変換する。"""
    return Email.of(raw)
```

**response.py（レスポンス変換）**

```python
"""ドメイン型から HTTP レスポンス DTO への変換。"""

from pydantic import BaseModel

from app.domain.model.user import User


class UserResponse(BaseModel):
    """ユーザー情報を表すレスポンス DTO。"""

    user_id: str
    name: str
    email: str | None = None


def to_user_response(user: User) -> UserResponse:
    """ドメインモデルをレスポンス DTO に変換する。"""
    email = user.email
    return UserResponse(
        user_id=str(user.user_id),
        name=user.display_name,
        email=str(email) if email is not None else None,
    )
```

**dependencies.py（DI 定義）**

```python
"""FastAPI の Depends で注入する依存の組み立て。"""

from app.application.usecase.user_usecase import UserUsecase
from app.infrastructure.postgres.user_datasource import UserDatasource


def get_user_usecase() -> UserUsecase:
    """ユーザーユースケースを組み立てて返す。"""
    repository = UserDatasource()
    return UserUsecase(repository=repository)
```

## README の構成

### 基本方針

各プロジェクトには `README.md` を配置し、以下の情報を含めます：

* プロジェクトの概要
* 技術スタック
* ローカル開発環境のセットアップ手順（ローカル開発環境規約を参照）

### テンプレート例

```plaintext
# プロジェクト名

## 概要

このプロジェクトの目的と機能を簡潔に説明します。

## 技術スタック

- Python 3.13+
- uv（パッケージ・依存管理）
- FastAPI
- PostgreSQL 15 / SQLAlchemy 2.0
- Docker / Docker Compose

## ローカル開発環境

ローカル開発環境のセットアップと開発コマンドについては、
ローカル開発環境規約を参照してください。

### クイックスタート

1. リポジトリをクローン
   git clone https://example.com/app.git
   cd app

2. 依存をインストールして起動
   uv sync --all-extras
   docker compose up -d
   uv run uvicorn app.main:create_app --factory --reload
```

## pyproject.toml の管理

### 基本方針

* **プロジェクトメタデータと依存は** `pyproject.toml`（PEP 621） で管理 する
* **依存・仮想環境は uv で管理** し、ロックは `uv.lock` にコミットする
* **バージョンは可能な限り最新の安定版** を使用する
* **不要な依存関係は定期的に削除** する（ `uv remove` ）
* **ruff / mypy / pytest の設定も** `pyproject.toml` に集約 する

### pyproject.toml の例

```toml
[project]
name = "app"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = [
    "fastapi>=0.115",
    "pydantic>=2.9",
    "sqlalchemy>=2.0",
    "alembic>=1.14",
]

[project.scripts]
app = "app.__main__:main"

[dependency-groups]
dev = [
    "ruff>=0.8",
    "mypy>=1.13",
    "pytest>=8.3",
    "pytest-asyncio>=0.24",
    "pre-commit>=4.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/app"]

[tool.ruff]
src = ["src", "tests"]

# 以下は抜粋。ruff / mypy の完全な設定は linter.md を single source of truth とする。
[tool.ruff.lint]
select = ["E", "W", "F", "I", "N", "UP", "B", "BLE", "TRY", "ANN", "D", "RUF"]

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.mypy]
strict = true
mypy_path = "src"

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
```

### 依存関係の更新

```shell
# 依存を追加（dev グループへの追加は --dev）
uv add fastapi
uv add --dev pytest

# 依存を最新へ更新してロックを再生成
uv lock --upgrade

# ロックに従って環境を同期
uv sync --all-extras
```

## 関連ドキュメント

* [ローカル開発環境規約](local-dev.md) - uv・pre-commit・Docker Compose によるホットリロード開発環境、alembic マイグレーション、開発コマンド
* [テストコード規約](testing.md) - pytest によるテストの構造化、`@pytest.mark.parametrize` によるテーブル駆動、モックの使用方法
* [HTTPハンドラー・プレゼンテーション層規約](http-handler.md) - FastAPI ルーターの実装パターン、リクエスト/レスポンス変換、Depends による DI

## 参考資料

* [Python Packaging User Guide - src layout](https://packaging.python.org/en/latest/discussions/src-layout-vs-flat-layout/)
* [PEP 621 - Storing project metadata in pyproject.toml](https://peps.python.org/pep-0621/)
* [uv Documentation](https://docs.astral.sh/uv/)
* [Makefile Tutorial](https://makefiletutorial.com/)
