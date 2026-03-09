# プロジェクト構成規約

## 概要

プロジェクト構成とビルドツールの規約です。Makefile の自己文書化パターンやプロジェクト構造の標準化により、開発者がプロジェクトをすぐに理解できるようにします。

## Makefile 自己文書化

### 基本方針

* **Makefile にヘルプ機能** を提供する
* **各ターゲットにコメント（** `##` ）で説明 を追加する
* `make` または `make help` で使用可能なコマンド一覧を表示する
* **ターゲット名は** `カテゴリ/アクション` 形式 を使用する（例: `code/lint`, `image/build`）
* `.PHONY` は動的に自動生成する

### 実装例

```makefile
.PHONY: $(shell egrep -o ^[a-zA-Z_/.-]+: $(MAKEFILE_LIST) | sed 's/://')
SHELL=/bin/bash

help: ## ヘルプを表示する
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z].+:.*?## / {printf "\\033[36m%-30s\\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

code/generate: ## スキーマからコードを生成する
	@cd schema; go tool buf generate
	@go generate ./...

code/lint: ## コードを静的解析する
	@go tool golangci-lint run --timeout=5m --config ../.golangci.yml

code/test: ## コードをテストする
	@go tool gotest -v ./...

code/fmt: ## コードのフォーマットを整える
	@go fmt ./...

image/build: ## Dockerイメージをビルドする
	@docker build -t app:latest --platform=linux/amd64 .

install: ## 依存関係をダウンロード
	@go mod download
```

### 使用例

```shell
$ make
Usage: make [target]

Targets:
code/fmt                       コードのフォーマットを整える
code/generate                  スキーマからコードを生成する
code/lint                      コードを静的解析する
code/test                      コードをテストする
help                           ヘルプを表示する
image/build                    Dockerイメージをビルドする
install                        依存関係をダウンロード
```

### ポイント

* **自動 PHONY 宣言**: `egrep` で全ターゲットを抽出して `.PHONY` に設定
* **カラー表示**: ANSI カラーコード（ `\\033[36m]` ）で見やすく
* **30文字幅で整形**: AWK の `printf` で左詰め表示
* **go tool の活用**: `go tool golangci-lint`, `go tool gotest` など

## プロジェクト構造

### 基本方針

* **起動コマンドはモジュールルートに配置** する（ `cmd` ディレクトリは使用しない）
* **各パッケージに** `package.go` を配置してパッケージの目的を説明する（**必須**）
* **依存関係の方向を明確** にする（上位層→下位層）

### ディレクトリ構成例

```plaintext
app/
├── main.go                   # エントリポイント（モジュールルート）
├── domain/                   # ドメイン層
│   ├── model/                # エンティティと集約ルート
│   │   ├── user.go
│   │   ├── user_repository.go  # リポジトリインターフェース
│   │   ├── user_test.go
│   │   ├── mock/             # モック（パッケージ内に配置）
│   │   │   └── user_repository_mock.go
│   │   └── package.go
│   └── types/                # 値オブジェクト
│       ├── user_id.go
│       ├── email.go
│       ├── optional.go
│       └── package.go
├── application/              # アプリケーション層
│   ├── usecase/              # ユースケース実装
│   │   ├── user_usecase.go
│   │   ├── user_usecase_test.go
│   │   └── package.go
│   ├── queryservice/         # クエリサービスインターフェース
│   │   ├── user_query_service.go
│   │   └── package.go
│   └── types/                # アプリケーション層固有の型（クエリサービス用DTO・ユースケース固有型等）
│       ├── user_dto.go
│       └── package.go
├── infrastructure/           # インフラストラクチャ層
│   ├── postgres/             # PostgreSQL 実装
│   │   ├── user_datasource.go
│   │   ├── user_datasource_test.go
│   │   └── package.go
│   ├── dynamodb/             # DynamoDB 実装
│   │   ├── client.go
│   │   └── package.go
│   ├── s3/                   # S3 実装
│   │   ├── uploader.go
│   │   └── package.go
│   ├── redis/                # Redis 実装
│   │   ├── cache.go
│   │   └── package.go
│   ├── sns/                  # SNS 実装
│   │   ├── publisher.go
│   │   └── package.go
│   └── httpcli/              # HTTP クライアント（必要に応じて追加）
│       ├── client.go
│       └── package.go
├── presentation/             # プレゼンテーション層
│   ├── httphandler/          # HTTP ハンドラ
│   │   ├── user_handler.go       # ハンドラー実装
│   │   ├── request.go            # リクエスト→ドメイン型変換
│   │   ├── response.go           # ドメイン型→レスポンス変換
│   │   ├── middleware/            # HTTP ミドルウェア
│   │   │   ├── auth_middleware.go
│   │   │   ├── error_log_middleware.go
│   │   │   ├── recovery_middleware.go
│   │   │   └── package.go
│   │   ├── user_handler_test.go
│   │   ├── request_test.go
│   │   ├── response_test.go
│   │   ├── export_test.go        # テスト用エクスポート
│   │   └── package.go
│   ├── grpc/                 # gRPC サーバー
│   │   ├── user_service.go
│   │   └── package.go
│   └── cli/                  # CLI コマンド
│       ├── root.go
│       └── package.go
├── schema/                   # スキーマ定義
│   ├── proto/                # Protobuf 定義
│   │   ├── buf.yaml
│   │   ├── buf.gen.yaml
│   │   └── user.proto
│   └── postgres/             # PostgreSQL スキーマ
│       └── migrations/       # データベースマイグレーション
│           ├── 000001_create_users.up.sql
│           └── 000001_create_users.down.sql
├── generated/                # 生成されたコード
│   └── go/
│       └── schemas/
├── Makefile                  # ビルドタスク
├── Dockerfile                # Docker イメージ定義
├── compose.yml               # ローカル開発環境
├── go.mod                    # Go モジュール定義
├── go.sum                    # Go モジュール依存関係
├── .golangci.yml             # リンター設定
└── README.md                 # プロジェクト概要
```

### プレゼンテーション層の構成

プレゼンテーション層（ `presentation/` ）は、外部からのリクエストを受け付け、ドメイン層やアプリケーション層と連携して、適切なレスポンスを返す役割を担います。

#### ディレクトリ構造

```plaintext
presentation/
├── httphandler/              # HTTP ハンドラ
│   ├── user_handler.go       # ハンドラー実装
│   ├── request.go            # リクエスト→ドメイン型変換
│   ├── response.go           # ドメイン型→レスポンス変換
│   ├── middleware/            # HTTP ミドルウェア
│   │   ├── auth_middleware.go
│   │   ├── error_log_middleware.go
│   │   ├── recovery_middleware.go
│   │   └── package.go
│   ├── user_handler_test.go
│   ├── request_test.go
│   ├── response_test.go
│   ├── export_test.go        # テスト用エクスポート
│   └── package.go
├── grpc/                     # gRPC サーバー
│   ├── user_service.go
│   └── package.go
└── cli/                      # CLI コマンド
    ├── root.go
    └── package.go
```

#### ファイルの役割

| ファイル | 役割 | 責務 |
| --- | --- | --- |
| `*_handler.go` | ハンドラー実装 | リクエストの受付、ユースケースの呼び出し、レスポンスの返却 |
| `request.go` | リクエスト変換 | API スキーマ型 → ドメイン型への変換ロジック |
| `response.go` | レスポンス変換 | ドメイン型 → API スキーマ型への変換ロジック |
| `export_test.go` | テスト用エクスポート | 変換関数などの非公開関数をテストで使用可能にする |

> **Note:** gRPCハンドラーでは `request.go` / `response.go` の代わりに `converter.go` としてリクエスト・レスポンス変換を1ファイルにまとめるパターンも使用されています。

#### 設計のポイント

* **変換ロジックの分離**: リクエスト変換とレスポンス変換を別ファイルに分離し、ハンドラーの責務を明確にする
* **ドメイン駆動**: API 型ではなくドメイン型を中心にビジネスロジックを記述する
* **テスト容易性**: 変換ロジックを独立したファイルに分離することで、単体テストが書きやすくなる

#### 実装例

**handler.go（ハンドラー）**

```go
type UserHandler struct {
    userUsecase usecase.UserUsecase
}

func (h *UserHandler) GetUser(
    ctx context.Context,
    request openapi.GetUserRequestObject,
) (openapi.GetUserResponseObject, error) {
    // リクエストからドメイン型へ変換
    userID := toUserID(request.UserId)

    // ユースケースを呼び出し
    user, err := h.userUsecase.GetUser(ctx, userID)
    if err != nil {
        return nil, err
    }

    // ドメイン型からレスポンスへ変換
    response := toUserResponse(user)
    return openapi.GetUser200JSONResponse(response), nil
}
```

**request.go（リクエスト変換）**

```go
// toUserID は文字列から UserID に変換する
func toUserID(id string) types.UserID {
    return types.UserIDOf(id)
}

// toUserEmail は文字列から Email に変換する
func toUserEmail(email string) (types.Email, error) {
    return types.EmailFrom(email)
}
```

**response.go（レスポンス変換）**

```go
// toUserResponse はドメインモデルを API レスポンスに変換する
func toUserResponse(user *model.User) openapi.User {
    resp := openapi.User{
        Id:   ptr(user.UserID().String()),
        Name: ptr(user.DisplayName()),
    }
    if email, ok := user.Email().Value(); ok {
        resp.Email = ptr(email.String())
    }
    return resp
}

// ptr はポインタを返すヘルパー関数
func ptr[T any](v T) *T {
    return &v
}
```

**export_test.go（テスト用エクスポート）**

```go
// テスト用に変換関数をエクスポート
var (
    ToUserID       = toUserID
    ToUserEmail    = toUserEmail
    ToUserResponse = toUserResponse
    Ptr            = ptr
)
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

- Go 1.25+
- PostgreSQL 15
- gRPC
- Docker / Docker Compose

## ローカル開発環境

ローカル開発環境のセットアップと開発コマンドについては、
ローカル開発環境規約を参照してください。

### クイックスタート

1. リポジトリをクローン
   git clone https://example.com/app.git
   cd app

2. Docker Compose watch で起動
   docker compose watch
```

## go.mod の管理

### 基本方針

* **Go モジュールは** `go.mod` で管理 する
* **バージョンは可能な限り最新の安定版** を使用する
* **不要な依存関係は定期的に削除** する（ `go mod tidy` ）
* `go mod vendor` は使用しない

### go.mod の例

```go
module example.com/app

go 1.25

require (
	github.com/google/uuid v1.6.0
	golang.org/x/xerrors v0.0.0-20231012003039-104605ab7028
	google.golang.org/grpc v1.62.0
)

// ツール依存（Go 1.24+）
tool (
	github.com/golangci/golangci-lint/cmd/golangci-lint
	github.com/rakyll/gotest
	go.uber.org/mock/mockgen
)
```

### 依存関係の更新

```shell
# すべての依存関係を最新に更新
go get -u ./...

# 不要な依存関係を削除
go mod tidy
```

## 関連ドキュメント

* [ローカル開発環境規約](local-dev.md) - Docker Compose watch によるホットリロード開発環境、開発コマンド
* [テストコード規約](testing.md) - テストの構造化、モックの使用方法
* [HTTPハンドラー・プレゼンテーション層規約](http-handler.md) - HTTP ハンドラーの実装パターン、リクエスト/レスポンス変換

## 参考資料

* [Go Project Layout](https://github.com/golang-standards/project-layout)
* [Go Modules Reference](https://go.dev/ref/mod)
* [Makefile Tutorial](https://makefiletutorial.com/)
