# ローカル開発環境規約

## 概要

ローカル開発環境の構築と運用に関する規約です。Docker Compose の watch 機能を活用したホットリロード開発環境を標準とします。

## 基本方針

* **Docker Compose + watch で開発環境を構築** する
* **ファイル変更時に自動でコンテナを再ビルド** する（ホットリロード）
* **依存ツールは** `go.mod` の `tool` ディレクティブで管理する（Go 1.24+）
* **ポートはローカルホストにバインド** して外部からのアクセスを防ぐ

## Dockerfile の構成

マルチステージビルドを使用し、ビルダーステージとランタイムステージを分離します。

```dockerfile
# ビルダーステージ
FROM golang:1.25 AS builder

# 作業ディレクトリを設定
WORKDIR /workspace

# Go モジュールをコピー
COPY go.mod go.sum ./
RUN go mod download

# ソースコードをコピー
COPY . .

# アプリケーションをビルド（モジュールルートから）
RUN CGO_ENABLED=0 GOOS=linux go build -o /app .

# ローカル開発時はこのステージで起動（docker compose watch の target: builder）
CMD ["go", "run", "."]

# ランタイムステージ
FROM gcr.io/distroless/base-debian12

# ビルダーステージから実行ファイルをコピー
COPY --from=builder /app /app

# nonroot ユーザーで実行
USER nonroot:nonroot

# アプリケーションを起動
ENTRYPOINT ["/app"]
```

## docker compose の構成

### watch によるホットリロード

`develop.watch` を使用して、ファイル変更時に自動でコンテナを再ビルドします。

```yaml
services:
  app:
    container_name: app
    build:
      context: ./app
      target: builder
      secrets:
        - github_token
    develop:
      watch:
        - path: ./app
          action: rebuild
          ignore:
            - .gitignore
            - .golangci.yml
    ports:
      - "127.0.0.1:8080:8080"
    tty: true
    stdin_open: true
    volumes:
      # コンテナ内で go mod tidy などを実行した際の変更をホスト側に反映
      - ./app/go.mod:/workspace/go.mod
      - ./app/go.sum:/workspace/go.sum
      # コード生成されたファイルをホスト側に反映
      - ./app/generated:/workspace/generated
    environment:
      - DATABASE_URL=postgres://user:pass@db:5432/mydb

  db:
    container_name: app-db
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    ports:
      - "127.0.0.1:5432:5432"

secrets:
  github_token:
    environment: GITHUB_TOKEN
```

### ポイント

| 項目 | 説明 |
| --- | --- |
| `target: builder` | マルチステージビルドの builder ステージを使用 |
| `develop.watch` | ファイル変更を監視し、自動で再ビルド |
| `action: rebuild` | 変更検知時にコンテナを再ビルド |
| `ignore` | 再ビルド対象から除外するファイル |
| `127.0.0.1:8080:8080` | ローカルホストのみにバインド |
| `secrets` | GitHub トークンなどの秘密情報 |

### volumes のマウント

コンテナ内での変更をホスト側に反映させるため、以下のファイルをマウントします：

* `go.mod` / `go.sum` : 依存関係の変更をホストに反映
* `generated/` : コード生成されたファイルをホストに反映
* `mock/` : モック生成されたファイルをホストに反映

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

```shell
# テスト実行
docker exec app make code/test

# リンター実行
docker exec app make code/lint

# コード生成
docker exec app make code/generate

# フォーマット
docker exec app make code/fmt
```

## Go tool による依存管理

`go.mod` に tool ディレクティブを追加して、ツールを管理します（Go 1.24+）。

```go
module example.com/app

go 1.25

require (
	github.com/google/uuid v1.6.0
	golang.org/x/xerrors v0.0.0-20231012003039-104605ab7028
)

// ツール依存
tool (
	github.com/golangci/golangci-lint/cmd/golangci-lint
	github.com/rakyll/gotest
	go.uber.org/mock/mockgen
)
```

### ライブラリ・ツールの追加

```shell
# Go ライブラリの追加
docker exec app go get github.com/example/library@v1.0.0

# Go ツールの追加（Go 1.24+）
docker exec app go get -tool github.com/example/tool@v1.0.0
```

## ビルドタグによる環境別ビルド

### 基本方針

* **ローカル専用コードは** `//go:build local` タグで分離する
* **本番環境では不要なコードをビルドから除外** できる
* **開発用の初期化処理やデバッグ機能** に使用する

### ビルドタグの設定

```go
// main_local.go
//go:build local

package main

import "example.com/app/presentation/cli"

func init() {
	// ローカル専用サブコマンド登録
	rootCmd.AddCommand(cli.NewLocalCLI().Command())
}
```

```go
// presentation/cli/local.go
//go:build local

package cli

import (
	"context"
	"log/slog"

	"example.com/app/application/usecase"
	"github.com/spf13/cobra"
)

// LocalCLI はローカル環境のセットアップコマンドを提供します
type LocalCLI struct {
	initializers []usecase.LocalUsecase
}

// NewLocalCLI は新しいLocalCLIインスタンスを作成します
func NewLocalCLI(initializers ...usecase.LocalUsecase) *LocalCLI {
	return &LocalCLI{initializers: initializers}
}

// Command は local サブコマンドを返します
func (c *LocalCLI) Command() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "local",
		Short: "ローカル環境のセットアップ",
	}

	applyCmd := &cobra.Command{
		Use:   "apply",
		Short: "ローカル環境に必要なリソースを作成",
		RunE: func(cmd *cobra.Command, args []string) error {
			return c.apply(cmd.Context())
		},
	}

	cmd.AddCommand(applyCmd)
	return cmd
}

func (c *LocalCLI) apply(ctx context.Context) error {
	for _, initializer := range c.initializers {
		if err := initializer.Apply(ctx); err != nil {
			slog.Error("ローカル環境のセットアップに失敗しました", "error", err)
			return err
		}
	}

	slog.Info("ローカル環境のセットアップが完了しました")
	return nil
}
```

### ビルド方法

```shell
# ローカルタグ付きでビルド
go build -tags local .

# ローカルタグ付きで実行
go run -tags local . local apply

# 本番ビルド（ローカルコードを除外）
go build .
```

### Dockerfile でのビルドタグ使用

```dockerfile
# ローカル開発用ステージ
FROM golang:1.25 AS builder-local
WORKDIR /workspace
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# -tags local でビルド
RUN CGO_ENABLED=0 GOOS=linux go build -tags local -o /app .
CMD ["/app"]

# 本番用ステージ
FROM golang:1.25 AS builder
WORKDIR /workspace
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# タグなしでビルド（ローカルコードを除外）
RUN CGO_ENABLED=0 GOOS=linux go build -o /app .
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
      target: builder
      secrets:
        - github_token
    ports:
      - "127.0.0.1:8080:8080"
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

ローカル環境のリソース初期化は `LocalUsecase` インターフェースを実装し、
`local apply` コマンドで実行します。

#### LocalUsecase インターフェース

```go
// application/usecase/local_usecase.go
//go:build local

package usecase

import "context"

// LocalUsecase はローカル環境のセットアップを行うインターフェースです
type LocalUsecase interface {
    Apply(ctx context.Context) error
}
```

#### DynamoDB テーブル初期化

```go
// infrastructure/dynamodb/table_initializer.go
//go:build local

package dynamodb

import (
    "context"
    "errors"
    "time"

    "example.com/app/application/usecase"
    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
    "golang.org/x/xerrors"
)

type tableInitializer struct {
    client    Client
    tableName string
}

func NewTableInitializer(client Client, tableName string) usecase.LocalUsecase {
    return &tableInitializer{
        client:    client,
        tableName: tableName,
    }
}

func (t *tableInitializer) Apply(ctx context.Context) error {
    ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
    defer cancel()

    // 既存テーブルの存在チェック（冪等性の確保）
    _, err := t.client.DescribeTable(ctx, &dynamodb.DescribeTableInput{
        TableName: aws.String(t.tableName),
    })
    if err == nil {
        // テーブルが既に存在する場合はスキップ
        return nil
    }
    // ResourceNotFoundException 以外のエラーは異常
    var notFound *types.ResourceNotFoundException
    if !errors.As(err, &notFound) {
        return xerrors.Errorf("テーブル %s の確認に失敗しました: %w", t.tableName, err)
    }

    _, err = t.client.CreateTable(ctx, &dynamodb.CreateTableInput{
        TableName: aws.String(t.tableName),
        KeySchema: []types.KeySchemaElement{
            {AttributeName: aws.String("pk"), KeyType: types.KeyTypeHash},
            {AttributeName: aws.String("sk"), KeyType: types.KeyTypeRange},
        },
        AttributeDefinitions: []types.AttributeDefinition{
            {AttributeName: aws.String("pk"), AttributeType: types.ScalarAttributeTypeS},
            {AttributeName: aws.String("sk"), AttributeType: types.ScalarAttributeTypeS},
        },
        BillingMode: types.BillingModePayPerRequest,
    })
    if err != nil {
        return xerrors.Errorf("テーブル %s の作成に失敗しました: %w", t.tableName, err)
    }

    return nil
}
```

#### SNS Platform Application 初期化

```go
// infrastructure/sns/platform_application_initializer.go
//go:build local

package sns

import (
    "context"
    "strings"
    "time"

    "example.com/app/application/usecase"
    "github.com/aws/aws-sdk-go-v2/aws"
    awssns "github.com/aws/aws-sdk-go-v2/service/sns"
    "golang.org/x/xerrors"
)

type platformApplicationInitializer struct {
    client Client
}

func NewPlatformApplicationInitializer(client Client) usecase.LocalUsecase {
    return &platformApplicationInitializer{client: client}
}

func (p *platformApplicationInitializer) Apply(ctx context.Context) error {
    ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
    defer cancel()

    // 既存の Platform Application を取得（冪等性の確保）
    existing := make(map[string]bool)
    listOut, err := p.client.ListPlatformApplications(ctx, &awssns.ListPlatformApplicationsInput{})
    if err != nil {
        return xerrors.Errorf("Platform Application 一覧の取得に失敗しました: %w", err)
    }
    for _, pa := range listOut.PlatformApplications {
        existing[aws.ToString(pa.PlatformApplicationArn)] = true
    }

    apps := []struct {
        name     string
        platform string
        attrs    map[string]string
    }{
        {
            name:     "my-ios-app",
            platform: "APNS_SANDBOX",
            attrs:    map[string]string{"PlatformCredential": "dummy", "PlatformPrincipal": "dummy"},
        },
        {
            name:     "my-android-app",
            platform: "GCM",
            attrs:    map[string]string{"PlatformCredential": "dummy"},
        },
    }

    for _, app := range apps {
        // ARN に名前が含まれるかで既存チェック
        found := false
        for arn := range existing {
            if strings.Contains(arn, app.name) {
                found = true
                break
            }
        }
        if found {
            continue
        }

        if _, err := p.client.CreatePlatformApplication(ctx, &awssns.CreatePlatformApplicationInput{
            Name:       aws.String(app.name),
            Platform:   aws.String(app.platform),
            Attributes: app.attrs,
        }); err != nil {
            return xerrors.Errorf("Platform Application %s の作成に失敗しました: %w", app.name, err)
        }
    }

    return nil
}
```

### 初期化サービスの Docker Compose 設定

```yaml
services:
  app-initializer:
    container_name: app-initializer
    build:
      context: ./app
      target: builder-local
      secrets:
        - github_token
    working_dir: /workspace
    environment:
      - LOG_OPTION=development
      - LOG_LEVEL=debug
      - AWS_ENDPOINT_URL=http://app-localstack:4566
      - AWS_REGION=us-east-1
      - AWS_ACCESS_KEY_ID=dummy
      - AWS_SECRET_ACCESS_KEY=dummy
    command: ["local", "apply"]
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
      - "127.0.0.1:8000:8000"
    volumes:
      - kvstore-data:/data
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
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
      datastore:
        condition: service_healthy
      redis:
        condition: service_healthy
```

### 環境変数での接続先設定

ローカル環境では環境変数でサービスの接続先を上書きします：

```yaml
services:
  app:
    environment:
      # サードパーティサービスのエンドポイントをローカルに向ける
      DATASTORE_ENDPOINT: http://datastore:8000
      REDIS_ENDPOINT: redis:6379
```

## 関連ドキュメント

* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成、命名規則
* [テストコード規約](testing.md) - テスト実行、モック生成、E2Eテスト
* [インフラストラクチャパターン規約](infrastructure.md) - SDK クライアントインターフェース

## 参考資料

* [Docker Compose Watch](https://docs.docker.com/compose/file-watch/)
* [Go Modules Reference](https://go.dev/ref/mod)
* [Go Build Constraints](https://pkg.go.dev/cmd/go#hdr-Build_constraints)
* [LocalStack](https://docs.localstack.cloud/) - AWS サービスエミュレーター
