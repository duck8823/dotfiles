# HTTPハンドラー・プレゼンテーション層規約

## 概要

HTTPハンドラー（プレゼンテーション層）の実装規約です。OpenAPI仕様に基づくAPI実装と、Google AIP（API Improvement Proposals）に準拠した設計パターンを定めています。

## 基本方針

* **OpenAPI仕様を single source of truth とする**
* **Google AIP ガイドラインに準拠した API 設計**
* **自動生成コードは編集しない**
* **リクエスト/レスポンス変換ロジックは専用ファイルに分離**
* **ドメイン層への依存は型のみ、具体的な実装は依存しない**

## ディレクトリ構成

```plaintext
presentation/
├── httphandler/
│   ├── user_handler.go           # ハンドラー実装
│   ├── request.go                # リクエスト→ドメイン型変換
│   ├── response.go               # ドメイン型→レスポンス変換
│   ├── user_handler_test.go
│   ├── request_test.go
│   ├── response_test.go
│   └── export_test.go            # テスト用エクスポート（必要に応じて）
└── cli/
    └── ...
```

## OpenAPI定義のベストプラクティス（AIP準拠）

### リソース指向設計（AIP-121, AIP-122）

**基本方針:**

* **リソースは名詞の複数形**（例: `users`, `articles`, `notifications`）
* **リソースIDはパスパラメータ**（例: `/v1/users/{userId}`）
* **コレクションとリソースの階層構造**

**OpenAPI定義例:**

```yaml
paths:
  /v1/users:
    get:
      operationId: listUsers
      summary: ユーザー一覧取得
    post:
      operationId: createUser
      summary: ユーザー作成

  /v1/users/{userId}:
    get:
      operationId: getUser
      summary: ユーザー取得
    put:
      operationId: updateUser
      summary: ユーザー更新
    delete:
      operationId: deleteUser
      summary: ユーザー削除

  /v1/users/{userId}/articles:
    get:
      operationId: listUserArticles
      summary: ユーザーの記事一覧取得
```

### 標準メソッド（AIP-131-135）

**基本方針:**

* **List（一覧取得）:** `GET /v1/resources`
* **Get（単一取得）:** `GET /v1/resources/{id}`
* **Create（作成）:** `POST /v1/resources`
* **Update（更新）:** `PUT /v1/resources/{id}` または `PATCH /v1/resources/{id}`
* **Delete（削除）:** `DELETE /v1/resources/{id}`

**HTTPステータスコード:**

| メソッド | 成功時 | 説明 |
| --- | --- | --- |
| List | 200 OK | リソース一覧を返す |
| Get | 200 OK | リソースを返す |
| Create | 201 Created | 作成されたリソースを返す |
| Update | 200 OK | 更新されたリソースを返す |
| Delete | 204 No Content | レスポンスボディなし |

### カスタムメソッド（AIP-136）

**基本方針:**

* **標準メソッドで表現できない操作はカスタムメソッドを使用**
* **形式:** `POST /v1/resources/{id}:customVerb`
* **動詞は小文字のキャメルケース**

**一般的なカスタムメソッド:**

| 動詞 | 用途 | 例 |
| --- | --- | --- |
| `:cancel` | 処理のキャンセル | `POST /v1/orders/{orderId}:cancel` |
| `:activate` | リソースの有効化 | `POST /v1/users/{userId}:activate` |
| `:deactivate` | リソースの無効化 | `POST /v1/users/{userId}:deactivate` |
| `:enable` | 機能の有効化 | `POST /v1/endpoints/{id}:enable` |
| `:disable` | 機能の無効化 | `POST /v1/endpoints/{id}:disable` |
| `:move` | リソースの移動 | `POST /v1/files/{fileId}:move` |
| `:search` | 複雑な検索 | `POST /v1/articles:search` |
| `:batch` | バッチ処理 | `POST /v1/users:batchGet` |

**OpenAPI定義例:**

```yaml
paths:
  /v1/endpoints/{id}:enable:
    post:
      operationId: enableEndpoint
      summary: エンドポイントを有効化
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - type
              properties:
                type:
                  type: string
                  enum: [type_a, type_b, type_c]
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Endpoint'
```

**実装例:**

```go
// POST /v1/endpoints/{id}:enable
func (h *EndpointHandler) Enable(
    ctx context.Context,
    request openapi.EnableEndpointRequestObject,
) (openapi.EnableEndpointResponseObject, error) {
    if request.Body == nil {
        return openapi.EnableEndpoint400JSONResponse{
            Code:    ptr("INVALID_REQUEST"),
            Message: ptr("リクエストボディが必要です"),
        }, nil
    }

    endpointID := types.EndpointIDOf(request.Id)
    endpointType := types.EndpointType(request.Body.Type)

    // 種別の妥当性チェック
    if !endpointType.IsValid() {
        return openapi.EnableEndpoint400JSONResponse{
            Code:    ptr("VALIDATION_ERROR"),
            Message: ptr(fmt.Sprintf("無効な種別です: %s", endpointType)),
        }, nil
    }

    endpoint, err := h.endpointUsecase.Enable(ctx, endpointID, endpointType)
    if err != nil {
        return nil, xerrors.Errorf("有効化に失敗しました: %w", err)
    }

    response := toEndpointResponse(endpoint)
    return openapi.EnableEndpoint200JSONResponse(response), nil
}
```

### フィールド命名規則（AIP-140, AIP-142）

**基本方針:**

* **フィールド名は小文字のスネークケース**（例: `user_id`, `created_at`, `display_name`）
* **時刻フィールドは** `*_time` または `*_at` サフィックス（例: `create_time`, `created_at`）
* **ブール値は** `is_*`, `has_*`, `can_*` プレフィックス（例: `is_active`, `has_permission`）
* **列挙型（enum）は小文字のスネークケース**（例: `regular`, `premium`, `ios`, `android`）

**OpenAPI定義例:**

```yaml
components:
  schemas:
    User:
      type: object
      properties:
        user_id:
          type: string
          description: ユーザーID
        email:
          type: string
          format: email
          description: メールアドレス
        display_name:
          type: string
          description: 表示名
        is_active:
          type: boolean
          description: 有効かどうか
        user_type:
          $ref: '#/components/schemas/UserType'
        created_at:
          type: string
          format: date-time
          description: 作成日時
        updated_at:
          type: string
          format: date-time
          description: 更新日時

    UserType:
      type: string
      enum:
        - regular
        - premium
        - trial
```

### ページネーション（AIP-158）

**基本方針:**

* **ページネーションには** `page_size` と `page_token` を使用
* **レスポンスには** `next_page_token` を含める
* **最大ページサイズを定義**（例: 100件）

**OpenAPI定義例:**

```yaml
paths:
  /v1/users:
    get:
      operationId: listUsers
      parameters:
        - name: page_size
          in: query
          schema:
            type: integer
            minimum: 1
            maximum: 100
            default: 25
          description: 1ページあたりの件数
        - name: page_token
          in: query
          schema:
            type: string
          description: ページネーショントークン
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  users:
                    type: array
                    items:
                      $ref: '#/components/schemas/User'
                  next_page_token:
                    type: string
                    description: 次のページのトークン（最終ページの場合は空）
```

### エラーレスポンス（AIP-193）

**基本方針:**

* **エラーレスポンスは統一されたスキーマを使用**
* **エラーコードとメッセージを含める**
* **詳細情報が必要な場合は** `details` フィールドを使用

**OpenAPI定義例:**

```yaml
components:
  schemas:
    Error:
      type: object
      required:
        - code
        - message
      properties:
        code:
          type: string
          description: エラーコード
          example: VALIDATION_ERROR
        message:
          type: string
          description: エラーメッセージ
          example: 無効な入力値です
        details:
          type: array
          description: エラー詳細（オプション）
          items:
            type: object
            properties:
              field:
                type: string
                description: エラーが発生したフィールド
              reason:
                type: string
                description: エラー理由

  responses:
    BadRequest:
      description: リクエストが不正
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
          example:
            code: VALIDATION_ERROR
            message: 無効な値です

    NotFound:
      description: リソースが見つからない
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
          example:
            code: NOT_FOUND
            message: リソースが見つかりません
```

## OpenAPI自動生成コードの扱い

### 基本方針

* **自動生成コードは** `generated/openapi/` に配置
* **生成されたインターフェースを実装する形でハンドラーを作成**
* **生成コードを直接編集しない**（再生成時に上書きされるため）

### 実装例

```go
// generated/openapi/server.gen.go（自動生成）
type ServerInterface interface {
    GetUser(ctx context.Context, request GetUserRequestObject) (GetUserResponseObject, error)
    CreateUser(ctx context.Context, request CreateUserRequestObject) (CreateUserResponseObject, error)
}

// presentation/httphandler/user_handler.go（手動実装）
type UserHandler struct {
    userUsecase usecase.UserUsecase
}

func NewUserHandler(userUsecase usecase.UserUsecase) *UserHandler {
    return &UserHandler{
        userUsecase: userUsecase,
    }
}

// インターフェース実装の確認
var _ openapi.ServerInterface = (*UserHandler)(nil)

// GetUser はユーザー取得のハンドラー
func (h *UserHandler) GetUser(
    ctx context.Context,
    request openapi.GetUserRequestObject,
) (openapi.GetUserResponseObject, error) {
    // パスパラメータから型変換
    userID := types.UserIDOf(request.UserId)

    // ユースケース実行
    opt, err := h.userUsecase.GetUser(ctx, userID)
    if err != nil {
        return nil, xerrors.Errorf("ユーザーの取得に失敗しました: %w", err)
    }

    // 存在チェック
    user, ok := opt.Value()
    if !ok {
        return openapi.GetUser404JSONResponse{
            Code:    ptr("NOT_FOUND"),
            Message: ptr("ユーザーが見つかりません"),
        }, nil
    }

    // レスポンスに変換
    response := toUserResponse(user)
    return openapi.GetUser200JSONResponse(response), nil
}
```

## リクエスト変換パターン

### 基本方針

* **変換ロジックは** `request.go` に集約
* **変換関数はすべてプライベート**（小文字開始）
* **バリデーションエラーは適切なHTTPステータスコードで返す**

### 実装例（request.go）

```go
// request.go
package httphandler

import (
    "fmt"

    "example.com/app/domain/types"
    "example.com/app/generated/openapi"
    "golang.org/x/xerrors"
)

// toUserType はOpenAPI型からドメイン型に変換する
func toUserType(userType openapi.UserType) (types.UserType, error) {
    switch userType {
    case openapi.UserTypeRegular:
        return types.UserTypeRegular, nil
    case openapi.UserTypePremium:
        return types.UserTypePremium, nil
    default:
        return "", xerrors.Errorf("無効なユーザー種別: %s", userType)
    }
}

// toEmail はオプショナルなメールアドレスを変換する
func toEmail(email *string) types.Optional[types.Email] {
    if email == nil {
        return types.None[types.Email]()
    }
    return types.Some(types.EmailOf(*email))
}
```

## レスポンス変換パターン

### 基本方針

* **変換ロジックは** `response.go` に集約
* **変換関数はすべてプライベート**（小文字開始）
* **テスト用にエクスポートが必要な場合は** `export_test.go` を使用

### 実装例（response.go）

```go
// response.go
package httphandler

import (
    "example.com/app/domain/model"
    "example.com/app/domain/types"
    "example.com/app/generated/openapi"
)

// toUserResponse はドメインモデルからレスポンスに変換する
func toUserResponse(user *model.User) openapi.User {
    return openapi.User{
        UserId:      ptr(user.UserID().String()),
        Email:       toEmailAPI(user.Email()),
        DisplayName: ptr(user.DisplayName()),
        UserType:    ptr(toUserTypeAPI(user.UserType())),
        CreatedAt:   ptr(user.CreatedAt()),
        UpdatedAt:   ptr(user.UpdatedAt()),
    }
}

// toEmailAPI はOptional[Email]をAPI型に変換する
func toEmailAPI(email types.Optional[types.Email]) *string {
    if e, ok := email.Value(); ok {
        return ptr(e.String())
    }
    return nil
}

// toUserTypeAPI はドメイン型からAPI型に変換する
func toUserTypeAPI(userType types.UserType) openapi.UserType {
    switch userType {
    case types.UserTypeRegular:
        return openapi.UserTypeRegular
    case types.UserTypePremium:
        return openapi.UserTypePremium
    default:
        return ""  // 未知の値の場合
    }
}

// ptr は任意の型のポインタを返すヘルパー関数
func ptr[T any](v T) *T {
    return &v
}
```

### テスト用エクスポート（export_test.go）

テストで変換関数を直接テストする必要がある場合:

```go
// export_test.go
package httphandler

// テスト用にエクスポート
var (
    ToUserResponse = toUserResponse
    ToUserTypeAPI  = toUserTypeAPI
    ToEmailAPI     = toEmailAPI
    Ptr            = ptr
)
```

## バリデーションとエラーレスポンス

### 基本方針

* **バリデーションエラーは 400 Bad Request**
* **認証エラーは 401 Unauthorized**
* **認可エラーは 403 Forbidden**
* **リソース未発見は 404 Not Found**
* **内部エラーは 500 Internal Server Error**（ログに記録）

### 実装例

```go
func (h *UserHandler) CreateUser(
    ctx context.Context,
    request openapi.CreateUserRequestObject,
) (openapi.CreateUserResponseObject, error) {
    // バリデーション
    if request.Body == nil {
        return openapi.CreateUser400JSONResponse{
            Code:    ptr("INVALID_REQUEST"),
            Message: ptr("リクエストボディが必要です"),
        }, nil
    }

    // 型変換とバリデーション
    userType, err := toUserType(request.Body.UserType)
    if err != nil {
        return openapi.CreateUser400JSONResponse{
            Code:    ptr("VALIDATION_ERROR"),
            Message: ptr(err.Error()),
        }, nil
    }

    // ユースケース実行
    user, err := h.userUsecase.CreateUser(ctx, userType, ...)
    if err != nil {
        // 内部エラー（ログに記録してから返す）
        return nil, xerrors.Errorf("ユーザーの作成に失敗しました: %w", err)
    }

    response := toUserResponse(user)
    return openapi.CreateUser201JSONResponse(response), nil
}
```

## 関連ドキュメント

* [アーキテクチャ設計規約](architecture.md) - レイヤー構成
* [テストコード規約](testing.md) - ハンドラーのテスト
* [プロジェクト構成規約](project-structure.md) - ディレクトリ構成

## 参考資料

* [Google API Improvement Proposals (AIP)](https://google.aip.dev/)
* [AIP-121: Resource-oriented design](https://google.aip.dev/121)
* [AIP-122: Resource names](https://google.aip.dev/122)
* [AIP-131-135: Standard methods](https://google.aip.dev/131)
* [AIP-136: Custom methods](https://google.aip.dev/136)
* [AIP-140: Field names](https://google.aip.dev/140)
* [AIP-158: Pagination](https://google.aip.dev/158)
* [AIP-193: Errors](https://google.aip.dev/193)
* [OpenAPI Specification](https://spec.openapis.org/oas/v3.0.0)
* [oapi-codegen](https://github.com/deepmap/oapi-codegen)
