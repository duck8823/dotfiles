# Structure-Behavior Design Note: Issue #96 token budget guards

## Requirement summary
- 目的: MCP connector / Traceary / Gmail を使う調査で、巨大 tool payload による Codex token 消費を抑える。
- 現状: shell 出力は `rtk` で削減できるが、MCP connector の返却 payload と Traceary 診断 JSON は別経路で context に入る。
- 期待する振る舞い: 初手は metadata / snippet / bounded body に限定し、raw JSON・全文・添付は選別後だけ読む。巨大出力は file path + 要約へ逃がす。
- 非対象: Traceary 本体の read surface 修正、Gmail connector のサーバー側仕様変更、品質 gate を下げるモデル格下げ。

## Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Tool payload | bounded / raw / full body | Codex context に入る外部 connector 出力 | `rtk` では削減できない |
| Triage read | metadata / selected body | 候補を絞ってから本文を読む | 初手で bulk body を読まない |
| Traceary diagnostic | narrow / snapshot / full transcript | session・hook・event を診断する | 現在 session の全文読みで自己増幅しない |
| Evidence artifact | summary / raw file path | 検証証跡を残す | PR コメントへ raw JSON を貼らない |

## Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| Token budget policy | `conventions/ai/token-budget.md` | connector-heavy 手順の source of truth | 個別 connector 実装は repo 外 |
| Traceary read guidance | `conventions/ai/agent-hooks-observability.md` | hook / session 診断の読み方を持つ | Traceary 本体 bug 修正は `duck8823/traceary` |
| Codex operational default | `codex/instructions.md` | Codex current orchestrator の実行規約 | live `~/.codex/config.toml` は個人設定 |
| Regression check | `tests/test_policy_text.py` | 重要な運用文言の drift を検知する | 文章全体の品質レビューは human / AI reviewer |

## Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| MCP connector | Codex / Claude / Antigravity | connector server の payload shape | limit / max_results / pageSize / body_limit を使い、全文は選別後だけ |
| Traceary CLI | current orchestrator | SQLite / hook internals | list/search/fields/limit で狭く読む |
| PR / final answer | reviewer / user | raw JSON / transcript | 要約と path を返す |

## Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| policy text drift | docs guidance | `tests/test_policy_text.py` | MCP / Gmail / Traceary / file path summary の必須文言が存在する | lightweight |
| docs-only safety | docs changes | `git diff --check` / grep | raw output pasted or English-only drift がない | manual/local |

## TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| connector guardrail text exists | `test_policy_text.py` に必須文言を追加して失敗させる | token-budget / observability / codex instructions を更新 | 重複が増えたら source-of-truth 参照へ寄せる |

## Risks / rollback
- 手続き化リスク: guidance が長くなる。token-budget を source of truth にし、Codex instructions は実行時の要点に絞る。
- premature abstraction リスク: connector wrapper は作らず、まず運用手順と drift test に留める。
- migration / compatibility: docs-only。既存 hooks / scripts の動作は変更しない。
- rollback trigger: guidance が実際の Traceary CLI / MCP tool 名と乖離した場合は、該当コマンド例だけ修正する。
