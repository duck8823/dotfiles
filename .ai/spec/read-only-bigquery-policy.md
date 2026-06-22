## Structure-Behavior Design Note

### Requirement summary
- 目的: ユーザーが明示的に BigQuery / BQ / `bq` 確認を依頼した場合、sandbox 内の gcloud credential cache 書き込み制限で失敗せず、Codex local orchestrator が read-only に限定して sandbox 外実行できるようにする。
- 現状: `bq` は sandbox 内で `~/.config/gcloud/credentials.db` 等へアクセスできず失敗する。既存 `[auto_review].policy` は external AI delegation 例外中心で、local read-only BigQuery の明示例外がない。
- 期待する振る舞い: `bq query` / `bq show` / `bq ls` の read-only inspection だけを許可し、production data は aggregate / metadata / bounded query に最小化する。
- 非対象: `bq rm` / `bq mk` / `bq load` / `bq cp` / `bq extract`、DDL / DML / export、auth login、browser login、secret / raw PII の取得、外部 AI への data 送信。

### Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Local BigQuery inspection | User-explicit | Runs `bq` outside sandbox | Read-only command classes only |
| Credential cache | Host local | SDK may refresh token/cache | Never print/copy/summarize/commit/upload credentials |
| Query result | Minimized | Aggregate/metadata/small limit | No raw personal data/device tokens/endpoint IDs/uid lists by default |

### Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| Sandbox escalation decision | `[auto_review].policy` | It gates `require_escalated` commands | Repository AGENTS; project-specific only |
| Operator guidance | `codex/instructions.md` | Runtime behavior for Codex | README; human summary only |
| Shared documentation | `README.md` | Explain why/when allowed | Live config; generated/local state |

### Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| `bq query/show/ls` | Codex local orchestrator | gcloud token refresh/cache files | Stop on auth login/browser login |
| BigQuery result output | User/report | Raw rows and sensitive fields | Summarize aggregates and residual risks |

### Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| Policy includes BQ exception | policy text | test reads template | Required BQ guardrails exist | unit/text |
| Runtime instructions include BQ exception | instructions | test reads markdown | Required runtime guardrails exist | unit/text |
| README documents BQ exception | README | test reads markdown | Human-facing guardrails exist | unit/text |

### TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| Policy text coverage | Add assertions for missing BQ exception | Add template/instructions/README text | Keep duplicated wording minimal |

### Risks / rollback
- 手続き化リスク: policy text が長くなる。BigQuery 例外を isolated section にして external AI delegation と混ぜない。
- premature abstraction リスク: BigQuery 以外の external data-source CLI へ広げない。
- migration / compatibility: `config.toml.template` 更新後、install/sync が必要。live `~/.codex/config.toml` は別途反映する。
- rollback trigger: auto_review が過剰許可と判断する、または実運用で sensitive data 取得リスクが高いと判断された場合はこの例外 section を削除する。
