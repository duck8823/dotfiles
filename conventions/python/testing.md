# テストコード規約

## 概要

テストコードの記述規約です。テストの構造化、命名規則、モックの使用方法について定めています。テストランナーは `pytest`、テーブル駆動は `@pytest.mark.parametrize` を前提とします。

## テストファイルの配置

### 基本方針

* **`tests/` ディレクトリは `src/` と同一のパッケージ構成にする**（src レイアウト）
* **ファイル名は** `test_<対象モジュール>.py` とする（`pytest` の既定検出パターン）
* **公開（public）API を外部利用者の視点でテストする** ことを基本とする
* 非公開関数（`_xxx`）のテストが必要な場合は、対象モジュールから直接 import してテストする（Go の `export_test.go` に相当する仕組みは不要で、同一パッケージのプライベート関数も import で参照できる）

### ディレクトリ構成例

```plaintext
src/app/
├── domain/
│   ├── model/
│   │   ├── user.py
│   │   ├── user_repository.py
│   │   └── __init__.py
│   └── types/
│       ├── user.py
│       └── __init__.py
└── infrastructure/
    └── postgres/
        ├── user_datasource.py
        └── __init__.py

tests/app/
├── domain/
│   ├── model/
│   │   ├── test_user.py          # user.py のテスト
│   │   └── conftest.py           # model パッケージ共通の fixture
│   └── types/
│       └── test_user.py          # types/user.py のテスト
├── infrastructure/
│   └── postgres/
│       ├── test_user_datasource.py
│       └── conftest.py           # DB 接続 fixture
└── conftest.py                   # プロジェクト全体の fixture
```

`tests/` の各階層に `__init__.py` は置かず、`pyproject.toml` の `[tool.pytest.ini_options]` で `rootdir` と `pythonpath` を設定して import を解決します。

```toml
# pyproject.toml
[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
addopts = "--strict-markers --strict-config"
```

### 公開 API を起点にテストする

* **公開（exported）API のみをテストする** ことを原則とする
* パッケージの外部利用者の視点で、`__init__.py` が再エクスポートする型・関数を起点に検証する

```python
# tests/app/domain/types/test_user.py
from app.domain.types import UserId  # 公開 API を import


def test_useridのofは値オブジェクトを生成する() -> None:
    # 公開 API のみをテストする
    user_id = UserId.of("user-123")
    assert str(user_id) == "user-123"
```

### 非公開関数のテスト

Go では `export_test.go` で非公開関数を公開する必要がありますが、Python では同一パッケージのプライベート関数（`_xxx`）もモジュールから直接 import できます。非公開関数のテストは「公開 API を通したテストで網羅できないか」をまず検討し、それでもユニットで検証したい変換ロジックなどに限り直接 import します。

```python
# src/app/infrastructure/postgres/user_datasource.py
def _to_user_row(user: User) -> UserRow:
    """ドメインモデルを DB 行に変換する（非公開）。"""
    ...
```

```python
# tests/app/infrastructure/postgres/test_user_datasource.py
from app.infrastructure.postgres.user_datasource import _to_user_row


def test_to_user_rowはドメインモデルを行に変換する() -> None:
    ...
```

#### DTO の非公開メソッドをテストする

DTO の変換メソッド（`_to_model()` など）が非公開の場合も、テストから直接呼び出してテーブル駆動で検証します。`raise` を期待するケースは `pytest.raises` で検証します。

```python
# tests/app/infrastructure/postgres/test_user_association_record.py
import pytest

from app.domain import model, types
from app.errors import ValidationError
from app.infrastructure.postgres.dto import UserAssociationRecord


@pytest.mark.parametrize(
    ("record", "expected"),
    [
        pytest.param(
            UserAssociationRecord(sp_uid=1, platform_user_id="token-ios-1", platform_type="ios"),
            model.UserAssociation.of(
                types.SpUid.of(1),
                types.StoreId.from_("token-ios-1"),
                types.Platform.IOS,
            ),
            id="ios レコードをドメインモデルに変換できる",
        ),
    ],
)
def test_user_association_recordの_to_modelは正常系で変換する(
    record: UserAssociationRecord,
    expected: model.UserAssociation,
) -> None:
    # when
    got = record._to_model()

    # then
    assert got == expected


def test_user_association_recordの_to_modelはplatform_user_idが空でエラー() -> None:
    record = UserAssociationRecord(sp_uid=1, platform_user_id="", platform_type="ios")

    with pytest.raises(ValidationError, match="platform_user_id"):
        record._to_model()
```

## 並列実行

### 基本方針

* テストはデフォルトで状態を共有せず、独立に実行できるように書く（ファイル I/O・グローバル状態への依存を避ける）
* 高速化のために `pytest-xdist`（`pytest -n auto`）でプロセス並列を使ってよい。並列前提でも壊れないテストを書くことが条件
* `@pytest.mark.parametrize` の各ケースは独立したテストとして扱われるため、ケース間で可変オブジェクトを共有しない

> **Note:** DB 統合テストなど同一リソース（テーブル・ファイル）を共有するテストは `pytest-xdist` での並列対象から外すか、`@pytest.mark.serial` などのマーカーで分離して直列実行する。

### 実装例

```python
# 並列で実行されても安全: 各ケースは入力と期待値だけを持ち、外部状態を持たない
@pytest.mark.parametrize(
    ("value", "expected"),
    [
        pytest.param("ios", True, id="iOS は既知"),
        pytest.param("android", True, id="Android は既知"),
        pytest.param("unknown", False, id="unknown は未知"),
    ],
)
def test_platformのis_known(value: str, expected: bool) -> None:
    assert Platform.from_(value).is_known() is expected
```

DB 統合テストを直列に隔離する例:

```toml
# pyproject.toml
[tool.pytest.ini_options]
markers = ["serial: 同一リソースを共有するため直列実行する"]
```

```bash
# 並列対象からマーカー付きを除外し、別途直列で実行する
pytest -n auto -m "not serial"
pytest -m serial
```

## テスト関数の命名

### 基本方針

* **`test_` + 対象 + 条件** の形式とし、条件を日本語で表現する（OSS・外部コントリビューション前提の公開プロジェクトでは英語を優先）
* `@pytest.mark.parametrize` のケース名は `pytest.param(..., id="...")` の `id` に日本語で条件を書く（`pytest -v` の出力・失敗時の特定に使われる）
* メソッドのテストはクラスにまとめてもよい（`class TestUser:` のように `Test` プレフィックスで定義する）

### 命名例

```python
def test_user_usecaseのget_userはユーザーを返す() -> None: ...
def test_useridのofは空文字でエラー() -> None: ...


class TestUser:
    """User エンティティの振る舞いのテスト。"""

    def test_update_profileは更新日時を再設定する(self) -> None: ...
```

> **Note:** 日本語の関数名は PEP 8 の `snake_case`（ASCII）から外れますが、テスト名はドキュメントとしての可読性を優先します。プロダクションコードの識別子は ASCII の `snake_case` を維持します（[命名規約](naming.md) を参照）。OSS では英語名を使います。

## テーブル駆動テスト

### 基本方針

* **複数のテストケースを 1 つのテスト関数に** `@pytest.mark.parametrize` でまとめる
* **各ケースには** `pytest.param(..., id="...")` で名前を必ず付ける
* **テストを跨いだ共通の可変変数を作らない**（モジュールレベルの可変オブジェクト共有も禁止。fixture か各ケースのリテラルで与える）
* 正常系と異常系を 1 つの parametrize に混在させない。異常系は `pytest.raises` を使う別テストに分ける

### テーブル構造の使い分け

| パターン | パラメータ構成 | 用途 |
| --- | --- | --- |
| コンストラクタテスト | `value` + `expected`（異常系は `match` 文字列） | ファクトリ・変換関数のテスト |
| ゲッター/メソッドテスト | `sut` + `expected` | 値オブジェクト・メソッドのテスト |
| ユースケーステスト | `fixture（モック設定）` + `expected` | モック・依存性注入を使うテスト |

### コンストラクタテスト（value + expected パターン）

正常系を parametrize でまとめ、異常系（例外送出）は `pytest.raises` の別テストに分けます。

```python
import pytest

from app.domain.types import RunId
from app.errors import ValidationError


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        pytest.param(
            "00000000-0000-4000-8000-000000000001",
            RunId.from_("00000000-0000-4000-8000-000000000001"),
            id="有効な UUIDv4 を受け付ける",
        ),
    ],
)
def test_runidのfrom_は正常系で生成する(value: str, expected: RunId) -> None:
    # when
    got = RunId.from_(value)

    # then
    assert got == expected


@pytest.mark.parametrize(
    "value",
    [
        pytest.param("", id="空文字はエラー"),
        pytest.param("not-a-uuid", id="UUID 形式でない文字列はエラー"),
    ],
)
def test_runidのfrom_は不正値でvalidationerror(value: str) -> None:
    with pytest.raises(ValidationError, match="RunId"):
        RunId.from_(value)
```

### ゲッター/メソッドテスト（sut パターン）

```python
import pytest

from app.domain.types import Platform


@pytest.mark.parametrize(
    ("sut", "expected"),
    [
        pytest.param(Platform.IOS, True, id="iOS は既知"),
        pytest.param(Platform.ANDROID, True, id="Android は既知"),
        pytest.param(Platform.UNKNOWN, False, id="unknown は未知"),
    ],
)
def test_platformのis_known(sut: Platform, expected: bool) -> None:
    # when
    got = sut.is_known()

    # then
    assert got is expected
```

### ユースケーステスト（モック設定 + expected パターン）

依存（リポジトリ Protocol）をモックで差し替えるケースでは、モックの構築を `Callable` で受け取り、各ケースが期待する振る舞いを定義します。非同期メソッドは `pytest.mark.asyncio` と `AsyncMock` で扱います。

```python
from collections.abc import Callable
from unittest.mock import AsyncMock

import pytest

from app.application.usecase import UserUsecase
from app.domain.model import User, UserRepository
from app.domain.types import UserId


def _expected_user() -> User:
    return User.of(
        user_id=UserId.of("user-123"),
        email=None,
        display_name="ユーザー",
        user_type=...,  # 省略
        created_at=...,
        updated_at=...,
    )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("build_repo", "user_id", "expected"),
    [
        pytest.param(
            lambda: AsyncMock(spec=UserRepository, find_by_id=AsyncMock(return_value=_expected_user())),
            UserId.of("user-123"),
            _expected_user(),
            id="ユーザーを取得できる",
        ),
        pytest.param(
            lambda: AsyncMock(spec=UserRepository, find_by_id=AsyncMock(return_value=None)),
            UserId.of("missing"),
            None,
            id="存在しないユーザーは None を返す",
        ),
    ],
)
async def test_user_usecaseのget_user(
    build_repo: Callable[[], UserRepository],
    user_id: UserId,
    expected: User | None,
) -> None:
    # given
    user_repo = build_repo()

    # and
    sut = UserUsecase(user_repo)

    # when
    got = await sut.get_user(user_id)

    # then
    assert got == expected
    user_repo.find_by_id.assert_awaited_once_with(user_id)
```

### `# given / # and / # when / # then` コメント

テスト本体は `# given`（前提）/ `# when`（実行）/ `# then`（検証）で区切ります。`# given` 内で意味的に分かれる箇所は `# and` で区切ります。

```python
# given — テスト前提条件（モック、フィクスチャなど）
user_repo = build_repo()

# and — テスト対象の構築
sut = UserUsecase(user_repo)

# when — テスト対象の実行
got = await sut.get_user(user_id)

# then — 検証
assert got == expected
```

## アサーション

### 基本方針

* **`pytest` の素の `assert` 文を使う**（`pytest` がアサーションを書き換えて詳細な失敗メッセージを出力する）
* **`unittest` の `assertEqual` 系メソッドや外部アサーションライブラリは使わない**
* **構造体（値オブジェクト・DTO）の比較は値等価で行う**。値オブジェクトは `@dataclass(frozen=True)`、DTO も `@dataclass(frozen=True)` のため、`==` 一つでフィールド全体の等価比較ができる（[ドメインモデル設計規約](domain-model.md) を参照）
* 例外の検証は `pytest.raises` を使い、`match=` で原因メッセージ（の部分一致正規表現）まで確認する

### dataclass の値等価でのアサーション

Go では非公開フィールドを `cmp.AllowUnexported` で比較する必要がありましたが、Python の `@dataclass` は `__eq__` を自動生成するため、`==` で全フィールドを比較できます。

```python
from app.application.types import Progress


def test_progressのnewは初期状態を生成する() -> None:
    # when
    got = Progress.new(total=10)

    # then
    assert got == Progress(total=10, done=0)
```

### 一部フィールドを比較から除外する

DB が自動設定する `updated_at` などを比較から除外したい場合は、`dataclasses.replace` で期待値側の該当フィールドを実測値に揃えてから比較します（個別フィールドアサーションの乱立を避ける）。

```python
import dataclasses

from app.application.types import Progress


def test_progressのadvanceはdoneを増やす() -> None:
    sut = Progress.new(total=10)

    # when
    got = sut.advance()

    # then: updated_at は実行時刻に依存するため期待値に揃えてから比較する
    want = dataclasses.replace(
        Progress(total=10, done=1, updated_at=got.updated_at),
    )
    assert got == want
```

時刻のように非決定的な値はそもそも注入で固定するのが望ましく、その方法は後述の「時刻のテスト」を参照してください。

### エンティティの等価性

エンティティは識別子（id）で `__eq__` / `__hash__` を定義します（[ドメインモデル設計規約](domain-model.md)）。そのため `==` は id 一致のみを見ます。フィールドの更新結果を検証したい場合は、`==` ではなく `@property` ゲッターで個別に検証します。

```python
def test_user_update_profileは表示名を更新する() -> None:
    sut = User.new(
        user_id=UserId.of("user-1"),
        email=None,
        display_name="旧名",
        user_type=...,
    )

    # when
    sut.update_profile(email=None, display_name="新名")

    # then: == は id 比較のため、更新内容はゲッターで確認する
    assert sut.display_name == "新名"
```

## テストヘルパー

### 基本方針

* 共通のヘルパー・fixture は `conftest.py` に置き、同一ディレクトリ配下のテストで共有する
* 値の生成を簡潔にするためのファクトリヘルパーは、`new` / `of` / `from_` を直接呼ぶインライン記述で足りる場合は作らない（ヘルパーの増殖を防ぐ）

### conftest.py の fixture

ディレクトリ単位で共有する fixture は `conftest.py` に定義します。`pytest` は対象テストの位置から上位に向かって `conftest.py` を自動探索します。

```python
# tests/app/domain/model/conftest.py
"""model パッケージのテスト共通 fixture。"""

import datetime as dt

import pytest

from app.domain.model import User
from app.domain.types import UserId


@pytest.fixture
def sample_user() -> User:
    """テスト用の標準的な User を返す。"""
    fixed = dt.datetime(2024, 1, 1, tzinfo=dt.UTC)
    return User.of(
        user_id=UserId.of("user-1"),
        email=None,
        display_name="ユーザー",
        user_type=...,  # 省略
        created_at=fixed,
        updated_at=fixed,
    )
```

```python
# tests/app/domain/model/test_user.py
from app.domain.model import User


def test_user_の同一性はidで判定する(sample_user: User) -> None:
    assert sample_user == sample_user
```

### アンチパターン: 型特化の生成ヘルパー

`make_filter`、`make_assoc`、`build_store_id` のように **特定の型に特化した生成ヘルパー** を個別定義してはいけません。ファクトリ（`of` / `from_`）をテーブル定義内でインライン展開し、ヘルパーの増殖を防ぎます。

```python
# NG: 型特化の生成ヘルパー
def build_store_id(raw: str) -> StoreId:
    return StoreId.from_(raw)
```

```python
# OK: ファクトリをインライン展開する
@pytest.mark.parametrize(
    ("filter_", "expected"),
    [
        pytest.param(
            SourceFilter.of(platform=Platform.IOS),
            [
                model.UserAssociation.of(
                    types.SpUid.of(1),
                    types.StoreId.from_("token-ios-1"),
                    types.Platform.IOS,
                ),
            ],
            id="iOS でフィルタする",
        ),
    ],
)
def test_find_all(filter_: SourceFilter, expected: list[model.UserAssociation]) -> None:
    ...
```

ファクトリが例外を送出しうる箇所では、テーブル定義時に正常値を渡す前提で書きます（異常系は別テストで `pytest.raises` を使う）。

## モックの使用

### 基本方針

* **モックは標準ライブラリの** `unittest.mock`（`Mock` / `MagicMock` / `AsyncMock`）**または** `pytest-mock`（`mocker` fixture）**を使う**
* **リポジトリ・サービスのモックは Protocol を `spec` に指定して生成する**（`spec=UserRepository`）。存在しない属性へのアクセスを検出でき、IF からの乖離を防ぐ
* 非同期メソッドは `AsyncMock` を使い、呼び出し検証は `assert_awaited_once_with` 系で行う
* モックは「協調オブジェクト（依存）」にのみ使う。テスト対象（SUT）自身はモックしない

### Protocol を spec にしたモック

```python
from unittest.mock import AsyncMock

from app.domain.model import UserRepository
from app.domain.types import UserId

# spec を指定すると、UserRepository に無いメソッドへのアクセスは AttributeError になる
repo = AsyncMock(spec=UserRepository)
repo.find_by_id.return_value = None

# 呼び出し検証
# await repo.find_by_id(UserId.of("u-1"))
# repo.find_by_id.assert_awaited_once_with(UserId.of("u-1"))
```

### pytest-mock を使う場合

`mocker` fixture を使うと、テスト終了時のパッチ解除（teardown）が自動化されます。グローバルや外部依存のパッチに適しています。

```python
def test_load_configは時刻を固定して検証する(mocker) -> None:
    mock_clock = mocker.patch("app.domain.model._clock.now")
    mock_clock.return_value = ...
    ...
```

`unittest.mock` の自動 spec を強制したい場合は `create_autospec` を使い、シグネチャ不一致を検出します。

## インフラ層テスト: fixtures + want_state パターン

データベース統合テストでは、**fixtures**（テストデータの投入）と **want_state**（実行後の期待状態）を parametrize に定義し、**actual_state** で DB から直接行を取得して比較します。

### 行 DTO と DataSet

```python
import dataclasses


@dataclasses.dataclass(frozen=True)
class DeliveryRow:
    """deliveries テーブルの 1 行。"""

    id: str
    title: str
    status: str


@dataclasses.dataclass(frozen=True)
class DataSet:
    """テストの DB 状態を表す行集合。"""

    deliveries: tuple[DeliveryRow, ...] = ()
    targets: tuple["TargetRow", ...] = ()
```

可変なデフォルト引数を避けるため、コレクションは `tuple`（不変）を既定値にします。`@dataclass(frozen=True)` のため `==` で `want_state` と `actual_state` をそのまま比較できます。

### 書き込み系テスト（fixtures + want_state + actual_state）

```python
from collections.abc import Callable

import pytest

from app.domain import model


@pytest.mark.serial  # 同一テーブルを共有するため直列実行
@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("fixtures", "build_delivery", "want_state"),
    [
        pytest.param(
            DataSet(),
            lambda: model.Delivery.new(title="テスト"),
            DataSet(deliveries=(DeliveryRow(id="<ignored>", title="テスト", status="PENDING"),)),
            id="データを保存できる",
        ),
    ],
)
async def test_delivery_datasourceのsaveは行を作成する(
    db_session,  # conftest.py の fixture（トランザクション境界・TRUNCATE 済み）
    fixtures: DataSet,
    build_delivery: Callable[[], model.Delivery],
    want_state: DataSet,
) -> None:
    # given
    await _load_fixtures(db_session, fixtures)
    sut = UserDatasource(db_session)

    # when
    await sut.save(build_delivery())

    # then
    got_state = await _actual_state(db_session)
    # DB 採番の id は比較対象外にしてから等価比較する
    assert _ignore_ids(got_state) == _ignore_ids(want_state)
```

DB が採番する `id` や `created_at` のように非決定的なフィールドは、比較前に正規化（`_ignore_ids` で `<ignored>` に揃えるなど）してから `==` で比較します。

### 読み取り専用テスト（fixtures + expected パターン）

読み取り専用メソッド（`find_all` など）のテストでは DB 状態を検証する `want_state` は不要です。`fixtures` でデータを投入し、戻り値を `expected: list[model.XXX]` と直接比較します。

```python
@pytest.mark.serial
@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("fixtures", "filter_", "expected"),
    [
        pytest.param(
            [
                UserAssociationRecord(sp_uid=1, platform_user_id="token-ios-1", platform_type="ios"),
                UserAssociationRecord(sp_uid=2, platform_user_id="token-android-1", platform_type="android"),
            ],
            types.SourceFilter.of(),
            [
                model.UserAssociation.of(types.SpUid.of(1), types.StoreId.from_("token-ios-1"), types.Platform.IOS),
                model.UserAssociation.of(types.SpUid.of(2), types.StoreId.from_("token-android-1"), types.Platform.ANDROID),
            ],
            id="フィルタなしで全件を昇順で取得できる",
        ),
        pytest.param(
            [],
            types.SourceFilter.of(platform=types.Platform.ANDROID),
            [],
            id="条件に一致するレコードがない場合は空リストを返す",
        ),
    ],
)
async def test_user_association_datasourceのfind_all(
    db_session,
    fixtures: list[UserAssociationRecord],
    filter_: types.SourceFilter,
    expected: list[model.UserAssociation],
) -> None:
    # given
    await _insert_records(db_session, fixtures)

    # and: SUT 構築
    sut = UserAssociationDatasource(db_session)

    # when
    got = await sut.find_all(filter_)

    # then
    assert got == expected
```

### db_session fixture（PostgreSQL / SQLAlchemy 2.0）

DB 統合テストでは、各テストの前後でトランザクションを開始・ロールバックして状態を隔離します。`conftest.py` の fixture にまとめます。

```python
# tests/app/infrastructure/postgres/conftest.py
"""DB 統合テストの接続・トランザクション fixture。"""

import os
from collections.abc import AsyncIterator

import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine


def _dsn() -> str:
    """テスト用 DSN を返す（未設定時はローカルの既定値）。"""
    return os.environ.get(
        "TEST_DATASOURCE",
        "postgresql+asyncpg://postgres:postgres@127.0.0.1:15432/testdb",
    )


@pytest_asyncio.fixture
async def db_session() -> AsyncIterator[AsyncSession]:
    """1 テストにつき 1 トランザクションを張り、終了時にロールバックする。"""
    engine = create_async_engine(_dsn())
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as session:
            async with session.begin():
                yield session
                # with ブロック内で例外を送出せずに抜けると commit されるため、
                # テスト隔離のため明示的にロールバックする
                await session.rollback()
    finally:
        await engine.dispose()
```

接続先 DSN は環境変数 `TEST_DATASOURCE` で切り替え、未設定時はローカルの既定値を使います（[ローカル開発環境規約](local-dev.md) の docker-compose 起動先と合わせる）。

### fixtures の型

fixture データには DTO の行クラスのリストを使い、parametrize のパラメータ型として明示します。SQL は `.sql` に外出しし `importlib.resources` 経由で読み込みます（テストでも本番と同じ SQL 管理方針に従う。[インフラストラクチャ規約](infrastructure.md) を参照）。

```python
import importlib.resources

from sqlalchemy import text


async def _insert_records(session: AsyncSession, records: list[UserAssociationRecord]) -> None:
    """fixture レコードを一括 INSERT する。"""
    sql = importlib.resources.read_text(
        "app.infrastructure.postgres.sql", "insert_user_association.sql"
    )
    await session.execute(
        text(sql),
        [dataclasses.asdict(r) for r in records],
    )
```

### 注意点

* DB 統合テストは `@pytest.mark.serial` で直列実行する（同一テーブルを共有するため `pytest-xdist` の並列対象から外す）
* `# given`, `# and`, `# when`, `# then` コメントを使用する
* DB が自動設定するフィールド（`created_at`, `updated_at`, 採番 `id` など）は比較前に正規化してから `==` で比較する

## 時刻のテスト

現在時刻に依存するエンティティは、時刻取得を差し替え可能な関数に集約します（[ドメインモデル設計規約](domain-model.md) の「時刻の注入」）。テストでは `pytest` の fixture で setup / teardown します。

```python
# src/app/domain/model/_clock.py — プロダクションコード（差し替え点）
import datetime as dt
from collections.abc import Callable

_now_func: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.UTC)


def now() -> dt.datetime:
    """現在時刻を返す。テスト時は set_now で固定できる。"""
    return _now_func()


def set_now(func: Callable[[], dt.datetime]) -> None:
    """時刻取得関数を差し替える（テスト用）。"""
    global _now_func
    _now_func = func


def reset_now() -> None:
    """時刻取得関数を既定値に戻す（テスト用）。"""
    global _now_func
    _now_func = lambda: dt.datetime.now(dt.UTC)
```

```python
# tests/app/domain/model/test_user.py
import datetime as dt
from collections.abc import Iterator

import pytest

from app.domain.model import User, _clock
from app.domain.types import UserId


@pytest.fixture
def fixed_clock() -> Iterator[dt.datetime]:
    """現在時刻を固定する fixture。終了時に既定へ戻す。"""
    fixed = dt.datetime(2024, 1, 1, 12, 0, 0, tzinfo=dt.UTC)
    _clock.set_now(lambda: fixed)
    try:
        yield fixed
    finally:
        _clock.reset_now()


def test_user_newは生成時刻をupdated_atに設定する(fixed_clock: dt.datetime) -> None:
    # when
    sut = User.new(user_id=UserId.of("u-1"), email=None, display_name="名前", user_type=...)

    # then
    assert sut.updated_at == fixed_clock
```

`Clock` プロトコルをコンストラクタ注入する DI 構成を採る場合は、テストでは固定時刻を返す fake を注入します（グローバル差し替えより副作用が局所化される）。

## E2E テスト

### 基本方針

* **HTTP API の E2E は FastAPI の** `TestClient` / `httpx.AsyncClient` **でアプリケーションを起動して検証する**
* **テストファイルは** `tests/e2e/` ディレクトリに配置する
* **機能単位でファイルを分割** する
* 外部依存（DB・キュー）は docker-compose で起動した実サービスに対して実行する（[ローカル開発環境規約](local-dev.md)）

### httpx + ASGI でのテスト

`create_app()`（[アーキテクチャ規約](architecture.md) のアプリケーションファクトリ）を ASGI トランスポートで直接叩き、ネットワークを介さず E2E を検証します。

```python
# tests/e2e/test_user_api.py
import httpx
import pytest

from app.main import create_app


@pytest.mark.serial
@pytest.mark.asyncio
async def test_get_userはユーザーを返す() -> None:
    transport = httpx.ASGITransport(app=create_app())
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        # when
        res = await client.get("/users/user-123")

    # then
    assert res.status_code == 200
    assert res.json()["id"] == "user-123"
```

### Makefile / タスクランナーでのテスト実行

```makefile
test: ## ユニットテストを実行（DB 不要のテスト）
	@uv run pytest -n auto -m "not serial"

test/e2e: ## E2E・DB 統合テストを直列で実行
	@uv run pytest -m serial
```

## 関連ドキュメント

* [プロジェクト構成規約](project-structure.md) - src レイアウト、tests/ 構成、uv
* [型システムと Optional 規約](type-system.md) - `T | None` ・値オブジェクトのテスト
* [ドメインモデル設計規約](domain-model.md) - エンティティ／値オブジェクトの等価性、時刻の注入
* [HTTP ハンドラ規約](http-handler.md) - FastAPI ハンドラのテスト、Depends の差し替え
* [ローカル開発環境規約](local-dev.md) - docker-compose、DB 接続、E2E テスト環境
* [インフラストラクチャ規約](infrastructure.md) - SQLAlchemy、SQL の外出し（importlib.resources）、datasource パターン

## 参考資料

* [pytest](https://docs.pytest.org/)
* [pytest – parametrize](https://docs.pytest.org/en/stable/how-to/parametrize.html)
* [pytest-asyncio](https://pytest-asyncio.readthedocs.io/)
* [pytest-mock](https://pytest-mock.readthedocs.io/)
* [unittest.mock](https://docs.python.org/3/library/unittest.mock.html)
* [pytest-xdist](https://pytest-xdist.readthedocs.io/)
