# 命名規則

## 概要

命名規則です。一貫性のある命名により、コードの可読性と保守性を向上させます。

## パッケージ命名

### types パッケージの使用

* **値オブジェクト（domain/types）とDTO（application/types）を格納するパッケージとして** `types` を使用する
* Go標準ライブラリでも使われている命名であり、プロジェクト内で一貫して使用する
* revive の "var-naming: avoid meaningless package names" 警告を抑制する

### golangci-lint 設定

```yaml
linters:
  exclusions:
    rules:
      # 値オブジェクト（domain/types）とDTO（application/types）を格納するパッケージとして types を使用
      # Go標準ライブラリでも使われている命名であり、プロジェクト内で一貫して使用するため許可
      - path: ".*/types/[^/]+\\.go"
        text: "var-naming: avoid meaningless package names"
        linters:
          - revive
```

## 一般的な命名規則

### 基本方針

* Go標準の命名規則に従う
* **パッケージ名: 小文字、単語区切りなし（例:** `model`**,** `usecase`）
* **型名: PascalCase（例:** `User`**,** `UserID`）
* **関数・メソッド名: exported は PascalCase、unexported は camelCase（例:** `NewUser`**,** `getUser`）
* **定数: PascalCase または UPPER_SNAKE_CASE（例:** `DefaultTimeout`）

## ドメインモデル特有の命名

### ファクトリ関数

* **モデルの生成:** `New<Type>`**（例:** `NewUser`**,** `NewDeliveryID`）
* **フィールドと同等の情報から生成:** `<Type>Of`**（例:** `UserOf`**,** `ContentOf`**,** `UserIDOf`）
* **変換して生成（例: 文字列から Enum）:** `<Type>From`**（例:** `DeliveryIDFrom`**,** `PlatformFrom`）

詳細は [ドメインモデル設計規約](domain-model.md) のコンストラクタ命名規則を参照。

### 実装例

```go
// モデルの生成
func NewUser(
	userID types.UserID,
	email types.Optional[types.Email],
	displayName string,
) *User {
	// ...
}

// フィールドと同等の情報から生成
func UserOf(
	userID types.UserID,
	email types.Optional[types.Email],
	displayName string,
	createdAt time.Time,
	updatedAt time.Time,
) *User {
	// ...
}

// 値オブジェクトをフィールドと同等の情報から生成
func UserIDOf(value string) UserID {
	return UserID(value)
}

// 値オブジェクトを変換して生成
func PlatformFrom(s string) (Platform, error) {
	// ...
}
```

## 関連ドキュメント

* [ドメインモデル設計規約](domain-model.md) - エンティティ、値オブジェクト
* [型システムとOptional型規約](type-system.md) - ドメイン固有型
* [Linter設定](linter.md) - golangci-lint設定

## 参考資料

* [Effective Go - Names](https://go.dev/doc/effective_go#names)
* [Go Code Review Comments - Package Names](https://go.dev/wiki/CodeReviewComments#package-names)
