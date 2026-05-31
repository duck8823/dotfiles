## Structure-Behavior Design Note

### Requirement summary
- 目的: AI orchestrator が `duck8823/*` のレビュー済み PR で merge 待ちになって自律進行を止めない。
- 現状: `[auto_review].policy` は local orchestrator の `gh pr merge` に「具体的 PR の明示指示」を必須にしており、Traceary / calorie-balance / dotfiles の delivery loop が merge 待ちで blocked になる。
- 期待する振る舞い: `duck8823` org / owner の PR だけ、通常の品質 gate を満たせば AI orchestrator が自律的に `gh pr merge` して次へ進める。他 owner/org では自律 merge しない。
- 非対象: main 直 push、production deploy / store upload、release tag / GitHub Release 作成、外部 AI worker への merge 権限委譲、branch protection の迂回。

### Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Repository owner gate | GitHub owner/org | `duck8823` だけ autonomous merge allowed | owner が `duck8823` 以外なら user-specific merge instruction が必要 |
| Local orchestrator | current foreground AI | 品質 gate を確認して `gh pr merge` を実行できる | delegated worker / reviewer には merge を許可しない |
| Merge quality gate | PR state / checks / reviews / evidence | draft でなく、blocking review なし、checks pass or no-checks-reported、branch protection respect | failing / cancelled / pending / auth/communication error は merge 不可 |
| Release/deploy gate | tag / release / store upload / infra apply | explicit approval required | autonomous merge exception の対象外 |

### Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| Codex policy wording | `codex/config.toml.template`, `codex/instructions.md` | Codex approval reviewer / orchestrator 判断の source | Claude hook alone では Codex の approval gate を変えられない |
| Whole delivery loop | `codex/skills/autonomous-pr-flow/SKILL.md` | merge 後に次タスクへ進む運用を定義 | 各 repo の個別 CLAUDE.md に分散しない |
| GitHub command guard docs | Claude guidelines / README | hook が要求する ticket / review evidence と整合させる | hook の品質 gate 自体は既に owner 非依存で検証している |

### Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| `[auto_review].policy` | Codex approval reviewer / orchestrator | Guardian implementation detail | policy gate を弱めず、owner/gate 条件を明記 |
| `gh pr merge` | local orchestrator | GitHub branch protection / mergeability | fail/cancel/pending/auth error は stop; no checks reported のみ CI 未設定扱い |
| `autonomous-pr-flow` | Codex current orchestrator | repo-specific command details | other org autonomous merge は forbidden |

### Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| duck8823 autonomous merge allowed | `duck8823/*` PR, ready, review evidence, checks pass | orchestrator reaches merge step | may run `gh pr merge` without asking for another merge approval | docs/policy grep |
| other org autonomous merge forbidden | non-`duck8823` PR | orchestrator reaches merge step | must not autonomously run `gh pr merge`; requires explicit current-turn PR instruction | docs/policy grep |
| deploy remains guarded | release tag / store upload / infra apply | autonomous merge exception exists | still requires explicit approval | docs/policy grep |

### TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| owner-scoped merge policy | grep cannot find `duck8823` owner exception | update policy docs/templates | keep wording centralized and consistent |
| non-duck8823 denial | grep cannot find other-org prohibition | update instructions / autonomous flow | avoid broad `gh pr merge` allow rule |
| release/deploy exclusion | grep cannot find exclusion | update policy text | no code hook change unless future enforcement needs it |

### Risks / rollback
- 手続き化リスク: policy text が複数ファイルに散るため、`rg "duck8823.*autonomous"` で同期確認する。
- premature abstraction リスク: owner allowlist を script 化しない。現時点の要件は `duck8823` 固定。
- migration / compatibility: existing hook quality gates remain unchanged; install sync updates generated config.
- rollback trigger: owner 判定が広すぎる、または non-duck8823 で merge が通る運用が観測されたら exception を explicit-approval only に戻す。
