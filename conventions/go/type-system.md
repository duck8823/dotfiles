# 型システムとOptional型規約

## 概要

型安全性を高めるための型システム規約です。特に、NULL許容値を扱うための Optional 型の使用方法について定めています。

## Optional型の使用

### 基本方針

* **NULL許容値には** `Optional[T]` 型を使用する
* **ポインタ（**`*T`）を使わず、Optional型で明示的にNULL許容を表現する
* `IsSome()` / `IsNone()` / `Get()` **メソッドは存在しない**。`Value()` のみを使用する

### 値の取得方法

**Optional型の値を取得する際は、**`Value()` メソッドのみを使用します。このメソッドは値と存在有無を同時に返します。

```go
// 良い例: Value() を使用
if user, ok := optionalUser.Value(); ok {
	// user を使用した処理
	result := processUser(user)
	return result, nil
} else {
	// 値がない場合の処理
	return nil, errors.New("user not found")
}

// 悪い例: 存在しないメソッドを使用（コンパイルエラーになる）
if optionalUser.IsSome() { ... }  // NG: IsSome() は存在しない
if optionalUser.IsNone() { ... }  // NG: IsNone() は存在しない
user := optionalUser.Get()        // NG: Get() は存在しない
```

### Optional型の生成

```go
// 値がある場合
email := types.Some(types.EmailOf("user@example.com"))

// 値がない場合
email := types.None[types.Email]()
```

### `T` に渡す型の制約

`Optional[T]` の `T` には値型のみを使用する。ポインター型は渡さない。

```go
// 良い例: T に値型を使用
types.Optional[types.ULID]
types.Optional[types.Auth0UserID]
types.Optional[string]
types.Optional[time.Time]

// 悪い例: T にポインター型を使用（Some(nil) という不正状態が作れてしまう）
types.Optional[*types.ULID]   // NG
types.Optional[*model.User]   // NG（後述の例外を除く）
```

**例外: リポジトリの Get 系メソッド**

リポジトリでエンティティの存在有無を表す場合のみ `Optional[*Entity]` を使用する。
これは複数プロジェクトで確立した慣習である。

```go
// domain/model/user_repository.go
type UserRepository interface {
	// FindByID はユーザーをIDで取得する。
	// 存在しない場合は None を返す。error は DB エラー等の本当のエラーのみ。
	FindByID(ctx context.Context, id types.UserID) (types.Optional[*User], error)
}
```

呼び出し側:

```go
opt, err := repo.FindByID(ctx, userID)
if err != nil {
	return xerrors.Errorf("ユーザーの取得に失敗しました: %w", err)
}
user, ok := opt.Value()
if !ok {
	// 未存在
}
```

## ドメイン固有型

### 基本方針

* **プリミティブ型（**`string`, `int` など）を直接使わず、ドメイン固有型を定義する
* 型の誤用を防ぎ、コンパイル時に型安全性を担保する
* 実装パターンの詳細は [ドメインモデル設計規約](domain-model.md) を参照

```go
// シンプルな識別子・enum は type X string
type UserID string
func UserIDOf(value string) UserID { return UserID(value) }
func (u UserID) String() string    { return string(u) }

// UUID など複雑な型は struct { value T }
type DeliveryID struct{ value uuid.UUID }
func DeliveryIDFrom(s string) (DeliveryID, error) { ... }
```

## Sealed Interface パターン

インターフェースに非公開メソッドを追加し、外部パッケージからの実装を防ぐ。

```go
// domain/model/target.go
type Target interface {
	mustEmbedTarget()
}

type SegmentTarget struct{ segmentName string }
func (s SegmentTarget) mustEmbedTarget() {}

type MemberTarget struct{ memberIDs []string }
func (m MemberTarget) mustEmbedTarget() {}

// type switch では default ケースで未知の型を処理する
// Go コンパイラは type switch の網羅性を保証しないため、
// default でエラーを返すか、ワーニングログ + デフォルト値で対応する
func ProcessTarget(t Target) error {
	switch v := t.(type) {
	case SegmentTarget:
		// セグメントターゲットの処理
		return nil
	case MemberTarget:
		// 会員ターゲットの処理
		return nil
	default:
		// パターン1: エラーを返す
		return xerrors.Errorf("未知の Target 型です: %T", v)
		// パターン2: ワーニングログ + デフォルト値
		// slog.Warn("未知の Target 型です", "type", fmt.Sprintf("%T", v))
		// return nil
	}
}
```

## 関連ドキュメント

* [ドメインモデル設計規約](domain-model.md) - 値オブジェクトの実装パターン、コンストラクタ命名規則
* [テストコード規約](testing.md) - Optional型のテスト

## 参考資料

* [Effective Go - The comma ok idiom](https://go.dev/doc/effective_go#maps)
