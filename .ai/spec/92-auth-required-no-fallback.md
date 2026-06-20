# Structure-Behavior Design Note: Issue #92 auth-required no fallback

## Requirement summary
- 目的: Claude / Antigravity / Gemini / Codex の CLI 認証切れを、quota や一時失敗と同じ fallback 可能な失敗として扱わない。
- 現状: `scripts/multi-ai-research.sh` は `auth_prompt` を分類できるが、後続 engine を続行するため、fallback engine が余計に実行されうる。
- 期待する振る舞い: 実行済み engine の出力が `auth_prompt` に分類された時点で後続 engine を止め、status / summary に `AUTH_REQUIRED` を残し、終了コード 78 で停止する。
- 非対象: CLI のログイン修復、ブラウザ認証起動、外部 AI の追加代替実行。

## Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Engine run | ok / auth_prompt / transient failure | 1 engine の実行結果を分類する | `auth_prompt` は fallback 可能な失敗ではない |
| Research bundle | running / auth-required / completed | status と summary を保存する | 停止理由を後から監査できる |
| Fallback boundary | allowed / prohibited | 後続 engine 実行可否を決める | 認証失敗時は後続 engine を実行しない |

## Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| 結果分類 | `classify_result` | 既に `auth_prompt` を分類しているため維持 | engine-specific runner は分類を持たない |
| 停止判断 | main engine loop | 後続 engine 実行の境界を持つ | individual runner は全体順序を知らない |
| 回帰検証 | `tests/test_agent_policy_scripts.py` | CLI script の観測可能な振る舞いを守る | docs-only tests では実行停止を検証できない |

## Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| `status.md` | reviewer / orchestrator | grep details and engine stderr | `## AUTH_REQUIRED` と `fallback: not executed` を記録 |
| process exit code | caller / CI / hook | engine-specific auth text | auth required は 78 |
| per-engine output file | reviewer / audit | stdout / stderr merge | 実行された engine のみ result file を持つ |

## Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| 認証失敗で停止 | `claude,codex`、Claude が `Please log in to continue.` を出す | script 実行 | exit 78、`AUTH_REQUIRED` 記録、Codex marker が作られない | script regression |
| Antigravity 認証失敗で停止 | `antigravity,codex`、Antigravity が browser auth prompt を出す | script 実行 | exit 78、`AUTH_REQUIRED` 記録、Codex marker が作られない | script regression |
| 認証らしい一般文は誤検知しない | research output に `users may sign in to apps` が含まれる | script 実行 | classification は `ok` | script regression |

## TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| auth_prompt で後続 engine を止める | Codex marker が作られてしまう | main loop が `AUTH_REQUIRED` を記録して `break`、最後に exit 78 | 必要なら status 書き込みを関数化 |

## Risks / rollback
- 手続き化リスク: main loop に停止処理が増えるが、全体順序の責務は main loop が持つため許容。
- premature abstraction リスク: 今回は新しい coordinator 抽象を作らず、既存 loop に最小分岐を追加する。
- migration / compatibility: dry-run と no effective engines の既存 exit code は変更しない。
- rollback trigger: auth required 以外の transient failure でも後続 engine が止まる場合は revert する。
