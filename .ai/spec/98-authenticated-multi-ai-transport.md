## Structure-Behavior Design Note

### Requirement summary
- 目的: Claude / Antigravity / Codex / legacy Gemini が相互に調査・委譲・レビューできる状態を維持しつつ、外部 AI CLI を sandbox に閉じ込めた結果 CLI 認証情報まで見えなくなって `auth_prompt` になる運用ミスを防ぐ。
- 現状: multi-AI research / review は headless + sandbox/read-only/plan を重視しているが、Antigravity など一部 CLI は `--sandbox` 実行時に認証済み host surface と切り離されることがある。認証失敗は fallback 禁止なので、単なる実行 surface の選択ミスでもレビュー全体が停止しやすい。
- 期待する振る舞い:
  - 外部 AI へ渡す context は従来通り sanitized packet / source-diff bundle に限定する。
  - CLI プロセスは host の認証済み設定・keychain を使える surface で起動する。
  - sandbox / plan / read-only は「モデルに許す tool / filesystem / write の境界」として扱い、認証情報を隠す境界として使わない。
  - Antigravity の sandbox 実行が `auth_prompt` だけで失敗した場合は、同じ engine・同じ prompt・空 cwd・NO_BROWSER・追加 directory なしで **1 回だけ authenticated transport retry** を許可する。
  - retry 後も認証プロンプトなら fallback せず停止し、ユーザーに CLI 認証状態の修正を促す。
- 非対象: 外部 AI への secret 共有、browser login の自動化、write/commit/push/PR/merge/deploy の委譲、sandbox / Guardian / approval の恒久的な弱体化。

### Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Authenticated transport surface | host-authenticated / sandbox-auth-failed / unauthenticated | CLI 起動時に既存ログイン状態を利用する | 認証情報そのものは prompt / packet に含めない |
| Delegation data boundary | general / workspace packet / explicit packet / PR bundle | 外部 AI に渡す情報を蒸留する | `.env*`, tokens, credentials, shell history, repo 外 raw private data は送らない |
| Tool permission boundary | sandbox / plan / read-only / no-tools | モデルが読める・書ける対象を制限する | auth transport retry でも empty cwd / no add-dir / headless / NO_BROWSER を維持 |
| Auth failure classification | auth_prompt / auth_retry_host / ok | 同一 engine retry と最終停止を区別する | 別 engine への暗黙 fallback で auth 不備を隠さない |

### Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| multi-AI 実行 surface の実装 | `scripts/multi-ai-research.sh` | 実際に headless CLI を起動し status bundle を作る | 各 agent prompt は実装詳細を重複させない |
| policy / allowed boundary | `codex/config.toml.template`, `codex/instructions.md`, conventions | delegation gate の正本 | 個別 command snippets は正本にしない |
| Claude / Codex review 運用の投影 | `claude/commands/review-and-merge.md`, `codex/skills/multi-ai-review/SKILL.md` | 実運用で raw `agy --sandbox` を使う箇所 | README は概要だけ |
| local override | `scripts/lib/agent-policy.sh`, `conventions/ai/local-agent-policy.md` | machine ごとの engine disable / sandbox / model を扱う | repo policy は local auth 状態を持たない |

### Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| `MULTI_AI_ANTIGRAVITY_AUTH_RETRY_WITHOUT_SANDBOX` | multi-ai scripts / docs | sandbox が auth を隠すかどうか | `true` なら同一 engine 1 回 retry、`false` なら従来通り停止 |
| `status.md` auth retry fields | orchestrator / PR comment | engine stderr 全量 | initial sandbox attempt と final classification を分けて記録 |
| Auth prompt detector | research / review runner | CLI 固有文言 | `auth_prompt` は別 engine fallback 禁止 |
| Authenticated transport retry | Antigravity read-only/scout | `--sandbox` を外す実装詳細 | empty cwd / NO_BROWSER / no add-dir / same prompt 以外に拡張しない |

### Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| sandbox auth failure retry | fake `agy` が `--sandbox` で `not authenticated`、no-sandbox で成功 | `multi-ai-research.sh --engines antigravity,codex` | Antigravity は `ok`、retry 証跡が status に残り、Codex へ進む | script |
| genuine auth failure stop | fake `agy` が sandbox/no-sandbox とも auth prompt | `multi-ai-research.sh --engines antigravity,codex` | exit 78、Codex は未実行、fallback not executed | script |
| retry disabled | local policy で retry=false | sandbox auth failure | 従来通り `auth_prompt` で停止 | script |
| policy text consistency | policy / README / conventions | grep test | authenticated transport と fallback 禁止が明記される | docs |

### TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| Antigravity retry succeeds | fake `agy` test を追加して現状失敗を確認 | `run_antigravity` に retry branch を追加 | classification / retry status を関数化 |
| Genuine auth still stops | no-sandbox も auth を返す fake test | final classification が `auth_prompt` のときのみ loop break | auth detector の共通化 |
| Docs sync | `test_policy_text.py` に required phrases 追加 | policy / conventions / commands を更新 | redundant snippets を helper 参照へ寄せる |

### Risks / rollback
- 手続き化リスク: review command と research script に同じ auth retry ロジックが散らばる。正本を conventions + script に置き、command snippets は同じ用語を使う。
- premature abstraction リスク: 汎用 runner 新設は避け、まず既存 `multi-ai-research.sh` と review 運用文書を最小変更する。
- migration / compatibility: 既定は sandbox-first のまま。新 retry は Antigravity の read-only/scout かつ auth_prompt の場合だけ発火する。
- rollback trigger: no-sandbox retry が想定外の file access / write を誘発する evidence が出た場合、`MULTI_AI_ANTIGRAVITY_AUTH_RETRY_WITHOUT_SANDBOX=false` を既定に戻し、manual auth preflight のみにする。
