# ドメインモデル設計規約

## 概要

ドメインモデルの設計規約です。ビジネスロジックを適切にモデル化します。

## エンティティと集約ルート

### 基本方針

* **エンティティは集約ルート** として設計する
* **すべてのフィールドを非公開（小文字開始）** にする
* **値の取得にはゲッターメソッド** を提供する
* **値の更新にはビジネスロジックを含むメソッド** を提供する
* **エンティティはポインターレシーバーのメソッドを持つ**（状態を持つため）

### 実装例

```go
// User はユーザーを表すエンティティ
type User struct {
	userID      types.UserID
	email       types.Optional[types.Email]
	displayName string
	userType    types.UserType
	createdAt   time.Time
	updatedAt   time.Time
}

// NewUser は新しい User を生成する
func NewUser(
	userID types.UserID,
	email types.Optional[types.Email],
	displayName string,
) *User {
	return &User{
		userID:      userID,
		email:       email,
		displayName: displayName,
		createdAt:   nowFunc(),
		updatedAt:   nowFunc(),
	}
}

// UserOf はフィールドと同等の情報から User を生成する
func UserOf(
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

// ゲッターメソッド（ポインターレシーバー）
func (u *User) UserID() types.UserID                    { return u.userID }
func (u *User) Email() types.Optional[types.Email]      { return u.email }
func (u *User) DisplayName() string                     { return u.displayName }
func (u *User) UserType() types.UserType                 { return u.userType }
func (u *User) CreatedAt() time.Time                     { return u.createdAt }
func (u *User) UpdatedAt() time.Time                     { return u.updatedAt }

// ビジネスロジックを含む更新メソッド（ポインターレシーバー）
func (u *User) UpdateProfile(
	email types.Optional[types.Email],
	displayName string,
) {
	u.email = email
	u.displayName = displayName
	u.updatedAt = nowFunc()
}
```

## 値オブジェクト（types）

### 基本方針

* **値オブジェクトは不変** である
* **値レシーバーのメソッドを持つ**（変更が発生しないため）

### 実装パターンの使い分け

値オブジェクトには2つの実装パターンがある。型の性質に応じて使い分ける。

#### パターン1: `type X string`（シンプルな文字列/数値型）

enum・識別子・ステータスなど、バリデーション以外に追加ロジックが不要な型に使用する。

```go
// Platform はプラットフォームを表す enum
type Platform string

const (
	PlatformIOS     Platform = "ios"
	PlatformAndroid Platform = "android"
	PlatformUnknown Platform = "unknown"
)

// PlatformFrom は文字列から Platform を変換して生成する
func PlatformFrom(s string) (Platform, error) {
	switch Platform(s) {
	case PlatformIOS, PlatformAndroid, PlatformUnknown:
		return Platform(s), nil
	default:
		return Platform(""), xerrors.Errorf("不明なプラットフォームです: %q", s)
	}
}

func (p Platform) String() string { return string(p) }
func (p Platform) IsKnown() bool  { return p == PlatformIOS || p == PlatformAndroid }
```

```go
// EndpointID はエンドポイントの識別子を表す値オブジェクト
type EndpointID string

// EndpointIDOf は文字列から EndpointID を生成する
func EndpointIDOf(value string) (EndpointID, error) {
	if value == "" {
		return EndpointID(""), xerrors.New("エンドポイントIDは空であってはなりません")
	}
	return EndpointID(value), nil
}

func (e EndpointID) String() string { return string(e) }
```

#### パターン2: `struct { ... }`（複合型・UUID を内包する型）

複数フィールドを持つ型、または UUID など型変換が複雑な型に使用する。

```go
// DeliveryID は配信リクエストの識別子を表す値オブジェクト
type DeliveryID struct {
	value uuid.UUID
}

// NewDeliveryID は新しい DeliveryID を生成する
func NewDeliveryID() DeliveryID {
	return DeliveryID{value: uuid.New()}
}

// DeliveryIDFrom は文字列から DeliveryID を変換して生成する
func DeliveryIDFrom(s string) (DeliveryID, error) {
	id, err := uuid.Parse(s)
	if err != nil {
		return DeliveryID{}, xerrors.Errorf("不正な DeliveryID フォーマット: %w", err)
	}
	return DeliveryID{value: id}, nil
}

func (d DeliveryID) String() string   { return d.value.String() }
func (d DeliveryID) UUID() uuid.UUID  { return d.value }
```

```go
// Content はメッセージの内容を表す複合値オブジェクト
type Content struct {
	title Optional[string]
	body  string
}

// ContentOf は Content を生成する
func ContentOf(title Optional[string], body string) Content {
	return Content{title: title, body: body}
}

func (c Content) Title() Optional[string] { return c.title }
func (c Content) Body() string            { return c.body }
```

### コンストラクタ命名規則

| 命名 | 用途 | 例 |
| --- | --- | --- |
| `New` | モデルの生成 | `NewUser(...)`, `NewDeliveryID()` |
| `Of` | モデル/ValueObject をフィールドと同等の情報から生成 | `UserOf(...)`, `ContentOf(...)`, `UserIDOf("abc")` |
| `From` | ValueObject を変換して生成（例: 文字列から Enum） | `DeliveryIDFrom(s)`, `PlatformFrom(s)` |

## レシーバーの使い分け

| 型 | レシーバー | 理由 |
| --- | --- | --- |
| **エンティティ（model）** | ポインターレシーバー `*User` | 状態を持つため、変更を反映させる |
| **値オブジェクト（types）** | 値レシーバー `Email` | 不変であり、状態を持たない |

**エンティティのメソッドはすべてポインターレシーバー**、**値オブジェクトのメソッドはすべて値レシーバー**で統一する。

## 属性の更新

* **更新時には必要な副作用（例: 更新日時の設定）** も同時に処理する
* **一部の属性のみを更新し、他の属性（例: 設定、作成日時）は維持** する

```go
func (u *User) UpdateProfile(
	email types.Optional[types.Email],
	displayName string,
) {
	u.email = email
	u.displayName = displayName
	u.updatedAt = nowFunc()
}
```

## テスト容易性

### 時刻の注入

```go
// nowFunc はテスト用に時刻を注入できるようにするための関数
var nowFunc = time.Now

// export_test.go に配置
func SetNowFunc(f func() time.Time) { nowFunc = f }
func ResetNowFunc()                 { nowFunc = time.Now }
```

## 複数実装戦略のファクトリパターン

リポジトリやサービスに複数の実装が存在する場合:

* **インターフェースはドメイン層（domain/model）に定義** する
* **実装はインフラ層（infrastructure）に配置** する
* **main.go で依存関係を組み立て** る

```go
// domain/model/user_repository.go
type UserRepository interface {
	FindByID(ctx context.Context, id types.UserID) (types.Optional[*User], error)
	Save(ctx context.Context, user *User) error
}
```

```go
// infrastructure/postgres/user_datasource.go
var _ model.UserRepository = (*UserDatasource)(nil)  // インターフェース実装の確認
```

## 関連ドキュメント

* [型システムとOptional型規約](type-system.md) - Optional型、ドメイン固有型
* [アーキテクチャ設計規約](architecture.md) - レイヤー構成、依存性注入
* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成

## 参考資料

* [Domain-Driven Design Reference](https://www.domainlanguage.com/ddd/reference/)
