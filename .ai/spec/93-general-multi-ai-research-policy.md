# Structure-Behavior Design Note — Issue #93 general multi-AI research policy

## Requirement summary

- 目的: ユーザーが明示した場合に限り、Claude / Gemini / Codex CLI へ public Web の read-only 一般調査を安全に委譲できるようにする。
- 現状: External AI delegation exception は trusted repository / git worktree と 1 ticket / 1 PR を前提にしており、repo context を送らない一般調査も `policy_denied` になる。
- 期待する振る舞い: repo/source/workspace packet を送らない general research は、ユーザー明示・public/non-sensitive context・headless read-only・audit evidence の条件付きで許可する。
- 非対象: 実装 write、PR merge、deploy、release、infra apply、main direct push、repo/home dump、secrets 送信の許可。

## Conceptual model

| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Delegation path | scoped-repo / general-web | 外部 AI に渡してよい context を path ごとに分ける | general-web は local files / source / workspace packet を送らない |
| User consent | current-turn explicit / absent | current-turn explicit の場合だけ general-web path を開く | 過去の同意や曖昧な示唆では足りない |
| Context packet | workspace packet / public prompt only | repo 調査では packet hash、general では prompt hash を監査 | general に repo content を混ぜたら scoped-repo path に戻す |
| Failure classification | ok / auth_prompt / policy_denied / etc. | 失敗を成果物として記録 | auth/login は fallback しない |

## Responsibility assignment

| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| Delegation allow/deny rule | `codex/config.toml.template` `[auto_review].policy` | Codex approval reviewer の source of truth | individual skill にだけ置くと gate がずれる |
| Operational guidance | `codex/instructions.md`, `README.md`, `conventions/ai/*.md` | 人間/AI が同じ境界で判断する | script だけだと policy 意図が見えない |
| Research execution | `scripts/multi-ai-research.sh` | general mode は既に local context を含めない | 今回は write/merge 権限を増やさない |
| Review evidence | PR comment / docs | merge gate の証跡 | 会話だけに残さない |

## Boundaries / interfaces

| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| general web research path | Claude/Gemini/Codex CLI | local repo/files are unavailable by design | file access/auth/secrets 要求で stop |
| scoped repo path | PR/repo review workflows | sanitized packet generation | sensitive path/content で skip |
| local policy overrides | user/machine | engine disablement / approval mode | disabled は `local_policy_disabled` |

## Behavior tests

| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| general exception is documented | policy template | grep policy text | user-explicit/read-only/public/audit/auth-stop が揃う | docs/test |
| normal repo gate remains | policy template | inspect ticket/repo path | 1 ticket / 1 PR と secret 禁止が残る | docs/test |
| guidance is synchronized | docs/skills | grep key phrases | README / Codex instructions / multi-ai research docs が同じ境界を示す | docs/test |
| general dry-run excludes workspace context | `multi-ai-research.sh --mode general --dry-run` | inspect status/prompt artifacts | no packet metadata / workspace packet / repo diff / tracked source marker appears | behavior test |

## TDD plan

| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| policy text has narrow general path | `tests/test_policy_text.py` fails on missing phrase | config/instructions/docs updated | avoid duplicating contradictory wording |
| general mode does not leak workspace context | `tests/test_policy_text.py` runs general dry-run and fails on packet/source markers | prompt/status contain only safety template and topic | keep runtime behavior test lightweight |
| managed install still works | installer sync test | no regression | none |

## Risks / rollback

- 手続き化リスク: policy wording が長くなり、判断が docs 間でずれる。
- premature abstraction リスク: engine-specific flags を policy に入れすぎない。
- migration / compatibility: install 後、local `~/.codex/config.toml` に local edits がある場合は `.dotfiles-new` になるため手動適用が必要な可能性。
- rollback trigger: general research path が repo/source/private data 送信に使われたら revert し、ticket/PR scoped path のみに戻す。
