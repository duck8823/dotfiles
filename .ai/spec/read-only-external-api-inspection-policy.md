## Structure-Behavior Design Note

### Requirement summary
- 目的: Codex local orchestrator が、ユーザーの明示指示に基づき外部 API / SaaS / data service を参照する調査を、AI 管理フローの一部として安全に実行できるようにする。
- 現状: BigQuery など一部 CLI / SDK は sandbox 内では host 側の認証キャッシュに触れず失敗する。既存 policy は external AI delegation 例外が中心で、local orchestrator が証跡取得のために read-only API 参照を行う境界が BigQuery 個別に寄りすぎている。
- 期待する振る舞い: 外部 API 参照は「外部 AI への委譲」ではなく local evidence collection として扱い、ユーザーが求めた具体的な API / resource に限って read-only / bounded / auditable に sandbox 外実行できる。
- 非対象: create / update / delete / mutate / export / import / upload / deploy / auth login、browser login、secret / raw PII / credential の取得、raw API response や production data の外部 AI 送信。

### Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| External API inspection | User-explicit and scoped | Runs read-only CLI / SDK / HTTP request outside sandbox when sandbox blocks auth/cache | Concrete provider, resource, and question only |
| Credential cache | Host local | Provider SDK may read/update token/cache as side effect | Never print/copy/summarize/commit/upload credentials |
| API result | Minimized evidence | Summarized for the user and optionally sanitized for AI review | No raw personal data, production dumps, secret values, tokens, or broad identifiers by default |
| AI-managed workflow | Audited orchestration | Local orchestrator gathers evidence; external AI receives only sanitized summaries when policy allows | No delegation of API access, login, mutation, or raw data handling |

### Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| Sandbox escalation decision | `[auto_review].policy` | It gates `require_escalated` commands | Repository AGENTS; project-specific only |
| Operator guidance | `codex/instructions.md` | Runtime behavior for Codex | README; human summary only |
| Shared documentation | `README.md` | Explain why/when allowed | Live config; generated/local state |
| Regression coverage | `tests/test_policy_text.py` | Prevents policy drift back to one provider | Human review alone is too easy to miss |

### Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| Read-only provider API / CLI / SDK | Codex local orchestrator | Provider token refresh/cache files | Stop on auth login/browser login or mutation requirement |
| API result output | User/report | Raw rows, objects, and sensitive fields | Summarize aggregates/metadata and residual risks |
| Sanitized evidence packet | External AI reviewer, when allowed | Raw API payload and credentials | Share only minimized summary; never raw production/API data |

### Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| Policy includes external API exception | policy text | test reads template | Required read-only API guardrails exist | unit/text |
| Runtime instructions include external API exception | instructions | test reads markdown | Required runtime guardrails exist | unit/text |
| README documents external API exception | README | test reads markdown | Human-facing guardrails exist | unit/text |

### TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| Policy text coverage | Replace BigQuery-only assertions with external API inspection assertions | Add template/instructions/README text | Keep provider-specific examples secondary |

### Risks / rollback
- 手続き化リスク: 「外部 API 全般」が過剰許可に見える。user-explicit / concrete resource / read-only / bounded / no raw data sharing を不変条件として明記する。
- premature abstraction リスク: すべての API に provider-specific 安全判定を作ろうとしない。汎用の禁止動作と、BigQuery などの例示に留める。
- migration / compatibility: `config.toml.template` 更新後、install/sync が必要。live `~/.codex/config.toml` は別途反映する。
- rollback trigger: auto_review が過剰許可と判断する、または実運用で sensitive data 取得リスクが高いと判断された場合はこの例外 section を削除し、provider-specific 例外へ戻す。
