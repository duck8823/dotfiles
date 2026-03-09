# アーキテクチャ設計規約

## 概要

アーキテクチャ設計のパターンと依存関係の規約です。レイヤードアーキテクチャを採用し、各層の責務と依存関係を明確にします。

## レイヤー構成

### 4層アーキテクチャ

```plaintext
┌─────────────────────────────────────┐
│  Presentation Layer                 │  ← HTTP/gRPC ハンドラ
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
* **Infrastructure → Domain への依存は インターフェース経由**
* **循環参照は禁止**

```plaintext
Presentation → Application → Domain ← Infrastructure
```

## パッケージ構成

### domain パッケージ

ビジネスロジックの中核を担います。

```go
// domain/model/user.go
package model

import (
	"time"

	"example.com/app/domain/types"
)

// User はユーザーを表すエンティティ
type User struct {
	userID      types.UserID
	email       types.Optional[types.Email]
	displayName string
	createdAt   time.Time
	updatedAt   time.Time
}

// NewUser は新しい User を作成する
func NewUser(
	userID types.UserID,
	email types.Optional[types.Email],
	displayName string,
	createdAt time.Time,
	updatedAt time.Time,
) *User {
	return &User{
		userID:      userID,
		email:       email,
		displayName: displayName,
		createdAt:   createdAt,
		updatedAt:   updatedAt,
	}
}

// ゲッターメソッド
func (u *User) UserID() types.UserID { return u.userID }
func (u *User) Email() types.Optional[types.Email] { return u.email }
func (u *User) DisplayName() string { return u.displayName }
```

### domain/types パッケージ

値オブジェクトを定義します。

```go
// domain/types/user_id.go
package types

type UserID struct {
	value string
}

func UserIDOf(value string) UserID {
	return UserID{value: value}
}

func (u UserID) String() string {
	return u.value
}
```

### リポジトリインターフェース

ドメイン層にインターフェースを定義し、インフラ層で実装します。

```go
// domain/model/user_repository.go
package model

import (
	"context"

	"example.com/app/domain/types"
)

// UserRepository はユーザーリポジトリのインターフェース
type UserRepository interface {
	FindByID(ctx context.Context, id types.UserID) (types.Optional[*User], error)
	Save(ctx context.Context, user *User) error
	Delete(ctx context.Context, id types.UserID) error
}
```

## application パッケージ

### ユースケース

ビジネスロジックのオーケストレーションを担当します。

```go
// application/usecase/user_usecase.go
package usecase

import (
	"context"

	"example.com/app/domain/model"
	"example.com/app/domain/types"
)

// UserUsecase はユーザー関連のユースケースインターフェース
type UserUsecase interface {
	GetUser(ctx context.Context, id types.UserID) (types.Optional[*model.User], error)
}

type userUsecase struct {
	userRepo model.UserRepository
}

// NewUserUsecase は新しい UserUsecase を作成する
func NewUserUsecase(userRepo model.UserRepository) UserUsecase {
	return &userUsecase{userRepo: userRepo}
}

// GetUser はユーザーを取得する
func (uc *userUsecase) GetUser(ctx context.Context, id types.UserID) (types.Optional[*model.User], error) {
	return uc.userRepo.FindByID(ctx, id)
}
```

### クエリサービス

読み取り専用の複雑なクエリを担当します。

```go
// application/queryservice/user_query_service.go
package queryservice

import (
	"context"

	"example.com/app/application/types"
)

// UserQueryService はユーザークエリサービスのインターフェース
type UserQueryService interface {
	ListUsers(ctx context.Context, limit int, offset int) ([]types.UserDTO, error)
	SearchUsers(ctx context.Context, query string) ([]types.UserDTO, error)
}
```

### application/types パッケージ

アプリケーション層固有の型を定義します。

**原則はクエリサービス用のDTO**ですが、ドメイン層で定義するには不適切かつアプリケーション層の複数ユースケースで共有される型（ユースケース固有エンティティ・進捗管理型など）も例外的にここに置きます。

```go
// application/types/user_dto.go
package types

import "time"

// UserDTO はユーザーの読み取り用DTO
type UserDTO struct {
	ID          string
	Email       *string
	DisplayName string
	CreatedAt   time.Time
}
```

## infrastructure パッケージ

### datasource パターン

リポジトリとクエリサービスを **単一の構造体（datasource）で実装** します。

```go
// infrastructure/postgres/user_datasource.go
package postgres

import (
	"context"
	"database/sql"

	"example.com/app/application/queryservice"
	apptypes "example.com/app/application/types"
	"example.com/app/domain/model"
	"example.com/app/domain/types"
)

// UserDatasource はユーザーのデータソース
// model.UserRepository と queryservice.UserQueryService を実装
type UserDatasource struct {
	db *sql.DB
}

// NewUserDatasource は新しい UserDatasource を作成する
func NewUserDatasource(db *sql.DB) *UserDatasource {
	return &UserDatasource{db: db}
}

// インターフェース実装の確認
var _ model.UserRepository = (*UserDatasource)(nil)
var _ queryservice.UserQueryService = (*UserDatasource)(nil)

// FindByID はユーザーをIDで取得する（Repository実装）
func (ds *UserDatasource) FindByID(ctx context.Context, id types.UserID) (types.Optional[*model.User], error) {
	// 実装
	return types.None[*model.User](), nil
}

// Save はユーザーを保存する（Repository実装）
func (ds *UserDatasource) Save(ctx context.Context, user *model.User) error {
	// 実装
	return nil
}

// Delete はユーザーを削除する（Repository実装）
func (ds *UserDatasource) Delete(ctx context.Context, id types.UserID) error {
	// 実装
	return nil
}

// ListUsers はユーザー一覧を取得する（QueryService実装）
func (ds *UserDatasource) ListUsers(ctx context.Context, limit int, offset int) ([]apptypes.UserDTO, error) {
	// 実装
	return nil, nil
}

// SearchUsers はユーザーを検索する（QueryService実装）
func (ds *UserDatasource) SearchUsers(ctx context.Context, query string) ([]apptypes.UserDTO, error) {
	// 実装
	return nil, nil
}
```

### datasource パターンの利点

* **単一責任**: 1つのエンティティに対するDB操作を1箇所に集約
* **コードの重複削減**: Repository と QueryService で共通のヘルパーを利用可能
* **テスト容易性**: 1つの構造体をモックすれば両方のインターフェースをテスト可能

## 依存性注入

### main.go での組み立て

```go
// main.go
package main

import (
	"database/sql"
	"log"
	"net/http"

	"example.com/app/application/usecase"
	_ "github.com/jackc/pgx/v5/stdlib"
	"example.com/app/infrastructure/postgres"
	"example.com/app/presentation/httphandler"
)

func main() {
	// データベース接続
	db, err := sql.Open("postgres", "postgres://...")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Datasource（Repository + QueryService）
	userDatasource := postgres.NewUserDatasource(db)

	// ユースケース
	userUsecase := usecase.NewUserUsecase(userDatasource)

	// ハンドラ
	userHandler := httphandler.NewUserHandler(userUsecase)

	// ルーティング
	mux := http.NewServeMux()
	mux.HandleFunc("/users", userHandler.ListUsers)
	mux.HandleFunc("/users/", userHandler.GetUser)

	// サーバー起動
	log.Println("Server starting on :8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
```

## 関連ドキュメント

* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成、Makefile
* [ドメインモデル設計規約](domain-model.md) - エンティティ、値オブジェクト、集約
* [型システムとOptional型規約](type-system.md) - Optional型、ドメイン固有型

## 参考資料

* [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
* [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture/)
