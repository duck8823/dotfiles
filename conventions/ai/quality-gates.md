# AI quality gates

この文書は、AI agent が自律進行するときの品質ゲートを定義する。
進行ルールは `conventions/ai/multi-ai-agent-operations.md`、レビュー運用は
`claude/guidelines/review-workflow.md` を参照し、この文書は **品質 artifact と gate 条件** に限定する。

## 方針

- Gate は Claude / Codex / Gemini などの AI 名ではなく、role / capability に対して定義する。
- Hard block は決定論的に確認できる条件に限定する。LLM reviewer の主観的指摘だけで merge を永久停止しない。
- 小変更を止めない。docs-only / typo / formatting / 既存パターンの単純横展開には軽量 lane を用意する。
- High risk 変更は、実装前に ADR または同等の設計判断・rollback・検証方針を残す。ADR の適用条件と template は `conventions/ai/adr-guidance.md` を参照する。
- 重大度は最終的に MUST / SHOULD / NIT に正規化する。CRITICAL / HIGH / MAJOR は原則 MUST、MINOR / WARNING は SHOULD または NIT として integrator role が triage する。
- 外部 AI が local policy / quota / auth / permission で失敗した場合は、失敗分類を記録し、代替 reviewer / local verification / CI で補完する。

## Risk lanes

| Lane | 例 | 必須 artifact |
|---|---|---|
| Docs-only light | typo / formatting / 非規範的 docs のみ | `git diff --check`、関連 grep、軽量テストまたは構文チェック |
| Policy docs | gate / workflow / security / release / agent policy を変える docs | Low または Medium として扱い、review evidence、関連 hook / workflow との整合性確認、検証結果を残す |
| Low | 既存パターンに沿う小変更、単一責務の修正 | 要求要約、変更内容のセルフレビュー、関連テストまたは未実行理由 |
| Medium | 新しい振る舞い、複数ファイル変更、IF 変更 | Low + Structure-Behavior Design Note、振る舞いテスト計画 |
| High | public API、DB schema、auth/authz、billing、migration、破壊的変更、新しい module boundary / cross-module architecture | Medium + ADR（`conventions/ai/adr-guidance.md`）または同等の設計判断記録、rollback / migration-safe plan、分割 PR 方針 |

内部の小規模 refactor や既存 boundary 内の整理は High risk ではなく、Medium + Design Note として扱ってよい。

## Gate 1: Pre-implementation

実装前に、作業対象が小さく安全に進められる状態かを確認する。

### Required artifacts

- Issue / Jira / ticket が 1 つに定まっている
- 受け入れ条件と非対象が読み取れる
- Risk lane が明示されている
- Medium 以上では Structure-Behavior Design Note がある
- High では ADR（`conventions/ai/adr-guidance.md`）または同等の設計判断記録がある

### Validation

- planner / spec writer role が ticket と受け入れ条件を確認する
- structure reviewer role が Medium / High の責務・境界・テスト観点を確認する
- 判断不能な High risk は、破壊的変更に進まず Draft PR / design note / migration-safe step に分割する

### Skip lane

- Docs-only light / typo / formatting のみの場合は Design Note を不要とする
- Policy docs は docs-only でも Low または Medium として扱う
- ただし PR body または review comment に risk lane 判断を残す

### Blocking policy

- Medium / High の必須 artifact がなく、safe fallback（Draft PR / Design Note / migration-safe step）にも分割できない場合は実装に進めない
- Ticket が曖昧な場合は、推測せず対象を 1 つに絞ってから進める

## Gate 2: Pre-review

レビューを始める前に、reviewer が同じ前提を見られる状態にする。

### Review context packet

レビュー前に共有する最小 context schema は `conventions/ai/review-context-schema.md` を参照する。reviewer は `required_context_checked` を返し、不足があれば `INSUFFICIENT_CONTEXT` として扱う。

### Required artifacts

- PR motivation と ticket link
- diff / changed files / PR scope
- 関連 docs / conventions / project instructions
- prior review comments がある場合はその一覧
- test / lint / typecheck / analyze の証跡、または未実行理由
- generated code がある場合は generator / schema / template の変更理由

### Validation

- review role は diff だけでなく、関連 docs / codebase / conventions / ticket / PR intent / prior reviews / test evidence を確認する
- reviewer が確認できない context は `INSUFFICIENT_CONTEXT` として明示する
- 外部 AI へ渡す場合は sanitized workspace context packet と policy gate を使う

### Skip lane

- Docs-only light では test evidence を `git diff --check`、関連 grep、Markdown / shell syntax check など軽量検証に置き換えてよい
- Policy docs では軽量検証に加えて、関連 workflow / hook / guideline との整合性を確認する
- local policy で特定 engine が無効な場合は `local_policy_disabled` を記録して代替する

### Blocking policy

- Required artifacts がなく reviewer が判断できない場合は `INSUFFICIENT_CONTEXT` として扱い、context を補うか scope を縮小する
- External AI policy が拒否した場合は policy を弱めず、local verification / CI / 代替 reviewer に切り替える

## Gate 3: Pre-ready

Draft PR を Ready にする前に、品質レビューと検証が完了しているかを確認する。

### Required artifacts

- Gate 2 の artifact
- Multi-AI review または代替 reviewer の統合結果
- MUST / CRITICAL 指摘の解消状況。integrator role が根拠付きで dismissed とした指摘は解消扱いにできる
- Medium / High では Structure-Behavior drift 確認結果
- UI / E2E 変更では Playwright 等の操作証跡、スクリーンショット、手動検証記録、または未実行理由

### Validation

- `gh pr ready` 前に verify stamp または検証コマンド結果を確認する
- reviewer は未解消の過去指摘を MUST として扱う
- UI 変更では user-visible behavior、locator、web-first assertion、trace / screenshot / video artifact の有無を確認する
- Playwright を使えない環境では、スクリーンショット、操作手順、期待結果、未実行理由を PR body または review comment に残す

### Skip lane

- Gate 3 は原則 skip しない。docs-only / low-risk でも、review evidence と検証結果または未実行理由を残す。
- 外部 reviewer が使えない場合は skip ではなく failure handling に従って代替 reviewer / local verification で補完する。

### Blocking policy

- Ready 前は CI / checks の fail / cancel / auth error を block する。pending は記録し、merge 前 gate で block する
- `no checks reported` だけを CI 未設定 / 未報告として扱う

## Gate 4: Pre-merge

merge 前に、変更が ticket scope を超えず、レビューと検証が収束していることを確認する。

### Required artifacts

- `claude/guidelines/git-workflow.md` の 1 PR = 1 ticket gate を満たす PR metadata
- Multi-AI review comment または代替レビュー記録
- 最新 head に対する verification evidence
- unresolved な MUST / CRITICAL 指摘が 0 件。integrator role が根拠付きで dismissed とした指摘は resolved として扱う
- 追加修正があった場合の re-review 記録。追加修正がない場合は N/A と明記する

### Validation

- integrator role がレビュー指摘と重大度語彙を MUST / SHOULD / NIT に triage し、採否理由を残す
- merge 前に `gh pr checks` を確認する
- generated code は原則レビュー対象外とし、generator / schema / template / build 設定を確認する

### Skip lane

- Gate 4 は merge gate のため skip しない。例外的な緊急対応でも、短い理由・残リスク・後続 Issue を残してから進める。

### Blocking policy

- 複数 ticket の混在、unresolved MUST、CI failure / cancel / pending / auth error、review evidence 欠落は merge 不可。具体的な ticket / commit / branch 運用は `claude/guidelines/git-workflow.md` を正本とする
- 緊急 hotfix でも bypass ではなく、短い理由・残リスク・後続 Issue を残す

## Disagreement handling

- integrator role が最終 triage を行い、採用 / 却下 / follow-up 化の理由を残す。
- 決定論的証跡（test / lint / CI / schema / explicit policy）を LLM reviewer の好みより優先する。
- 既存規約にない設計判断は、merge blocker にする前に ADR / Design Note / follow-up Issue として扱えるかを確認する。
- Security / data loss / authz / migration / public contract の破壊は、主観ではなくリリース阻害 risk として MUST にできる。

## Failure handling

| Failure | 扱い |
|---|---|
| `local_policy_disabled` | 失敗ではなく skip。代替 reviewer / local verification で補完する |
| `auth_prompt` / `quota_or_capacity` | ブラウザ認証で止めず、欠落理由を記録して fallback する |
| `policy_or_permission_denied` | policy を弱めず、packet を狭めるか local verification に切り替える |
| `timeout` / `empty_output` | 未検証として扱う。Gate 2 では `INSUFFICIENT_CONTEXT`、Gate 3 / Gate 4 では補完不可なら block とし、代替 reviewer / local verification / CI で補完できる場合だけ進行可 |
| LLM reviewer の主観的 disagreement | integrator role が MUST / SHOULD / NIT に triage する。決定論的証跡、既存規約、ticket 受け入れ条件を優先し、規約外の新しい設計判断は ADR / Design Note / follow-up Issue に逃がす |

## Current hook compatibility

現行 hook はこの文書より細かい marker / signature を要求する場合がある。hook 実装が更新されるまでは、`claude/guidelines/harness-hooks.md` にある既存 marker 形式を満たす。


## Related documents

- `conventions/ai/multi-ai-agent-operations.md`
- `conventions/ai/agent-hooks-observability.md`（failure taxonomy / recovery playbook）
- `claude/guidelines/review-workflow.md`
- `claude/guidelines/git-workflow.md`
- `conventions/ai/adr-guidance.md`
- `codex/skills/structure-behavior-design/SKILL.md`
