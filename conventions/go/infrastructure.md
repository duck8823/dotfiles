# インフラストラクチャパターン規約

## 概要

インフラストラクチャ層の設計パターンと実装規約です。ログ記録、Graceful Shutdown、gRPC ミドルウェアなど、本番環境で必要となる横断的関心事を扱います。

## ログ記録規約

### 基本方針

* **構造化ログ** を使用する（JSON 形式を推奨）
* **コンテキスト情報**（リクエストID など）を含める
* **適切なログレベル** を使用する（DEBUG、INFO、WARN、ERROR）
* **機密情報**（パスワード、トークン、ユーザーIDなど）はログに出力しない
* **Go 標準の** `log/slog` パッケージを使用する

### 実装例

```go
package main

import (
	"context"
	"log/slog"
	"os"
)

func main() {
	// 環境に応じたログレベルを設定
	var level slog.Level
	env := os.Getenv("ENV")
	switch env {
	case "production":
		level = slog.LevelInfo
	case "development":
		level = slog.LevelDebug
	default:
		level = slog.LevelInfo
	}

	opts := &slog.HandlerOptions{
		Level: level,
	}

	// JSON ハンドラを作成
	logger := slog.New(slog.NewJSONHandler(os.Stdout, opts))

	// デフォルトロガーとして設定
	slog.SetDefault(logger)

	ctx := context.Background()

	// ログ出力例
	slog.InfoContext(ctx, "アプリケーションを起動",
		"env", env,
		"version", "1.0.0",
	)
}
```

### コンテキストへのフィールド追加

リクエストIDなどの共通情報をコンテキストに含める場合：

```go
package middleware

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/google/uuid"
)

// context key は非公開の専用型を使用する（string key は他パッケージと衝突するため禁止）
type requestIDKey struct{}
type loggerKey struct{}

func RequestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := uuid.New().String()

		// コンテキストにリクエストIDを追加
		ctx := context.WithValue(r.Context(), requestIDKey{}, requestID)

		// ロガーにリクエストIDを含める
		logger := slog.With("requestID", requestID)
		ctx = context.WithValue(ctx, loggerKey{}, logger)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequestIDFromContext はコンテキストからリクエストIDを取得する
func RequestIDFromContext(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey{}).(string)
	return id
}
```

## Graceful Shutdown

### 基本方針

* **シグナル（SIGTERM、SIGINT）を受信したら、新しいリクエストを拒否** する
* **処理中のリクエストは完了するまで待機** する（タイムアウトあり）
* **データベース接続やメッセージキューなどのリソースを適切にクローズ** する

### 実装例

```go
package server

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"golang.org/x/xerrors"
)

// Server は HTTP サーバーを表す
type Server struct {
	httpServer *http.Server
}

// NewServer は新しい Server を作成する
func NewServer(addr string, handler http.Handler) *Server {
	return &Server{
		httpServer: &http.Server{
			Addr:    addr,
			Handler: handler,
		},
	}
}

// Start はサーバーを起動し、Graceful Shutdown を処理する
func (s *Server) Start() error {
	// シグナルチャネルを作成
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)

	// サーバーを別のゴルーチンで起動
	errCh := make(chan error, 1)
	go func() {
		slog.Info("サーバーを起動", "addr", s.httpServer.Addr)
		if err := s.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- xerrors.Errorf("サーバーの起動に失敗: %w", err)
		}
	}()

	// シグナルまたは起動エラーを待機
	var sig os.Signal
	select {
	case err := <-errCh:
		return err
	case sig = <-sigChan:
		slog.Info("シグナルを受信", "signal", sig)
	}

	// Graceful Shutdown を実行
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	slog.Info("サーバーをシャットダウン中...")
	if err := s.httpServer.Shutdown(ctx); err != nil {
		return xerrors.Errorf("サーバーのシャットダウンに失敗: %w", err)
	}

	slog.Info("サーバーを正常に停止しました")
	return nil
}
```

## gRPC ミドルウェア

### 基本方針

* **gRPC インターセプター** を使用して横断的関心事を処理する
* **ログ記録、認証、認可、メトリクス収集** などに活用する
* **Unary インターセプター**（単一リクエスト/レスポンス）と **Stream インターセプター**（ストリーミング）を区別する

### 実装例

```go
package interceptor

import (
	"context"
	"log/slog"
	"time"

	"google.golang.org/grpc"
)

// LoggingInterceptor はログ記録用の Unary インターセプター
func LoggingInterceptor() grpc.UnaryServerInterceptor {
	return func(
		ctx context.Context,
		req any,
		info *grpc.UnaryServerInfo,
		handler grpc.UnaryHandler,
	) (any, error) {
		start := time.Now()

		slog.InfoContext(ctx, "gRPC リクエスト開始", "method", info.FullMethod)

		resp, err := handler(ctx, req)

		duration := time.Since(start)
		if err != nil {
			slog.ErrorContext(ctx, "gRPC リクエスト失敗",
				"method", info.FullMethod, "duration", duration, "error", err)
		} else {
			slog.InfoContext(ctx, "gRPC リクエスト完了",
				"method", info.FullMethod, "duration", duration)
		}

		return resp, err
	}
}
```

## データストアアクセスパターン

### 基本方針

* **リポジトリパターン** を使用してデータアクセスを抽象化する
* **サードパーティライブラリのクライアントはインターフェース化** する（テスタビリティ向上）
* **DTO（Data Transfer Object）** でドメインモデルとデータストア形式を変換する

### サードパーティクライアントのインターフェース化

サードパーティライブラリ（データベースSDK、ストレージSDKなど）を直接使用せず、必要なメソッドのみを持つインターフェースを定義します。

#### インターフェース命名規則

サードパーティ SDK のクライアントをインターフェース化する際は、**SDK の構造体名と同じ名前を使用** し、import alias で名前衝突を回避します。

```go
// infrastructure/sns/client.go
package sns

import (
    "context"

    awssns "github.com/aws/aws-sdk-go-v2/service/sns"  // import alias を使用
)

//go:generate go tool mockgen -source=$GOFILE -destination=mock/$GOFILE -package=mock

// Client は SNS クライアントのインターフェース
// AWS SDK の構造体名 (sns.Client) と同じ名前を使用
type Client interface {
    CreatePlatformEndpoint(ctx context.Context, params *awssns.CreatePlatformEndpointInput, optFns ...func(*awssns.Options)) (*awssns.CreatePlatformEndpointOutput, error)
    CreatePlatformApplication(ctx context.Context, params *awssns.CreatePlatformApplicationInput, optFns ...func(*awssns.Options)) (*awssns.CreatePlatformApplicationOutput, error)
}
```

#### 命名規則の比較

| パターン | 例 | 評価 | 理由 |
| --- | --- | --- | --- |
| SDK 構造体名と一致 | `sns.Client` | ○ 推奨 | SDK の命名に準拠、直感的 |
| パッケージ名と重複 | `sns.SNSClient` | × 非推奨 | 冗長、lint 警告の対象 |
| 独自命名 | `sns.AwsClient` | × 非推奨 | SDK の命名と不一致 |

### リポジトリ実装（DynamoDB 例）

```go
// infrastructure/dynamodb/user_datasource.go
package dynamodb

import (
	"context"

	"example.com/app/domain/model"
	"example.com/app/domain/types"
	"golang.org/x/xerrors"
)

type userDataSource struct {
	client    Client
	tableName string
}

func NewUserDataSource(client Client, tableName string) model.UserRepository {
	return &userDataSource{
		client:    client,
		tableName: tableName,
	}
}

func (d *userDataSource) FindByID(ctx context.Context, id types.UserID) (types.Optional[*model.User], error) {
	// ...
	var item userItem
	if err := attributevalue.UnmarshalMap(result.Item, &item); err != nil {
		return types.None[*model.User](), xerrors.Errorf("アイテムのアンマーシャルに失敗しました: %w", err)
	}
	user, err := item.toUser()
	if err != nil {
		return types.None[*model.User](), xerrors.Errorf("ユーザーへの変換に失敗しました: %w", err)
	}
	return types.Some(user), nil
}
```

### DTOパターン

ドメインモデルとデータストアの形式を変換するDTOを定義します。

```go
// infrastructure/dynamodb/user_item.go
package dynamodb

import (
	"time"

	"example.com/app/domain/model"
	"example.com/app/domain/types"
	"golang.org/x/xerrors"
)

// userItem はデータストアのアイテム形式
// 値レシーバー、値返却のパターンを使用
type userItem struct {
	UserID    string    `dynamodbav:"user_id"`
	Email     *string   `dynamodbav:"email,omitempty"`
	DisplayName string    `dynamodbav:"display_name"`
	CreatedAt time.Time `dynamodbav:"created_at"`
	UpdatedAt time.Time `dynamodbav:"updated_at"`
}

// toUser はDTOからドメインモデルに変換する（値レシーバー・非公開）
func (i userItem) toUser() (*model.User, error) {
	// ...
}

// fromUser はドメインモデルからDTOに変換する（値返却）
func fromUser(user *model.User) userItem {
	// ...
}
```

## MySQL + sqlx パターン

MySQL を使用するリポジトリ実装では、`sqlx` と `go:embed` による SQL 外出しパターンを使用します。

### Open 関数

`Open` 関数で `*sqlx.DB` を返します。接続プール設定（`SetMaxOpenConns` など）は呼び出し元（`main.go`）で行います。

```go
// infrastructure/mysql/user_association_datasource.go
package mysql

import (
	_ "embed"

	"github.com/jmoiron/sqlx"
	"golang.org/x/xerrors"
)

// Open は MySQL DB を開いて返す。
// 接続プール設定（SetMaxOpenConns 等）は呼び出し元（main.go）で行うこと。
func Open(dsn string) (*sqlx.DB, error) {
	db, err := sqlx.Open("mysql", dsn)
	if err != nil {
		return nil, xerrors.Errorf("MySQL DB のオープンに失敗しました: %w", err)
	}
	return db, nil
}
```

### MySQL ドライバの blank import

`_ "github.com/go-sql-driver/mysql"` の blank import は `main.go` に置きます。
実装ファイルに置くと revive `blank-imports` 警告が発生します。テストファイルでは blank import が許容されるため、統合テストファイルに置きます。

```go
// main.go
package main

import (
    _ "github.com/go-sql-driver/mysql" // MySQL ドライバを database/sql に登録する
)
```

```go
// infrastructure/mysql/user_association_datasource_test.go
package mysql_test

import (
    _ "github.com/go-sql-driver/mysql" // MySQL ドライバをテスト実行時に登録する
)
```

### SQL ファイルの外出し（go:embed）

SQL クエリは `sql/` サブディレクトリに `.sql` ファイルとして外出しし、`//go:embed` で読み込みます。
SQL をコード内に文字列定数として埋め込まないことで、SQL の可読性・管理性を保ちます。

```
infrastructure/mysql/
├── sql/
│   ├── find_user_associations.sql          # LIMIT あり
│   └── find_all_user_associations.sql      # LIMIT なし
├── user_association_datasource.go
└── user_association_datasource_test.go
```

```go
//go:embed sql/find_all_user_associations.sql
var findAllQuery string

//go:embed sql/find_user_associations.sql
var findQuery string
```

### sqlx.NamedQueryContext + named parameter

フィルター条件には `sqlx.NamedQueryContext` と named parameter（`:param_name` 形式）を使用します。
未指定フィールドは `nil` を渡して SQL 側の `IS NULL` チェックに対応させます。

```go
func (s *UserAssociationDataSource) FindAll(ctx context.Context, filter types.SourceFilter) ([]model.UserAssociation, error) {
	params := map[string]any{
		"platform_type":    nil,
		"sp_uid":           nil,
		"platform_user_id": nil,
	}
	if platform, ok := filter.Platform().Value(); ok {
		params["platform_type"] = platform.String()
	}
	if spUID, ok := filter.SpUID().Value(); ok {
		params["sp_uid"] = spUID.Uint64()
	}
	if storeID, ok := filter.StoreID().Value(); ok {
		params["platform_user_id"] = storeID.String()
	}

	rows, err := sqlx.NamedQueryContext(ctx, s.db, findAllQuery, params)
	if err != nil {
		return nil, xerrors.Errorf("FindAll のクエリに失敗しました: %w", err)
	}
	defer func() { _ = rows.Close() }()

	records := make(dto.UserAssociationRecords, 0)
	for rows.Next() {
		var r dto.UserAssociationRecord
		if err := rows.StructScan(&r); err != nil {
			return nil, xerrors.Errorf("FindAll のスキャンに失敗しました: %w", err)
		}
		records = append(records, r)
	}
	if err := rows.Err(); err != nil {
		return nil, xerrors.Errorf("FindAll のイテレーションに失敗しました: %w", err)
	}

	return records.Aggregate()
}
```

### LIMIT の扱い: SQL ファイルを分ける

`LIMIT` の有無でクエリが変わる場合は、SQL ファイルを分けます。
**Go 側でのスライスカット（**`applyLimit` のような後処理）はアンチパターンです。

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

`LIMIT :limit` は `sqlx.Named` → `sqlx.Rebind` パターンで named parameter のまま使用できます。

```go
// LIMIT あり版の実行パターン
query, args, err := sqlx.Named(findQuery, params) // :param → ? に展開
if err != nil {
    return nil, xerrors.Errorf("クエリの展開に失敗しました: %w", err)
}
query = s.db.Rebind(query) // MySQL 用 ? に正規化
rows, err := s.db.QueryxContext(ctx, query, args...)
```

呼び出し側では `Limit` の有無でクエリを切り替えます：

```go
func (s *UserAssociationDataSource) FindAll(ctx context.Context, filter types.SourceFilter) ([]model.UserAssociation, error) {
	if _, ok := filter.Limit().Value(); ok {
		return s.findWithLimit(ctx, filter)
	}
	return s.findAll(ctx, filter)
}
```

### DTO + Aggregate パターン（MySQL）

DB の各行を表す `Record` 構造体と、そのスライス型 `Records` を定義します。
`Records` に `Aggregate()` メソッドを持たせ、ドメインモデルスライスへの一括変換を担わせます。
`toModel()` は非公開とし、`Aggregate()` からのみ呼び出します。

```go
// infrastructure/mysql/dto/user_association.go
package dto

import (
	"example.com/app/domain/model"
	"example.com/app/domain/types"
	"golang.org/x/xerrors"
)

// UserAssociationRecord は user_association テーブルの1行に対応する DB 読み取り用 DTO。
type UserAssociationRecord struct {
	SpUID          uint64 `db:"sp_uid"`
	PlatformUserID string `db:"platform_user_id"`
	PlatformType   string `db:"platform_type"`
}

// UserAssociationRecords は UserAssociationRecord のスライス。
type UserAssociationRecords []UserAssociationRecord

// Aggregate は DB レコード群をドメインモデルスライスに変換する。
func (rs UserAssociationRecords) Aggregate() ([]model.UserAssociation, error) {
	result := make([]model.UserAssociation, 0, len(rs))
	for _, r := range rs {
		assoc, err := r.toModel()
		if err != nil {
			return nil, xerrors.Errorf("sp_uid=%d のドメインモデル変換に失敗しました: %w", r.SpUID, err)
		}
		result = append(result, assoc)
	}
	return result, nil
}

// toModel は非公開。Aggregate() からのみ呼び出す。
func (r UserAssociationRecord) toModel() (model.UserAssociation, error) {
	storeID, err := types.StoreIDFrom(r.PlatformUserID)
	if err != nil {
		return model.UserAssociation{}, xerrors.Errorf("platform_user_id の復元に失敗しました: %w", err)
	}
	platform, err := types.PlatformFrom(r.PlatformType)
	if err != nil {
		return model.UserAssociation{}, xerrors.Errorf("platform_type の復元に失敗しました: %w", err)
	}
	return model.UserAssociationOf(types.SpUIDOf(r.SpUID), storeID, platform), nil
}
```

#### DTO のテスト

`toModel()` は非公開のため、`export_test.go` でテスト用に公開します（[テストコード規約 - export_test.go パターン](testing.md) 参照）。

```go
// infrastructure/mysql/dto/export_test.go
package dto

import "example.com/app/domain/model"

var ToModel = func(r UserAssociationRecord) (model.UserAssociation, error) {
	return r.toModel()
}
```

`Aggregate()` と `ToModel`（`toModel` のテスト用公開）をそれぞれ単体テストします。

```go
// infrastructure/mysql/dto/user_association_test.go
package dto_test

func TestUserAssociationRecord_ToModel(t *testing.T) {
    t.Parallel()
    tests := []struct {
        name    string
        sut     dto.UserAssociationRecord
        want    model.UserAssociation
        wantErr bool
    }{
        {
            name:    "ios レコードをドメインモデルに変換できる",
            sut:     dto.UserAssociationRecord{SpUID: 1, PlatformUserID: "token-ios-1", PlatformType: "ios"},
            wantErr: false,
        },
        {
            name:    "platform_user_id が空文字の場合はエラー",
            sut:     dto.UserAssociationRecord{SpUID: 1, PlatformUserID: "", PlatformType: "ios"},
            wantErr: true,
        },
        {
            name:    "platform_type が不正な値の場合はエラー",
            sut:     dto.UserAssociationRecord{SpUID: 1, PlatformUserID: "token-1", PlatformType: "invalid"},
            wantErr: true,
        },
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            got, err := dto.ToModel(tt.sut)
            if (err != nil) != tt.wantErr {
                t.Errorf("ToModel() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if tt.wantErr {
                return
            }
            opts := cmp.Options{
                cmp.AllowUnexported(zeroValuesRecursive(t, model.UserAssociation{})...),
            }
            if diff := cmp.Diff(tt.want, got, opts...); diff != "" {
                t.Errorf("ToModel() mismatch (-want +got):\n%s", diff)
            }
        })
    }
}
```

### インターフェース実装確認

コンパイル時にインターフェース実装を保証するため、以下のパターンを使用します。

```go
var _ model.SourceRepository = (*UserAssociationDataSource)(nil)
```

## 関連ドキュメント

* [アーキテクチャ設計規約](architecture.md) - レイヤー構成、依存性注入
* [エラーハンドリング規約](error-handling.md) - エラー処理、スタックトレース
* [テストコード規約](testing.md) - DTOのテスト、モック使用
* [ローカル開発環境規約](local-dev.md) - LocalStack、Initializerパターン

## 参考資料

* [Go slog package](https://pkg.go.dev/log/slog)
* [gRPC Interceptors](https://github.com/grpc/grpc-go/tree/master/examples/features/interceptor)
* [AWS SDK for Go v2](https://aws.github.io/aws-sdk-go-v2/docs/)
* [jmoiron/sqlx](https://github.com/jmoiron/sqlx)
* [go-sql-driver/mysql](https://github.com/go-sql-driver/mysql)
