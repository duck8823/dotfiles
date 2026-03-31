# エラーハンドリング規約

## 概要

エラーハンドリングの規約です。スタックトレースの保持と、適切なエラーラッピングを実現するための実装指針を定めています。

## xerrors.Errorf の使用

### 基本方針

* **エラーのラッピングには** `xerrors.Errorf` を使用する
* `fmt.Errorf` はエラーチェーンのみを保持し、スタックトレースをキャプチャしない
* `xerrors.Errorf` はスタックトレースをキャプチャするため、デバッグが容易になる

### 実装例

```go
import (
	"context"

	"example.com/app/domain/types"
	"golang.org/x/xerrors"
)

func (s *service) GetUser(ctx context.Context, userID types.UserID) (*User, error) {
	opt, err := s.userRepo.FindByID(ctx, userID)
	if err != nil {
		return nil, xerrors.Errorf("ユーザーの取得に失敗しました: %w", err)
	}

	user, ok := opt.Value()
	if !ok {
		return nil, ErrUserNotFound
	}

	if err := s.validateUser(user); err != nil {
		return nil, xerrors.Errorf("ユーザーのバリデーションに失敗しました: %w", err)
	}

	return user, nil
}
```

### エラーメッセージの記述方法

* 日本語で分かりやすく記述する
* 何が失敗したのかを明確に示す
* 原因エラーがある場合は `%w` を使ってラップする

## golangci-lint との統合

### xerrors の SA1019 警告を除外

`xerrors.Errorf` は非推奨（deprecated）とマークされていますが、スタックトレースキャプチャのために継続使用します。SA1019 を全体的に無効化するのではなく、`exclusions.rules` で xerrors パッケージに対する SA1019 のみを除外します。

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
```

これにより、xerrors 以外の deprecated API 使用は引き続き SA1019 で検出されます。

## 関連ドキュメント

* [インフラストラクチャパターン規約](infrastructure.md) - ログ記録、Graceful Shutdown
* [Linter設定](linter.md) - golangci-lint設定

## 参考資料

* [golang.org/x/xerrors](https://pkg.go.dev/golang.org/x/xerrors)
* [golangci-lint Configuration](https://golangci-lint.run/usage/configuration/)
