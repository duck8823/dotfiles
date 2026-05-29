# 型システムとNULL許容値規約

## 概要

型安全性を高めるための型システム規約です。特に、NULL許容値の扱い方、ドメイン固有型の定義方法、判別共用体（タグ付きユニオン）の表現方法について定めています。

前提として、すべての public API には型注釈を付与し、`mypy --strict` を通過させます。`# type: ignore` / `# noqa` を付ける場合は必ず理由コメントを添えます。`Any` は理由なく使いません。

```python
# 悪い例: 理由のない type: ignore は禁止
value = parse(raw)  # type: ignore  # NG: 理由がない

# 良い例: 理由を明示する
value = parse(raw)  # type: ignore[no-any-return]  # 外部ライブラリの型スタブ未整備のため
```

## NULL許容値の扱い

### 基本方針

* **NULL許容値には** `T | None` 型を使用する（PEP 604）
* `Optional[T]` というエイリアスは使わず、`T | None` で明示的にNULL許容を表現する
* 暗黙の `None` 許容（型注釈なしのデフォルト `None`）を作らない。`mypy --strict` の `no_implicit_optional` を有効にする
* `None` の可能性は型ナローイングで解消してから値を使う

### 値の取得方法

`T | None` を受け取ったら、`is None` / `is not None` による型ナローイングで存在有無を判定します。mypy はナローイング後の分岐で `None` を除外した型として扱うため、追加のキャストは不要です。

```python
# 良い例: is not None でナローイングしてから使う
def handle(user: User | None) -> Result:
    if user is not None:
        # ここでは user の型は User（None は除外されている）
        return process_user(user)
    # 値がない場合の処理
    raise UserNotFoundError("user not found")


# 悪い例: ナローイングせずに属性アクセス（mypy がエラーを報告する）
def handle_bad(user: User | None) -> Result:
    return process_user(user)  # NG: User | None を User として渡している
```

`None` を早期に弾いて以降のコードをフラットに保ちたい場合は、ガード節を使います。

```python
def handle(user: User | None) -> Result:
    if user is None:
        raise UserNotFoundError("user not found")
    # 以降 user は User として扱える
    return process_user(user)
```

### `T | None` の位置と注意点

* 引数・戻り値・属性のいずれでも `T | None` を型注釈に明示する。デフォルト値 `None` だけで NULL 許容を表現しない
* `T | None` の `T` には具体的な値型を置く。`Any | None` のように `None` 以外を曖昧にしない
* ネストしたコンテナ（`list[T]`、`dict[K, V]`）では、空コレクションと `None` の意味が異なる場合のみ `list[T] | None` を使う。区別が不要なら空コレクションをデフォルトにして `None` を避ける

```python
# 良い例: 値型を明示
email: Email | None
created_at: datetime | None
member_ids: list[MemberId]  # 「未取得」を表す必要がなければ空リストで十分

# 悪い例
data: Any | None  # NG: None 以外が曖昧
```

### エンティティの存在有無を表す場合

リポジトリの取得系メソッドは、対象が存在しないことを `Entity | None` で表現します。DB エラー等の本当のエラーは例外で送出し、「存在しない」を例外で表現しません。リポジトリ・ユースケース・プレゼンテーション層で一貫して `Entity | None` を使えます。

```python
# domain/model/user_repository.py
from typing import Protocol

from app.types import UserId


class UserRepository(Protocol):
    """ユーザーの永続化を担うリポジトリ。"""

    def find_by_id(self, user_id: UserId) -> User | None:
        """ユーザーをIDで取得する。

        存在しない場合は None を返す。例外は DB エラー等の本当のエラーのみ送出する。
        """
        ...
```

呼び出し側:

```python
def get_profile(self, user_id: UserId) -> Profile:
    user = self._repository.find_by_id(user_id)
    if user is None:
        raise UserNotFoundError(f"ユーザーが見つかりません: {user_id}")
    return Profile.from_user(user)
```

リポジトリインターフェースを Domain 層に `typing.Protocol` で定義し依存を内向きに保つ点は、[アーキテクチャ規約](architecture.md) を参照してください。

## ドメイン固有型

### 基本方針

* **プリミティブ型（**`str`, `int` など）を引数・戻り値・属性に直接使わず、ドメイン固有型を定義する
* 型の誤用（例: `UserId` を期待する箇所に `OrderId` を渡す）を `mypy --strict` で検出する
* 用途に応じて `NewType` / `Literal` / `Enum` / 値オブジェクト（`@dataclass(frozen=True)`）を使い分ける
* 値オブジェクトの実装パターン・ファクトリ命名規則は [ドメインモデル設計規約](domain-model.md) を参照する

### NewType: 軽量な識別子・別名

検証ロジックを持たない単純な識別子は `NewType` で定義します。実行時は基底型そのものなのでオーバーヘッドがなく、mypy 上では別型として扱われます。

```python
from typing import NewType

UserId = NewType("UserId", str)
OrderId = NewType("OrderId", str)


def find_order(user_id: UserId, order_id: OrderId) -> Order | None:
    """ユーザーの注文を取得する。"""
    ...


user_id = UserId("u_123")
order_id = OrderId("o_456")
find_order(user_id, order_id)        # OK
find_order(order_id, user_id)        # mypy エラー: 引数の型が逆
find_order("u_123", "o_456")         # mypy エラー: str は UserId/OrderId ではない
```

### Literal: 限定された文字列・数値の集合

固定された少数の文字列・数値リテラル（外部 API の区分値など）は `Literal` で表現します。Enum 化するほどの振る舞いを持たない場合に使います。

```python
from typing import Literal

HttpMethod = Literal["GET", "POST", "PUT", "DELETE"]


def request(method: HttpMethod, url: str) -> Response:
    """HTTP リクエストを送る。"""
    ...


request("GET", "https://example.com")    # OK
request("PATCH", "https://example.com")  # mypy エラー: PATCH は HttpMethod に含まれない
```

### Enum: 名前付き・振る舞いを持つ列挙

ドメイン上の意味を持つ列挙、または分岐ロジック・付随メソッドを持たせたい場合は `Enum` を使います。使い分けの基準は次のとおりです。

* **文字列値を持つドメイン enum**（DB・API・シリアライズで文字列表現を持つもの）は `StrEnum`（`from enum import StrEnum`）を使う。メンバが文字列としても振る舞うため、シリアライズ・比較が容易になる
* **文字列表現を持たない振る舞いのみの enum**（順序・状態遷移などロジックだけを表す列挙）は `Enum` を使う

```python
# 文字列値を持つドメイン enum: StrEnum を使う
from enum import StrEnum


class UserType(StrEnum):
    """ユーザー種別。"""

    GUEST = "guest"
    MEMBER = "member"
    ADMIN = "admin"

    @property
    def can_manage(self) -> bool:
        """管理操作の権限を持つかを返す。"""
        return self is UserType.ADMIN
```

```python
# 振る舞いのみの enum: 文字列表現が不要なら Enum を使う
from enum import Enum, auto


class Priority(Enum):
    """処理の優先度。文字列表現は持たず、比較・分岐のみに使う。"""

    LOW = auto()
    MEDIUM = auto()
    HIGH = auto()

    @property
    def is_urgent(self) -> bool:
        """緊急扱いの優先度かを返す。"""
        return self is Priority.HIGH
```

### 検証付き値オブジェクト

不変条件を持つ値（メールアドレス、金額など）は `@dataclass(frozen=True)` で値オブジェクトとして定義し、`__post_init__` で検証します。ファクトリは値オブジェクトを生成する `of` を用い、変換は `from_` を用います（詳細は [ドメインモデル設計規約](domain-model.md)）。不変条件違反は組み込みの `ValueError` ではなく、独自例外階層の `ValidationError`（[エラーハンドリング規約](error-handling.md) の `AppError` 階層）を送出します。

```python
import re
from dataclasses import dataclass

from app.errors import ValidationError

_EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


@dataclass(frozen=True)
class Email:
    """メールアドレスを表す値オブジェクト。"""

    value: str

    def __post_init__(self) -> None:
        if not _EMAIL_PATTERN.match(self.value):
            raise ValidationError(f"不正なメールアドレスです: {self.value}")

    @classmethod
    def of(cls, value: str) -> "Email":
        """文字列から Email を生成する。"""
        return cls(value)
```

### types パッケージへの集約

値オブジェクト・DTO・`NewType`・`Literal` 別名は `types` パッケージ（モジュール）に統一して配置し、各層から共通参照します。

```python
# src/app/types/__init__.py
from app.types.identifiers import OrderId, UserId
from app.types.email import Email
from app.types.user_type import UserType

__all__ = ["OrderId", "UserId", "Email", "UserType"]
```

## 判別共用体（Sealed / Closed Union）

Go の Sealed Interface に相当する「外部から実装を追加させない閉じた型集合」は、Python では次のいずれかで表現します。

### パターン1: ユニオン型 + match による網羅

各バリアントを `@dataclass(frozen=True)` で定義し、ユニオン型エイリアスにまとめます。`match` 文で分岐し、`case _:` に到達不能であることを `assert_never` で mypy に検証させると、バリアント追加漏れをコンパイル時相当（型チェック時）に検出できます。

```python
from dataclasses import dataclass
from typing import assert_never


@dataclass(frozen=True)
class SegmentTarget:
    """セグメント指定の配信ターゲット。"""

    segment_name: str


@dataclass(frozen=True)
class MemberTarget:
    """会員指定の配信ターゲット。"""

    member_ids: list[str]


# 閉じたユニオン: 新しいバリアントを足したら下流の match が mypy エラーになる
Target = SegmentTarget | MemberTarget


def process_target(target: Target) -> None:
    """配信ターゲットを処理する。"""
    match target:
        case SegmentTarget(segment_name=name):
            # セグメントターゲットの処理
            _process_segment(name)
        case MemberTarget(member_ids=ids):
            # 会員ターゲットの処理
            _process_members(ids)
        case _:
            # ここに到達する型が残っていると mypy が assert_never でエラーにする
            assert_never(target)
```

Go では `type switch` の網羅性をコンパイラが保証しないため `default` でエラーを返す必要がありましたが、Python では `assert_never` を使うことで mypy が網羅性を静的に検証します。これが Python での推奨形です。

### パターン2: Protocol による振る舞いの抽象化

バリアントごとに異なる振る舞いを持たせ、呼び出し側で分岐したくない場合は `typing.Protocol` を使います。網羅性チェックは不要になりますが、構造的部分型のため「外部実装の禁止」は保証されません。閉じた集合性が重要な場合はパターン1を選びます。

```python
from typing import Protocol


class Target(Protocol):
    """配信ターゲットの振る舞い。"""

    def resolve_recipients(self) -> list[UserId]:
        """配信対象のユーザーIDを解決する。"""
        ...
```

## 関連ドキュメント

* [ドメインモデル設計規約](domain-model.md) - 値オブジェクトの実装パターン、ファクトリ命名規則（`new` / `of` / `from_`）
* [アーキテクチャ規約](architecture.md) - レイヤー構成、Protocol によるリポジトリインターフェース
* [テストコード規約](testing.md) - `T | None` ・値オブジェクトのテスト

## 参考資料

* [PEP 604 – Allow writing union types as X | Y](https://peps.python.org/pep-0604/)
* [PEP 484 – Type Hints (NewType, Union)](https://peps.python.org/pep-0484/)
* [typing.assert_never](https://docs.python.org/3/library/typing.html#typing.assert_never)
* [mypy – Strict mode](https://mypy.readthedocs.io/en/stable/command_line.html#cmdoption-mypy-strict)
