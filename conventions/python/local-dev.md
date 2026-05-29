# ローカル開発環境規約

## 概要

ローカル開発環境の構築と運用に関する規約です。Docker Compose の watch 機能を活用したホットリロード開発環境を標準とし、パッケージ・依存管理は uv（`pyproject.toml` / `uv.lock`）に統一します。コード品質は pre-commit（ruff / mypy / pytest）で守り、スキーマ変更は alembic マイグレーションで管理します。

## 基本方針

* **Docker Compose + watch で開発環境を構築** する
* **ファイル変更時に自動でコンテナを同期・再起動** する（ホットリロード）
* **依存・仮想環境は uv で管理** する（`uv sync` で `uv.lock` に従い再現性を保証）
* **開発用ツール（ruff / mypy / pytest / alembic 等）は** `pyproject.toml` の `[dependency-groups]` で管理する（`uv run` で同一環境を保証）
* **コミット前検証は pre-commit** に集約する（ruff / mypy / pytest）
* **ポートはローカルホストにバインド** して外部からのアクセスを防ぐ

## Dockerfile の構成

マルチステージビルドを使用し、依存解決ステージ・開発ステージ・ランタイムステージを分離します。uv の公式 distroless イメージから `uv` バイナリをコピーし、`uv sync` でレイヤキャッシュを効かせます。

```dockerfile
# uv バイナリの取得元（公式 distroless イメージ）
FROM ghcr.io/astral-sh/uv:0.5 AS uv

# ベースステージ: 依存解決
FROM python:3.13-slim AS builder

# uv をコピー
COPY --from=uv /uv /uvx /usr/local/bin/

# 作業ディレクトリを設定
WORKDIR /workspace

# バイトコードを事前コンパイルし、コピーモードでリンクする
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# 依存定義のみを先にコピーして sync（ソース変更でレイヤを壊さない）
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

# ソースコードをコピーしてプロジェクト本体を install
COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# 開発ステージ: docker compose watch の target に指定する
FROM builder AS dev
# dev グループ（ruff / mypy / pytest 等）も同期する
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen
# ローカル開発時はリロード付きで起動
CMD ["uv", "run", "uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--reload"]

# ランタイムステージ: dev 依存を含まない最小構成
FROM python:3.13-slim AS runtime

# builder で作成した仮想環境をコピー
COPY --from=builder /workspace/.venv /workspace/.venv

# venv の実行ファイルを PATH に通す
ENV PATH="/workspace/.venv/bin:$PATH"

WORKDIR /workspace
COPY --from=builder /workspace/src /workspace/src

# nonroot ユーザーで実行
USER 1000:1000

# アプリケーションを起動
ENTRYPOINT ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0"]
```

## compose.yml の構成

### watch によるホットリロード

`develop.watch` を使用して、ファイル変更時にコンテナを同期します。Python のソース変更は `action: sync` でコンテナへ反映し（uvicorn の `--reload` がプロセスを再起動）、依存定義（`pyproject.toml` / `uv.lock`）の変更は `action: rebuild` で再ビルドします。

```yaml
services:
  app:
    container_name: app
    build:
      context: ./app
      target: dev
      secrets:
        - github_token
    develop:
      watch:
        # ソース変更はコンテナへ同期（uvicorn --reload が再起動）
        - path: ./app/src
          target: /workspace/src
          action: sync
        # 依存定義の変更は再ビルド
        - path: ./app/pyproject.toml
          action: rebuild
        - path: ./app/uv.lock
          action: rebuild
    ports:
      - "127.0.0.1:8000:8000"
    tty: true
    stdin_open: true
    environment:
      - ENV=development
      - DATABASE_URL=postgresql+asyncpg://user:pass@db:5432/mydb
    depends_on:
      db:
        condition: service_healthy

  db:
    container_name: app-db
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 10s
      timeout: 5s
      retries: 5

secrets:
  github_token:
    environment: GITHUB_TOKEN
```

### ポイント

| 項目 | 説明 |
| --- | --- |
| `target: dev` | マルチステージビルドの dev ステージを使用 |
| `develop.watch` | ファイル変更を監視し、自動で同期・再ビルド |
| `action: sync` | ソース変更をコンテナへ同期（`--reload` が再起動） |
| `action: rebuild` | `pyproject.toml` / `uv.lock` 変更時にコンテナを再ビルド |
| `127.0.0.1:8000:8000` | ローカルホストのみにバインド |
| `secrets` | GitHub トークンなどの秘密情報 |

### sync と rebuild の使い分け

* `action: sync`: ソースファイルのみをコンテナへ転送する。`uv sync` を再実行しないため高速。uvicorn の `--reload` がファイル更新を検知してプロセスを再起動する
* `action: rebuild`: `pyproject.toml` / `uv.lock` の変更を検知してイメージを再ビルドする。依存追加・更新は必ず再ビルドを経由させ、コンテナとロックファイルの不整合を防ぐ

コンテナ内で `uv lock` を実行した場合のロックファイル変更をホスト側へ反映するには、`uv.lock` を bind mount してもよいですが、依存変更はホスト側で `uv add` → `uv lock` を行い、`rebuild` で取り込む運用を基本とします。

## 起動・停止コマンド

### watch モードでの起動

```shell
# watch モードで起動（ホットリロード有効）
docker compose watch

# バックグラウンドで起動
docker compose up -d

# watch モードをバックグラウンドで起動
docker compose watch --detach
```

### 停止

```shell
# 停止
docker compose down

# ボリュームも削除して停止
docker compose down -v
```

### ログ確認

```shell
# ログを確認
docker compose logs -f app
```

## コンテナ内でのコマンド実行

タスクは Makefile の `カテゴリ/アクション` ターゲット経由で実行します（[プロジェクト構成規約](project-structure.md) 参照）。Makefile 内部は `uv run` で統一し、同一の仮想環境を保証します。

```shell
# テスト実行
docker exec app make code/test

# リンター・型チェック実行
docker exec app make code/lint

# フォーマット
docker exec app make code/fmt

# マイグレーション適用
docker exec app make db/migrate
```

`uv run` を直接呼び出す場合も同じ仮想環境で動作します。

```shell
# 単一テストファイルだけ実行
docker exec app uv run pytest tests/domain/model/test_user.py

# 型チェックのみ
docker exec app uv run mypy src
```

## uv による依存管理

依存・仮想環境は uv で管理し、ロックファイル `uv.lock` をコミットします。実行依存は `[project.dependencies]`、開発用ツールは `[dependency-groups]` の `dev` に分離します（`pyproject.toml` の構成は [プロジェクト構成規約](project-structure.md) を参照）。

### ライブラリ・ツールの追加

```shell
# 実行依存の追加
uv add fastapi

# 開発用ツールの追加（dev グループへ）
uv add --dev pytest

# 依存の削除
uv remove fastapi
```

### 同期と更新

```shell
# ロックに従って環境を同期（再現性のある初期セットアップ）
uv sync --all-extras

# 依存を最新へ更新してロックを再生成
uv lock --upgrade

# ロックを変更せず検証だけ行う（CI 向け）
uv sync --frozen
```

* **`uv.lock` は必ずコミット** する。ロックとインストール内容を一致させ、ローカル・CI・本番の差異を排除する
* **CI では** `uv sync --frozen` を使い、ロックの更新が必要な変更を検出する
* **新規依存追加時はセキュリティスキャン** を実行する（`uv pip audit` など）

## pre-commit による検証

コミット前の検証は pre-commit に集約し、ruff（lint + format）・mypy（strict）・pytest を実行します。フックは uv 経由で同一環境を保証するため `language: system` とし、`uv run` でツールを起動します。

### .pre-commit-config.yaml の例

```yaml
repos:
  - repo: local
    hooks:
      - id: ruff-format
        name: ruff format
        entry: uv run ruff format
        language: system
        types: [python]
      - id: ruff-lint
        name: ruff check
        entry: uv run ruff check --fix
        language: system
        types: [python]
      - id: mypy
        name: mypy
        entry: uv run mypy src
        language: system
        types: [python]
        pass_filenames: false
      - id: pytest
        name: pytest
        entry: uv run pytest
        language: system
        types: [python]
        pass_filenames: false
        stages: [pre-push]
```

### セットアップと実行

```shell
# フックをインストール（commit / push 時に自動実行）
uv run pre-commit install --hook-type pre-commit --hook-type pre-push

# 全ファイルに対して手動実行
uv run pre-commit run --all-files
```

### ポイント

* **ruff / mypy はコミット時、pytest は push 時** に実行し、コミットを軽量に保ちつつ push 前に必ずテストを通す
* **mypy / pytest は** `pass_filenames: false` とし、変更ファイルだけでなくプロジェクト全体を検査する（部分検査では型・テストの整合性が崩れる）
* **`# noqa` /** `# type: ignore` **は理由コメント必須**。pre-commit で抑制を素通りさせない（[Linter 規約](linter.md) 参照）

## alembic によるマイグレーション

スキーマ変更は alembic で管理し、マイグレーションは `migrations/` 配下に配置します（[プロジェクト構成規約](project-structure.md) 参照）。リビジョンファイルはコミット対象とし、レビューで内容を確認します。

### 基本コマンド

```shell
# 初期化（プロジェクト作成時に一度だけ）
uv run alembic init -t async migrations

# 差分からリビジョンを自動生成（生成内容は必ず目視確認する）
uv run alembic revision --autogenerate -m "create users table"

# 最新まで適用
uv run alembic upgrade head

# 1 つ前へロールバック
uv run alembic downgrade -1

# 現在のリビジョンを確認
uv run alembic current
```

### env.py での非同期エンジン接続

非同期ドライバ（asyncpg）を使う場合、`env.py` は `AsyncEngine` でマイグレーションを実行します。接続文字列は環境変数から取得し、`pyproject.toml` や `alembic.ini` に DSN を直書きしません。

```python
"""alembic マイグレーションの実行環境（非同期）。"""

import asyncio
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from app.infrastructure.postgres.metadata import metadata

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# 接続文字列は環境変数から取得する（DSN を直書きしない）
config.set_main_option("sqlalchemy.url", os.environ["DATABASE_URL"])

# autogenerate の比較対象となるメタデータ
target_metadata = metadata


def _run_migrations(connection: Connection) -> None:
    """同期コネクション上でマイグレーションを実行する。"""
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    """非同期エンジンを生成し、マイグレーションを適用する。"""
    engine = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
    )
    async with engine.connect() as connection:
        await connection.run_sync(_run_migrations)
    await engine.dispose()


asyncio.run(run_migrations_online())
```

### マイグレーションの起動順序

DB の起動を待ってからマイグレーションを適用し、その後アプリを起動します。

```shell
# DB を起動 → マイグレーション適用 → アプリ起動
docker compose up -d db && \
docker compose run --rm app make db/migrate && \
docker compose up -d app
```

専用の初期化サービスとして compose に切り出すこともできます。

```yaml
services:
  migrate:
    container_name: app-migrate
    build:
      context: ./app
      target: dev
    command: ["make", "db/migrate"]
    environment:
      - DATABASE_URL=postgresql+asyncpg://user:pass@db:5432/mydb
    depends_on:
      db:
        condition: service_healthy
    restart: on-failure
```

## 環境別の構成

### ローカル専用コードの分離

Go のビルドタグ（`//go:build local`）に相当する仕組みは Python にはありません。ローカル専用コードは **任意依存グループ（optional dependency group）と環境変数による分岐** で分離し、本番イメージには含めません。

* **ローカル専用ツールは** `[project.optional-dependencies]` の `local` extra に分離する
* **ローカル専用の初期化・サブコマンドは** 環境変数（例: `ENV=development`）で有効・無効を切り替える
* **本番イメージは dev / local 依存を含めずビルド** する（Dockerfile の `runtime` ステージは `--no-dev` で sync 済み）

```toml
[project.optional-dependencies]
# ローカルでのみ使うエミュレータ操作ツール等
local = [
    "boto3>=1.35",
]
```

```shell
# ローカル開発では local extra も含めて同期
uv sync --extra local

# 本番イメージは extra を含めない
uv sync --frozen --no-dev
```

### ローカル CLI コマンド

ローカル環境のセットアップは CLI のサブコマンドとして提供し、`ENV` で実行可否を判定します。ハンドラは薄く保ち、初期化処理はユースケースへ委譲します（[プロジェクト構成規約](project-structure.md) の presentation/cli を参照）。

```python
"""ローカル環境セットアップ用の CLI サブコマンド。"""

import asyncio
import logging
import os

from app.application.usecase.local_usecase import LocalUsecase

logger = logging.getLogger(__name__)


async def apply(initializers: list[LocalUsecase]) -> None:
    """ローカル環境に必要なリソースを順に作成する。

    Args:
        initializers: 実行するローカル初期化ユースケースのリスト。

    Raises:
        RuntimeError: 本番環境（ENV != development）で実行された場合。
    """
    # 本番での誤実行を防ぐためのガード
    if os.getenv("ENV") != "development":
        raise RuntimeError("local apply は development 環境でのみ実行できます")

    for initializer in initializers:
        await initializer.apply()
    logger.info("ローカル環境のセットアップが完了しました")


def main() -> None:
    """local apply エントリポイント（pyproject の scripts から呼ばれる）。"""
    asyncio.run(apply(_build_initializers()))


def _build_initializers() -> list[LocalUsecase]:
    """ローカル初期化ユースケースを組み立てる（実装は省略）。"""
    return []
```

## LocalStack による AWS サービスエミュレーション

### 基本方針

* **LocalStack を使用して AWS サービスをローカルでエミュレート** する
* **DynamoDB、SNS、SQS などの主要サービスに対応**
* `local apply` コマンドでリソースを初期化 する

### Docker Compose 設定

```yaml
services:
  app:
    container_name: app
    build:
      context: ./app
      target: dev
      secrets:
        - github_token
    ports:
      - "127.0.0.1:8000:8000"
    environment:
      # AWS エンドポイントを LocalStack に向ける
      - AWS_ENDPOINT_URL=http://app-localstack:4566
      - AWS_REGION=us-east-1
      - AWS_ACCESS_KEY_ID=dummy
      - AWS_SECRET_ACCESS_KEY=dummy
      # DynamoDB テーブル名
      - DYNAMODB_TABLE_NAME=app-items
      # SNS Platform Application ARN
      - SNS_PLATFORM_APP_ARN_IOS=arn:aws:sns:us-east-1:000000000000:app/APNS_SANDBOX/my-ios-app
      - SNS_PLATFORM_APP_ARN_ANDROID=arn:aws:sns:us-east-1:000000000000:app/GCM/my-android-app
    depends_on:
      app-localstack:
        condition: service_healthy

  app-localstack:
    container_name: app-localstack
    image: localstack/localstack:latest
    ports:
      - "127.0.0.1:4566:4566"
    environment:
      - SERVICES=sns,dynamodb,sqs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 5s

secrets:
  github_token:
    environment: GITHUB_TOKEN
```

### Initializer パターン

ローカル環境のリソース初期化は `LocalUsecase` プロトコルを実装し、`local apply` コマンドで実行します。インターフェースは `typing.Protocol` で定義し、依存方向を内向きに保ちます（[アーキテクチャ設計規約](architecture.md) 参照）。

#### LocalUsecase プロトコル

```python
"""ローカル環境セットアップのインターフェース。"""

from typing import Protocol


class LocalUsecase(Protocol):
    """ローカル環境のセットアップを行うインターフェース。"""

    async def apply(self) -> None:
        """ローカル環境に必要なリソースを作成する。"""
        ...
```

#### DynamoDB テーブル初期化

冪等性を確保するため、既存テーブルの存在を確認してから作成します。例外は独自階層（`AppError`）でラップし、`raise X from e` で原因を連鎖させます（[エラーハンドリング規約](error-handling.md) 参照）。

```python
"""ローカル用 DynamoDB テーブルの初期化。"""

from typing import Protocol

from botocore.exceptions import ClientError

from app.errors import InfrastructureError


class DynamoDBClient(Protocol):
    """初期化に必要な DynamoDB クライアントの Protocol。"""

    def describe_table(self, *, TableName: str) -> dict[str, object]:
        """テーブル定義を取得する。"""
        ...

    def create_table(self, **params: object) -> dict[str, object]:
        """テーブルを作成する。"""
        ...


class TableInitializer:
    """DynamoDB テーブルを冪等に作成する初期化ユースケース。"""

    def __init__(self, client: DynamoDBClient, table_name: str) -> None:
        """クライアントとテーブル名を受け取る。"""
        self._client = client
        self._table_name = table_name

    async def apply(self) -> None:
        """テーブルが無ければ作成する（冪等）。

        Raises:
            InfrastructureError: テーブル確認・作成に失敗した場合。
        """
        try:
            # 既存テーブルの存在チェック（冪等性の確保）
            self._client.describe_table(TableName=self._table_name)
            return
        except ClientError as e:
            # ResourceNotFoundException 以外のエラーは異常
            if e.response["Error"]["Code"] != "ResourceNotFoundException":
                raise InfrastructureError(
                    f"テーブル {self._table_name} の確認に失敗しました"
                ) from e

        try:
            self._client.create_table(
                TableName=self._table_name,
                KeySchema=[
                    {"AttributeName": "pk", "KeyType": "HASH"},
                    {"AttributeName": "sk", "KeyType": "RANGE"},
                ],
                AttributeDefinitions=[
                    {"AttributeName": "pk", "AttributeType": "S"},
                    {"AttributeName": "sk", "AttributeType": "S"},
                ],
                BillingMode="PAY_PER_REQUEST",
            )
        except ClientError as e:
            raise InfrastructureError(
                f"テーブル {self._table_name} の作成に失敗しました"
            ) from e
```

#### SNS Platform Application 初期化

```python
"""ローカル用 SNS Platform Application の初期化。"""

from typing import Protocol

from botocore.exceptions import ClientError

from app.errors import InfrastructureError


class SNSClient(Protocol):
    """初期化に必要な SNS クライアントの Protocol。"""

    def list_platform_applications(self) -> dict[str, object]:
        """Platform Application 一覧を取得する。"""
        ...

    def create_platform_application(self, **params: object) -> dict[str, object]:
        """Platform Application を作成する。"""
        ...


class PlatformApplicationInitializer:
    """SNS Platform Application を冪等に作成する初期化ユースケース。"""

    # 作成対象（name, platform, attributes）
    _APPS: tuple[tuple[str, str, dict[str, str]], ...] = (
        ("my-ios-app", "APNS_SANDBOX", {"PlatformCredential": "dummy", "PlatformPrincipal": "dummy"}),
        ("my-android-app", "GCM", {"PlatformCredential": "dummy"}),
    )

    def __init__(self, client: SNSClient) -> None:
        """クライアントを受け取る。"""
        self._client = client

    async def apply(self) -> None:
        """未作成の Platform Application のみ作成する（冪等）。

        Raises:
            InfrastructureError: 一覧取得・作成に失敗した場合。
        """
        try:
            listed = self._client.list_platform_applications()
        except ClientError as e:
            raise InfrastructureError(
                "Platform Application 一覧の取得に失敗しました"
            ) from e

        # ARN に名前が含まれるかで既存チェック
        existing_arns = {
            str(pa["PlatformApplicationArn"])
            for pa in listed.get("PlatformApplications", [])  # type: ignore[union-attr]  # LocalStack 応答の動的構造
        }

        for name, platform, attrs in self._APPS:
            if any(name in arn for arn in existing_arns):
                continue
            try:
                self._client.create_platform_application(
                    Name=name, Platform=platform, Attributes=attrs
                )
            except ClientError as e:
                raise InfrastructureError(
                    f"Platform Application {name} の作成に失敗しました"
                ) from e
```

### 初期化サービスの Docker Compose 設定

```yaml
services:
  app-initializer:
    container_name: app-initializer
    build:
      context: ./app
      target: dev
      secrets:
        - github_token
    working_dir: /workspace
    environment:
      - ENV=development
      - LOG_LEVEL=debug
      - AWS_ENDPOINT_URL=http://app-localstack:4566
      - AWS_REGION=us-east-1
      - AWS_ACCESS_KEY_ID=dummy
      - AWS_SECRET_ACCESS_KEY=dummy
    command: ["uv", "run", "app", "local", "apply"]
    depends_on:
      app-localstack:
        condition: service_healthy
    restart: on-failure
```

### 起動順序

LocalStack を使用する場合の起動順序：

1. **LocalStack を起動**: `docker compose up -d app-localstack`
2. **Initializer を実行**: `docker compose up --build app-initializer`
3. **アプリケーションを起動**: `docker compose up -d --build app`

```shell
# 一括起動（推奨）
docker compose up -d app-localstack && \
docker compose up --build app-initializer && \
docker compose up -d --build app
```

## サードパーティサービスのローカル環境

### データストアサービス

サードパーティのデータストアサービス（データベース、キャッシュなど）をローカルで動かす場合の設定例です。

#### PostgreSQL の例

```yaml
services:
  postgres:
    container_name: app-postgres
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres-data:
```

#### キーバリューストアの例

```yaml
services:
  kvstore:
    container_name: app-kvstore
    image: vendor/kvstore-local:latest
    ports:
      - "127.0.0.1:8001:8001"
    volumes:
      - kvstore-data:/data
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8001/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
    command:
      - "-inMemory"
      - "-sharedDb"

volumes:
  kvstore-data:
```

#### Redis の例

```yaml
services:
  redis:
    container_name: app-redis
    image: redis:7-alpine
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  redis-data:
```

### ヘルスチェックの設定

サービスの起動を待つため、ヘルスチェックを設定します：

```yaml
services:
  app:
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
```

### 環境変数での接続先設定

ローカル環境では環境変数でサービスの接続先を上書きします。接続文字列はコードに直書きせず環境変数から読み込み、ドメイン例外と同様に DSN などの秘密情報はログへ出力しません（[インフラストラクチャパターン規約](infrastructure.md) 参照）。

```yaml
services:
  app:
    environment:
      # サードパーティサービスのエンドポイントをローカルに向ける
      DATABASE_URL: postgresql+asyncpg://user:pass@postgres:5432/mydb
      REDIS_ENDPOINT: redis:6379
```

## 関連ドキュメント

* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成、src レイアウト、Makefile、`pyproject.toml`
* [テストコード規約](testing.md) - pytest 実行、フェイク・モック、E2E テスト
* [インフラストラクチャパターン規約](infrastructure.md) - Protocol によるクライアント抽象化、datasource パターン、SQL 外出し
* [アーキテクチャ設計規約](architecture.md) - レイヤー構成、依存性注入
* [エラーハンドリング規約](error-handling.md) - 例外階層、`raise ... from e` による連鎖
* [Linter 規約](linter.md) - ruff / mypy 設定、`# noqa` / `# type: ignore` の抑制ルール

## 参考資料

* [Docker Compose Watch](https://docs.docker.com/compose/file-watch/)
* [uv Documentation](https://docs.astral.sh/uv/)
* [uv Docker integration guide](https://docs.astral.sh/uv/guides/integration/docker/)
* [pre-commit](https://pre-commit.com/)
* [Alembic Documentation](https://alembic.sqlalchemy.org/)
* [LocalStack](https://docs.localstack.cloud/) - AWS サービスエミュレーター
