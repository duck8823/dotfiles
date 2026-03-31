# テストコード規約

## 概要

テストコードの記述規約です。テストの構造化、命名規則、モックの使用方法について定めています。

## テストファイルの配置

### 基本方針

* **テストファイルは対象ファイルと同じディレクトリに配置** する
* **ファイル名は** `*_test.go` とする
* **パッケージは原則** `_test` サフィックスを付ける（外部テスト・ブラックボックステスト）
* 内部ロジックをテストしたい場合は `export_test.go` で公開する

### ディレクトリ構成例

```plaintext
domain/
├── model/
│   ├── user.go
│   ├── user_test.go      # user.go のテスト（package model_test）
│   ├── user_repository.go
│   ├── mock/             # モック（パッケージ内に配置）
│   │   └── user_repository_mock.go
│   └── package.go
└── types/
    ├── user_id.go
    ├── user_id_test.go   # user_id.go のテスト（package types_test）
    └── package.go

infrastructure/
└── postgres/
    ├── user_datasource.go
    ├── user_datasource_test.go  # package postgres_test
    ├── export_test.go           # 非公開関数をテスト用に公開
    └── package.go
```

### 外部テスト（`_test` サフィックス）

* **公開（exported）APIのみをテストする**
* **パッケージの外部からの視点でテスト**
* **パッケージ名に** `_test` サフィックスを付ける

```go
// domain/types/user_id_test.go
package types_test  // _test サフィックス

import (
    "testing"
    "example.com/app/domain/types"
)

func TestUserIDOf(t *testing.T) {
    // 公開APIのみをテストする
}
```

### export_test.go パターン

非公開関数をテストしたい場合は `export_test.go` に公開用変数を定義します。

```go
// infrastructure/postgres/export_test.go
package postgres  // _test サフィックスなし（同一パッケージ）

// テスト用に非公開関数をエクスポート
var (
    ToUserRow  = toUserRow
    FromUserRow = fromUserRow
)
```

```go
// infrastructure/postgres/user_datasource_test.go
package postgres_test

import "example.com/app/infrastructure/postgres"

func TestToUserRow(t *testing.T) {
    got := postgres.ToUserRow(user)
    // ...
}
```

#### DTO の非公開メソッドを export_test.go で公開する

DTO の変換メソッド（`toModel()` など）が非公開の場合、`export_test.go` で公開します。

```go
// infrastructure/mysql/dto/export_test.go
package dto

import "example.com/app/domain/model"

// ToModel はテスト用に非公開メソッド toModel を公開する。
var ToModel = func(r UserAssociationRecord) (model.UserAssociation, error) {
    return r.toModel()
}
```

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
            want:    model.UserAssociationOf(types.SpUIDOf(1), mustStoreID("token-ios-1"), types.PlatformIOS),
            wantErr: false,
        },
        {
            name:    "platform_user_id が空文字の場合はエラー",
            sut:     dto.UserAssociationRecord{SpUID: 1, PlatformUserID: "", PlatformType: "ios"},
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
            // ...
        })
    }
}
```

## 並列実行

### 基本方針

* `t.Parallel()` は推奨（外部I/Oを伴うテストでは除外可）
* テスト関数とサブテスト（`t.Run` 内）の両方で呼び出す

> **Note:** DB 統合テストなど同一リソースを共有するテストでは `t.Parallel()` を使用しない。

### 実装例

```go
func TestXxx_Method(t *testing.T) {
    t.Parallel()  // テスト関数レベル

    tests := []struct {
        name string
        // ...
    }{...}

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()  // サブテストレベル
            // ...
        })
    }
}
```

## テスト関数の命名

### 基本方針

* **Test + 対象関数名** の形式
* テストケース名（`name` フィールド）で条件を日本語で表現する

### 命名例

```go
func TestUserUseCase_GetUser(t *testing.T) {}
func TestUserIDOf(t *testing.T) {}
func TestUser_UpdateProfile(t *testing.T) {}
```

## テーブル駆動テスト

### 基本方針

* **複数のテストケースを 1 つのテスト関数でまとめる**
* **テストケースには 名前（**`name`）を必ず付ける
* **テストを跨いだ共通変数は作らない**（`var opts = ...` などパッケージレベルの共有も禁止）
* `t.Run` でサブテストとして実行する

### テーブル構造の使い分け

| パターン | フィールド構成 | 用途 |
| --- | --- | --- |
| コンストラクタテスト | `args` + `want` + `wantErr` | コンストラクタ・変換関数のテスト |
| ゲッター/メソッドテスト | `sut` + `want` + `wantErr` | 値オブジェクト・メソッドのテスト |
| エンティティメソッドテスト | `fields` + `args` + `want` | モック・依存性注入を使うテスト |

### コンストラクタテスト（args + want パターン）

```go
func TestRunIDFrom(t *testing.T) {
    t.Parallel()
    type args struct {
        value string
    }
    tests := []struct {
        name    string
        args    args
        want    types.RunID
        wantErr bool
    }{
        {
            name:    "有効なUUIDv4を受け付ける",
            args:    args{value: "00000000-0000-4000-8000-000000000001"},
            want:    must(types.RunIDFrom("00000000-0000-4000-8000-000000000001")),
            wantErr: false,
        },
        {
            name:    "空文字はエラー",
            args:    args{value: ""},
            wantErr: true,
        },
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()

            // when
            got, err := types.RunIDFrom(tt.args.value)

            // then
            if (err != nil) != tt.wantErr {
                t.Errorf("RunIDFrom() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if tt.wantErr {
                return
            }
            if diff := cmp.Diff(tt.want, got); diff != "" {
                t.Errorf("RunIDFrom() mismatch (-want +got):\n%s", diff)
            }
        })
    }
}
```

### ゲッター/メソッドテスト（sut パターン）

```go
func TestPlatform_IsKnown(t *testing.T) {
    t.Parallel()
    tests := []struct {
        name string
        sut  types.Platform
        want bool
    }{
        {name: "iOS は既知", sut: types.PlatformIOS, want: true},
        {name: "Android は既知", sut: types.PlatformAndroid, want: true},
        {name: "unknown は未知", sut: types.PlatformUnknown, want: false},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()

            // when
            got := tt.sut.IsKnown()

            // then
            if diff := cmp.Diff(tt.want, got); diff != "" {
                t.Errorf("IsKnown() mismatch (-want +got):\n%s", diff)
            }
        })
    }
}
```

### エンティティメソッドテスト（fields + args パターン）

```go
func TestUserUseCase_GetUser(t *testing.T) {
    t.Parallel()

    type fields struct {
        userRepo func(ctrl *gomock.Controller) model.UserRepository
    }
    type args struct {
        ctx    context.Context
        userID types.UserID
    }
    tests := []struct {
        name    string
        fields  fields
        args    args
        want    types.Optional[*model.User]
        wantErr bool
    }{
        {
            name: "ユーザーを取得できる",
            fields: fields{
                userRepo: func(ctrl *gomock.Controller) model.UserRepository {
                    m := mock.NewMockUserRepository(ctrl)
                    m.EXPECT().
                        FindByID(gomock.Any(), types.UserIDOf("user-123")).
                        Return(types.Some(expectedUser), nil)
                    return m
                },
            },
            args:    args{ctx: context.Background(), userID: types.UserIDOf("user-123")},
            want:    types.Some(expectedUser),
            wantErr: false,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()

            // given
            ctrl := gomock.NewController(t)
            userRepo := tt.fields.userRepo(ctrl)

            // and
            sut := usecase.NewUserUsecase(userRepo)

            // when
            got, err := sut.GetUser(tt.args.ctx, tt.args.userID)

            // then
            if (err != nil) != tt.wantErr {
                t.Errorf("GetUser() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if diff := cmp.Diff(tt.want, got); diff != "" {
                t.Errorf("GetUser() mismatch (-want +got):\n%s", diff)
            }
        })
    }
}
```

### `// given / // and / // when / // then` コメント

`// given` セクション内で意味的に分かれる箇所を `// and` で区切ります。

```go
// given — テスト前提条件（モック、フィクスチャなど）
ctrl := gomock.NewController(t)
repo := tt.fields.userRepo(ctrl)

// and — テスト対象の構築
sut := usecase.NewUserUseCase(repo)

// when — テスト対象の実行
got, err := sut.GetUser(tt.args.ctx, tt.args.userID)

// then — 検証
```

## アサーション

### 基本方針

* **標準ライブラリの** `testing` パッケージを使用する
* **外部アサーションライブラリ（testify など）は使用しない**
* **構造体の比較には** `cmp.Diff` を使用する
* `cmp.Options` は各テスト内で構成する（パッケージレベルの共有変数にしない）

### 非公開フィールドを持つ型の比較

非公開フィールドを持つ構造体を `cmp.Diff` で比較する際は `cmp.AllowUnexported` を使用します。
型を個別に列挙する代わりに、`zeroValuesRecursive` / `fieldTypeRecursive` ヘルパーを使って再帰的に収集します。

```go
// ${package}_test.go（パッケージ内で共有）
// zeroValuesRecursive は構造体を再帰的に探索してフィールドのゼロ値一覧を返す。
// cmp.AllowUnexported に渡すことで非公開フィールドを持つ型を個別列挙せず比較できる。
func zeroValuesRecursive(t *testing.T, v any) []any {
    t.Helper()
    values := make([]any, 0)
    for _, typ := range fieldTypeRecursive(t, reflect.TypeOf(v), 0) {
        values = append(values, reflect.Zero(typ).Interface())
    }
    return values
}

func fieldTypeRecursive(t *testing.T, rt reflect.Type, depth int) []reflect.Type {
    t.Helper()
    if depth > 20 {
        return []reflect.Type{}
    }
    values := make([]reflect.Type, 0)
    switch rt.Kind() {
    case reflect.Ptr, reflect.Array, reflect.Slice:
        values = append(values, fieldTypeRecursive(t, rt.Elem(), depth+1)...)
    case reflect.Struct:
        values = append(values, rt)
        for i := 0; i < rt.NumField(); i++ {
            f := rt.Field(i)
            switch f.Type.Kind() {
            case reflect.Ptr, reflect.Array, reflect.Slice, reflect.Struct:
                values = append(values, fieldTypeRecursive(t, f.Type, depth+1)...)
            }
        }
    }
    return values
}
```

使用例：

```go
func TestNewProgress(t *testing.T) {
    // ...
    opts := cmp.Options{
        cmp.AllowUnexported(zeroValuesRecursive(t, apptypes.Progress{})...),
        cmpopts.IgnoreFields(apptypes.Progress{}, "updatedAt"),
    }
    if diff := cmp.Diff(tt.want, got, opts...); diff != "" {
        t.Errorf("NewProgress() mismatch (-want +got):\n%s", diff)
    }
}
```

#### 外部テストパッケージ（`_test`）での注意

外部テストパッケージ（`package foo_test`）では非公開フィールドに直接アクセスできません。`cmp.AllowUnexported` を使うとパニックは回避できますが、比較対象の期待値を組み立てる際に非公開フィールドを設定できない問題が残ります。対処法は以下のいずれかです：

* **エンティティ側に `Equal` メソッドを定義** して比較に使う
* **内部テストパッケージ（`package foo`）で書く** ことで非公開フィールドにアクセス可能にする
* **公開ゲッターで個別に検証** する（フィールド数が少ない場合）

シンプルな型（非公開フィールドが少ない場合）は直接列挙しても構いません：

```go
opts := cmp.Options{
    cmp.AllowUnexported(types.Content{}),
    cmp.AllowUnexported(types.Optional[string]{}),
}
```

## テストヘルパー

### 基本方針

* `must[T any]` ヘルパーは各パッケージの `${package}_test.go` に 1 箇所定義してパッケージ内で共有する
* **ヘルパー関数は** `t.Helper()` を呼び出す

### must ヘルパー

```go
// domain/types/types_test.go
package types_test

// must はエラーが発生しないことが期待される処理用のヘルパー。
// テストコード内でエラーハンドリングを簡潔にするために使用する。
func must[T any](v T, err error) T {
    if err != nil {
        panic(err)
    }
    return v
}
```

使用例：

```go
tests := []struct { ... }{
    {
        name: "...",
        args: args{
            storeID: must(types.StoreIDFrom("txn_test")),
            runID:   must(types.RunIDFrom("00000000-0000-4000-8000-000000000001")),
        },
    },
}
```

### アンチパターン: mustXxx 系ヘルパー

`mustFilter`、`mustAssoc`、`mustWithLimit`、`mustStoreID` のように、**特定の型に特化した** `mustXxx` 関数を個別定義してはいけません。

```go
// NG: 型特化の mustXxx ヘルパー
func mustFilter(t *testing.T, opts ...types.SourceFilterOption) types.SourceFilter {
    t.Helper()
    f, err := types.SourceFilterOf(opts...)
    if err != nil {
        t.Fatalf("SourceFilterOf: %+v", err)
    }
    return f
}
```

汎用の `must[T]` を使ってテーブル定義時にインライン展開することで、ヘルパーの増殖を防ぎます。

```go
// OK: 汎用 must[T] を使う
tests := []struct { ... }{
    {
        args: args{
            filter: must(types.SourceFilterOf(types.WithPlatform(types.PlatformIOS))),
        },
        want: []model.UserAssociation{
            model.UserAssociationOf(
                types.SpUIDOf(1),
                must(types.StoreIDFrom("token-ios-1")),
                types.PlatformIOS,
            ),
        },
    },
}
```

### ptr ヘルパー

```go
// ptr は値へのポインタを返す汎用ヘルパー
func ptr[T any](v T) *T {
    return &v
}
```

## モックの使用

### 基本方針

* **モックは** `go.uber.org/mock/mockgen` で生成する
* **モックファイルは対象パッケージ内の** `mock/` サブディレクトリに配置する
* `go generate` でモックを自動生成する

### go generate の設定

```go
// domain/model/user_repository.go
package model

//go:generate go tool mockgen -source=$GOFILE -destination=mock/user_repository_mock.go -package=mock

type UserRepository interface {
    FindByID(ctx context.Context, id types.UserID) (types.Optional[*User], error)
    Save(ctx context.Context, user *User) error
}
```

## インフラ層テスト: fixtures + wantState パターン

データベース統合テストでは、**fixtures**（テストデータの投入）と **wantState**（実行後の期待状態）をテストテーブルに定義し、**actualState** で DB から直接 Row を取得して比較します。

### Row 構造体と DataSet

```go
type deliveryRow struct {
    ID     uuid.UUID `db:"id"`
    Title  string    `db:"title"`
    Status string    `db:"status"`
}

type dataSet struct {
    Deliveries []deliveryRow
    Targets    []targetRow
}
```

### 書き込み系テスト（fixtures + wantState + actualState）

```go
func TestDeliveryRepository_Save(t *testing.T) {
    db, rollback := initTestDB(t, testDatasource)
    defer rollback()

    tests := []struct {
        name      string
        fixtures  dataSet
        args      func() *model.Delivery
        wantState dataSet
        wantErr   bool
    }{
        {
            name:     "データを保存できる",
            fixtures: dataSet{},
            args:     func() *model.Delivery { return model.NewDelivery(...) },
            wantState: dataSet{
                Deliveries: []deliveryRow{{Title: "テスト", Status: "PENDING"}},
            },
            wantErr: false,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            truncateTables(t, db)
            ctx := context.Background()

            // given
            if err := fixture(t, db, tt.fixtures); err != nil {
                t.Fatalf("fixture error = %v", err)
            }

            // when
            err := repo.Save(ctx, tt.args())

            // then
            if (err != nil) != tt.wantErr {
                t.Fatalf("Save() error = %v, wantErr %v", err, tt.wantErr)
            }
            if tt.wantErr {
                return
            }
            gotState := actualState(t, db)
            if diff := cmp.Diff(tt.wantState, gotState, dataSetCmpOpts()...); diff != "" {
                t.Errorf("state mismatch (-want +got):\n%s", diff)
            }
        })
    }
}
```

### 読み取り専用テスト（fixtures + want パターン）

読み取り専用メソッド（`FindAll` など）のテストでは、DB 状態を検証する `wantState` は不要です。
`fixtures` でデータを投入し、戻り値を `want []model.XXX` と直接比較します。

```go
func TestUserAssociationDataSource_FindAll(t *testing.T) {
    type fixtures = []dto.UserAssociationRecord
    type args struct {
        ctx    context.Context
        filter types.SourceFilter
    }
    tests := []struct {
        name     string
        fixtures fixtures
        args     args
        want     []model.UserAssociation
        wantErr  bool
    }{
        {
            name: "フィルターなしで全件を昇順で取得できる",
            fixtures: fixtures{
                {SpUID: 1, PlatformUserID: "token-ios-1", PlatformType: "ios"},
                {SpUID: 2, PlatformUserID: "token-android-1", PlatformType: "android"},
            },
            args: args{
                ctx:    context.Background(),
                filter: must(types.SourceFilterOf()),
            },
            want: []model.UserAssociation{
                model.UserAssociationOf(
                    types.SpUIDOf(1),
                    must(types.StoreIDFrom("token-ios-1")),
                    types.PlatformIOS,
                ),
                model.UserAssociationOf(
                    types.SpUIDOf(2),
                    must(types.StoreIDFrom("token-android-1")),
                    types.PlatformAndroid,
                ),
            },
        },
        {
            name:     "条件に一致するレコードがない場合は空スライスを返す",
            fixtures: fixtures{},
            args: args{
                ctx:    context.Background(),
                filter: must(types.SourceFilterOf(types.WithPlatform(types.PlatformAndroid))),
            },
            want: []model.UserAssociation{},
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // given
            opts := cmp.Options{
                cmp.AllowUnexported(zeroValuesRecursive(t, model.UserAssociation{})...),
            }

            // and: DB 接続・TRUNCATE
            db := initTestDB(t, dsn)
            defer func() { _ = db.Close() }()

            // and: fixture 投入
            if len(tt.fixtures) > 0 {
                if _, err := db.NamedExec(insertQuery, tt.fixtures); err != nil {
                    t.Fatalf("テストデータの投入に失敗しました: %+v", err)
                }
            }

            // and: SUT 構築
            sut := mysql.NewUserAssociationDataSource(db)

            // when
            got, err := sut.FindAll(tt.args.ctx, tt.args.filter)

            // then
            if (err != nil) != tt.wantErr {
                t.Errorf("FindAll() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if !cmp.Equal(got, tt.want, opts...) {
                t.Errorf("FindAll() diff = %+v", cmp.Diff(tt.want, got, opts...))
            }
        })
    }
}
```

### initTestDB ヘルパー（MySQL）

MySQL 統合テストでは、各テストケース実行前に `TRUNCATE TABLE` でテーブルをリセットします。
`initTestDB` ヘルパーで接続確認と TRUNCATE をまとめて行います。

```go
func initTestDB(t *testing.T, dsn string) (*sqlx.DB, func()) {
    t.Helper()
    db, err := mysql.Open(dsn)
    if err != nil {
        t.Fatalf("DB のオープンに失敗しました: %+v", err)
    }
    if err := db.Ping(); err != nil {
        t.Fatalf("DB への接続に失敗しました: %+v", err)
    }
    if _, err := db.Exec("TRUNCATE TABLE user_association"); err != nil {
        t.Fatalf("TRUNCATE に失敗しました: %+v", err)
    }
    cleanup := func() {
        db.Close()
    }
    return db, cleanup
}
```

接続先 DSN は環境変数で切り替え、未設定時はデフォルト値を使います。

```go
ds, ok := os.LookupEnv("TEST_DATASOURCE")
if !ok {
    ds = "root:@tcp(127.0.0.1:13306)/testdb"
}
db := initTestDB(t, ds)
```

### fixtures の型エイリアス

fixture データには DTO の Row 構造体のスライスを型エイリアスとして定義します。
これにより、テストテーブルのフィールド型定義を簡潔に保ちます。

```go
type fixtures = []dto.UserAssociationRecord
```

`db.NamedExec` で fixture を一括 INSERT する際は `//go:embed` で SQL を外出しします。
`//go:embed` ディレクティブはテストファイル本体に直接記述します（別ファイルへの分離はしない）。

```go
// user_association_datasource_test.go
import _ "embed"

//go:embed testdata/insert_user_association.sql
var insertUserAssociationQuery string

// INSERT INTO user_association (sp_uid, platform_user_id, platform_type)
// VALUES (:sp_uid, :platform_user_id, :platform_type)

if _, err := db.NamedExec(insertUserAssociationQuery, tt.fixtures); err != nil {
    t.Fatalf("テストデータの投入に失敗しました: %+v", err)
}
```

### 注意点

* DB 統合テストでは `t.Parallel()` を使用しない（同一 DB テーブルを共有するため）
* `// given`, `// and`, `// when`, `// then` コメントを使用する
* DB が自動設定するフィールド（`CreatedAt`, `UpdatedAt` など）は `cmpopts.IgnoreFields` で比較から除外する

## 時刻のテスト

```go
// プロダクションコード
var nowFunc = time.Now

// テストコード（export_test.go）
func SetNowFunc(f func() time.Time) { nowFunc = f }
func ResetNowFunc()                 { nowFunc = time.Now }

// テスト
func TestUser_UpdateProfile_SetsUpdatedAt(t *testing.T) {
    fixedTime := time.Date(2024, 1, 1, 12, 0, 0, 0, time.UTC)
    model.SetNowFunc(func() time.Time { return fixedTime })
    t.Cleanup(model.ResetNowFunc)
    // ...
}
```

## E2Eテスト

### 基本方針

* **runn を使用して YAML ベースの E2E テストを記述** する
* **テストファイルは** `test/e2e/` ディレクトリに配置する
* **機能単位でファイルを分割** する

### Makefile でのテスト実行

```makefile
e2e/test: ## E2Eテストを実行
	@GOLANG_PROTOBUF_REGISTRATION_CONFLICT=warn go tool runn run test/e2e/**/*.yaml --scopes run:exec --concurrent $$(nproc 2>/dev/null || sysctl -n hw.ncpu)
```

## 関連ドキュメント

* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成、モックの配置
* [型システムとOptional型規約](type-system.md) - Optional型のテスト
* [HTTPハンドラー・プレゼンテーション層規約](http-handler.md) - ハンドラーのテスト
* [ローカル開発環境規約](local-dev.md) - LocalStack、E2Eテスト環境
* [インフラストラクチャパターン規約](infrastructure.md) - MySQL/sqlx パターン

## 参考資料

* [Go Testing](https://pkg.go.dev/testing)
* [Table Driven Tests](https://go.dev/wiki/TableDrivenTests)
* [uber-go/mock](https://github.com/uber-go/mock)
* [google/go-cmp](https://github.com/google/go-cmp)
* [runn](https://github.com/k1LoW/runn)
