---
globs: "**/*.spec.ts,**/*.spec.tsx,**/*.spec.mts,**/*.spec.cts,**/*.spec.js,**/*.spec.jsx,**/*.spec.mjs,**/*.spec.cjs,**/*.test.ts,**/*.test.tsx,**/*.test.mts,**/*.test.cts,**/*.test.js,**/*.test.jsx,**/*.test.mjs,**/*.test.cjs"
---

# Playwright QA evidence rules

この rule は UI / E2E / QA 変更のレビューと実装で、Playwright の locator・assertion・証跡を安定運用するための最小規約です。特定プロジェクトの構成に依存しない。

## Locator policy

- ユーザーが見て操作する意味に近い locator を優先する。基本順は `getByRole` + accessible name、`getByLabel`、`getByPlaceholder`、`getByText`、`getByTestId`。
- `getByTestId` は、ユーザー可視の role / label / text で一意に取れない場合、または l10n / dynamic text の影響を避けるための安定契約として使う。
- `locator.filter({ has, hasText })` や locator chain で対象範囲を狭め、意図した要素が一意であることを `toHaveCount(1)` 等で必要に応じて確認する。
- `first()` / `last()` / `nth()` は、順序自体が仕様である場合を除き避ける。使う場合は、なぜ順序に依存してよいかをテスト名またはコメントで明示する。
- CSS / XPath / DOM 構造依存 selector は fallback 扱いにし、review では「ユーザー可視 locator に置き換えられない理由」を確認する。

## Assertion policy

- UI の状態確認は web-first assertion を優先する。例: `await expect(locator).toBeVisible()`, `toHaveText()`, `toHaveURL()`, `toHaveCount()`。
- `expect(await locator.textContent()).toBe(...)` のように値を先に取り出して通常 assertion する形は、retry が効かず flaky になりやすいので避ける。
- `waitForTimeout()` は原則禁止。animation / debounce / polling 等の待機は、locator assertion、response assertion、`expect.poll`、または明示的な状態 API に置き換える。
- click / fill の直後には、ユーザーに見える状態変化または domain result を assertion する。操作だけで終わるテストは QA 証跡として弱い。
- visual assertion は、目的が見た目の回帰検知である場合だけ使う。しきい値や masking の理由を config / test から読み取れるようにする。

## Evidence policy

- PR には UI / E2E 変更で何を確認したかを残す。最低限、実行コマンド、対象ブラウザ / device、成功・失敗、確認した user-visible behavior を記録する。
- CI 失敗調査では trace を第一候補にする。trace は timeline、DOM snapshot、console、network を確認できるため、動画・静止画だけより原因調査に向く。
- trace は通常 `on-first-retry` または failure 時に絞る。全テスト常時 `trace: "on"` は重く、artifact の保持・共有コストが高いため原則避ける。
- screenshot / video は補助証跡として扱う。screenshot は視覚差分や状態説明、video は再現手順の説明に使い、trace の代替にしない。
- 外部 AI / PR コメントに共有する場合は、trace / video / screenshot の raw dump ではなく、artifact path / URL、失敗箇所、要約、必要な短いスクリーンショットに蒸留する。個人データ・token・内部 URL が写る場合は mask / redaction を優先する。

## PR review checklist

- [ ] locator が user-visible contract または安定した `testId` contract に基づいている
- [ ] CSS / XPath / `nth()` 依存に合理的な理由がある
- [ ] user action の後に web-first assertion がある
- [ ] `waitForTimeout()` / manual sleep がない、または例外理由がある
- [ ] flaky 回避のために timeout をむやみに伸ばしていない
- [ ] trace / screenshot / video の設定が目的に対して過剰でない
- [ ] PR body または review comment に実行コマンドと artifact path / URL / 未実行理由がある
- [ ] 失敗時は trace から action timeline / DOM snapshot / console / network のどこを確認したかが書かれている
- [ ] external AI に渡す証跡は summary + path / URL に蒸留され、raw trace / private data を含めていない

## Anti-patterns

| Anti-pattern | Risk | Preferred approach |
|---|---|---|
| `page.locator(".btn-primary")` や深い CSS selector | DOM / style 変更で壊れる | `getByRole("button", { name: "..." })` または `getByTestId` |
| `locator.nth(0)` で曖昧さを潰す | 予期せぬ要素を操作する | role / label / filter で一意化 |
| `waitForTimeout(1000)` | 遅い環境で flaky、速い環境で無駄 | web-first assertion / response / state poll |
| `expect(await locator.textContent()).toBe(...)` | auto-retry されない | `await expect(locator).toHaveText(...)` |
| action だけで assertion なし | 何が成功条件か不明 | user-visible state / URL / data result を assertion |
| trace / video / screenshot を常時全部保存 | CI コスト・外部共有リスクが高い | failure / retry 中心、PR には要約と artifact path / URL |
| raw trace を外部 AI にそのまま渡す | 個人データ・token・内部情報露出 | sanitized summary、必要最小 screenshot、artifact link |

## 参考一次情報

- Playwright Best Practices: https://playwright.dev/docs/best-practices
- Playwright Locators: https://playwright.dev/docs/locators
- Playwright Assertions: https://playwright.dev/docs/test-assertions
- Playwright Trace Viewer: https://playwright.dev/docs/trace-viewer-intro
- Playwright Videos: https://playwright.dev/docs/videos
- Playwright Screenshots: https://playwright.dev/docs/screenshots
