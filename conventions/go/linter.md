# Linter設定

## 概要

golangci-lintの設定規約です。コード品質を保ちながら、プロジェクト固有の要件に合わせた設定を行っています。

## 有効化するLinter

### 基本方針

* `revive`: コーディングスタイルのチェック
* `wrapcheck`: エラーのラッピングチェック
* `staticcheck`: 静的解析によるバグ検出

## 完全な設定ファイル

`.golangci.yml` の完全な設定：

```yaml
version: "2"

linters:
  enable:
    - revive
    - wrapcheck
    - staticcheck
  exclusions:
    rules:
      # xerrors.Errorf はスタックトレースをキャプチャするため使用を継続
      # xerrors パッケージに対する SA1019 (deprecation警告) のみを除外
      - linters:
          - staticcheck
        text: 'SA1019: "golang.org/x/xerrors"'
      # 値オブジェクト（domain/types）とDTO（application/types）を格納するパッケージとして types を使用
      # Go標準ライブラリでも使われている命名であり、プロジェクト内で一貫して使用するため許可
      - path: ".*/types/[^/]+\\.go"
        text: "var-naming: avoid meaningless package names"
        linters:
          - revive

formatters:
  exclusions:
    generated: lax
    paths:
      - third_party$
      - builtin$
      - examples$
```

## 各Linterの役割

### revive

* Goのコーディングスタイルをチェック
* `types` パッケージの命名警告を抑制している

### wrapcheck

* エラーが適切にラップされているかチェック
* エラーチェーンを保持し、デバッグを容易にする

### staticcheck

* 静的解析によるバグやパフォーマンス問題を検出
* xerrors パッケージに対する **SA1019（非推奨警告）のみを除外** し、`xerrors.Errorf` の使用を許可

## //nolint ディレクティブの使用

### 基本方針

* Linterの警告を個別に抑制する必要がある場合は `//nolint` ディレクティブを使用する
* **必ず理由をコメントで記載する**
* プロジェクト全体で抑制すべき警告は `.golangci.yml` の `exclusions` を使用する

### 使用例

#### サードパーティライブラリのインターフェース化

サードパーティライブラリのクライアントをテスタビリティのためにインターフェース化する場合、パッケージ名とインターフェース名が重複（stuttering）することがあります。この場合、元のライブラリの命名を尊重するため、警告を抑制します。

```go
// ThirdPartyClient はサードパーティライブラリのクライアントインターフェース
// テスタビリティのために必要な操作のみを定義
//
//nolint:revive // サードパーティのインターフェースなのでGoDocはそちらを参照
type ThirdPartyClient interface {
    Operation(ctx context.Context, params *thirdparty.Input) (*thirdparty.Output, error)
}
```

#### 特定の行のみ抑制

```go
//nolint:revive // 特定の理由により命名規則から外れる
var API_KEY = "key"
```

#### 複数のLinterを抑制

```go
//nolint:revive,staticcheck // 複数の理由を記載
func legacyFunction() {
    // ...
}
```

### 抑制すべきでないケース

以下のような場合は `//nolint` を使用せず、コードを修正してください：

* 自分で定義した型や関数の命名規則違反
* 不要な変数やimport
* 明らかなバグや非効率なコード

## 実行方法

```shell
# Linterの実行
golangci-lint run

# 自動修正可能な問題を修正
golangci-lint run --fix
```

## 関連ドキュメント

* [エラーハンドリング規約](error-handling.md) - xerrors.Errorf、SA1019除外
* [命名規則](naming.md) - typesパッケージ命名
* [インフラストラクチャパターン規約](infrastructure.md) - サードパーティクライアントのインターフェース化

## 参考資料

* [golangci-lint Configuration](https://golangci-lint.run/usage/configuration/)
* [golangci-lint Linters](https://golangci-lint.run/usage/linters/)
