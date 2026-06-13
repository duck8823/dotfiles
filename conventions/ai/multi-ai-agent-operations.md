# Multi-AI agent operations

この文書は、Claude / Codex / Gemini の skill・agent・subagent 定義を共通化するときの source of truth です。
各ツール固有の `CLAUDE.md`、`codex/agents/*.toml`、`gemini/agents/*.md`、`SKILL.md` は、この役割表を投影したものとして扱います。

## 基本方針

- Orchestrator は固定された AI 名ではなく、現在の main session / task / local policy / 可用性 / 能力で選ぶ **role** とする。
- 現在の実運用では Codex が primary orchestrator になることが多いが、それは現状の適性であって恒久的な希望状態ではない。Claude / Gemini / Codex は同じ role / responsibility / resume schema で協調・代替できるようにする。
- Gemini を dotfiles で恒久的に read-only 固定しない。共有テンプレートは安全側の plan/scout を既定にするが、write 可否・無効化・approval mode はローカルポリシーを優先する。
- 手書き handoff を標準にせず、Traceary / git / PR / Issue / workspace packet から context を復元する。
- 実装は **実装したエージェント / セッションがコミットする**。orchestrator は採否判断・gate・統合を担うが、他セッションの実装を代理コミットしない（authorship を実装に一致させる）。同一エージェントが worker と orchestrator を兼ねる solo セッション、および成果物を返すだけの in-session ephemeral subagent はこの限りでない。

## 共通ロール

| ロール | 代表担当 | 権限 | 成果物 |
|---|---|---|---|
| Primary orchestrator | 現在の main session（現状は Codex が多いが固定しない） | 全体進行、採否判断、PR ゲート、レビュー反映 | 方針、採否理由、統合コメント、次アクション |
| Foreground specialist / integrator | Claude / Codex | UX・仕様・大きめの統合判断 | 設計判断、ユーザー影響整理、統合レビュー |
| Scoped implementation worker | Codex / local policy で許可された agent | dedicated branch / worktree の write・**自分の変更のコミット** | 変更ファイル、実行コマンド、結果、残リスク、自分が打ったコミット |
| Scout / critic | Gemini / Claude / Codex | 既定は read-heavy。write は local policy 次第 | 既存パターン逸脱、命名 drift、diff 外影響 |
| Security / verification reviewer | Codex / verifier agent | test / lint / 静的解析、セキュリティ観点 | `validated_commands` 付き findings |
| Call-chain reviewer | Claude subagent / Codex reviewer | Read / Grep / 必要最小の test | 呼び出し元からのバグ・エラー処理・テスト漏れ |
| Structure reviewer | Claude / Codex / Gemini | read-heavy、必要なら設計メモ | 責務配置、境界/IF、振る舞いテスト不足 |
| Planner / spec writer | Codex / Gemini / Claude | issue・コード調査 | wave、依存、担当、検証計画 |

## 共通 resume schema

agent 間の共有 artifact は「handoff」ではなく、再開可能な context resume packet として扱います。

```json
{
  "objective": "",
  "current_state": "",
  "scope": [],
  "allowed_write_scope": [],
  "forbidden_actions": [],
  "required_validation": [],
  "context_refs": [
    {"kind": "traceary_session|event|pr|issue|file", "value": ""}
  ],
  "output_format": {
    "changed_files": [],
    "validated_commands": [],
    "results": {"passed": [], "failed": []},
    "residual_risks": [],
    "findings": [],
    "next_actions": []
  }
}
```

- read-only / scout 実行では `allowed_write_scope` を空にし、書き込み禁止を明示する。
- write worker では ticket / branch / worktree / 変更可能ファイルを明示する。
- reviewer では author と利益相反を明示する。author と同じ engine は独立最終レビュー扱いにしない。
- `validated_commands` が空の verifier 出力は「未検証」として扱う。

## Quality gate policy

品質 gate の正本は `conventions/ai/quality-gates.md` とする。レビュー前に共有する最小 context packet は `conventions/ai/review-context-schema.md` に従う。各 agent は role / capability ベースで gate を満たす artifact を確認し、local policy で engine が無効な場合は欠落理由を記録して代替 reviewer / local verification / CI で補完する。

## Git / PR guard policy

- **1 PR = 1 ticket** を hard gate とする。GitHub Issue なら `Closes #123`、Jira 等なら `[PROJ-123]` のような ticket ID を PR title/body に1つだけ含める。
- これは write / 実装委譲に対する hard gate であり、`~/.codex/config.toml` の `[auto_review].policy` が定める例外（ticket-less prefix `[MAINTENANCE]` / `[FIX]` / `[PROPOSAL]`、read-only mutual invocation / consultation、structured-output regeneration / AI-reviewed artifact update）では ticket 参照を省略できる。これらの例外でも write 系の実装委譲・main/master 直 push・merge・deploy・infra apply は緩めない。
- 1 ticket の中では multiple commits を許可する。ただし各 commit は「何を・なぜ変えたか」を表す1関心事に分割する。
- レビュー指摘で発生した変更も「レビュー対応」「address review feedback」などの commit message にしない。既存 commit に fixup / amend するか、変更内容を表す semantic message にする。
- 1 PR に複数 ticket が混ざった場合は、既存 PR を閉じるのではなく対象 ticket に scope を戻し、残りの差分は別 branch / 別 PR へ分割する。
- hook は決定論的に判定できるもの（ticket count、draft、review 起点 commit message、過大 staged 変更の警告）だけを扱う。関心事分割の最終判断は diff 実読と reviewer に委ねる。

## 共通化の方針

1. **抽象は role / responsibility / schema に置く**
   モデル名、CLI フラグ、ツール名は各ツール固有ファイルに置く。
2. **skill は workflow、agent は観点、hook は決定論的 gate**
   skill に恒久制約を埋め込まない。恒久制約は global instruction / rule / policy に置く。
3. **ローカルポリシーを優先する**
   `conventions/ai/local-agent-policy.md` を参照し、Gemini 無効化・approval mode・write 可否などをローカルで上書きできるようにする。
4. **local subagent を優先し、remote agent は明確な境界がある場合だけ使う**
   同一ワークスペース内の並列調査は local subagent / worktree で十分。別サービス・別チーム・別 framework と連携する場合だけ A2A を検討する。
5. **context resume では履歴を蒸留する**
   外部 AI へは PR diff、関連 Issue、必要ソース、テスト出力、Traceary から蒸留した decision / blocker だけを渡す。shell history、`.env*`、認証情報、無関係な repo 外ファイル、raw transcript は渡さない。
6. **パーソナライズ情報はそのまま運用ルールにしない**
   Gemini / Google Lens / 個人記憶から得た示唆は、出典・再現性・適用条件を確認してから dotfiles に蒸留する。スクリーンショットや個人データの raw dump は PR review / external AI prompt に含めない。

## 2026-05 時点の採用知見

- Claude / Gemini とも subagent は「専門ロール + 独立 context + tool 制限」で安定する。万能 agent を増やすより、role / schema を共通化し、各 CLI の agent 定義へ薄く投影する。
- 引き継ぎは会話履歴を丸ごと渡すのではなく、Traceary / git / PR / Issue から objective / scope / forbidden_actions / required_validation / output_format を復元した resume packet に落とす。
- Guardrail / hook は LLM 判断ではなく、決定論的な policy gate・secret 除外・CI 判定・failure classification に寄せる。
- Tracing / memory / session audit は便利だが、prompt / tool payload / function output が sensitive data を含む可能性があるため、include sensitive data は明示 opt-in とする。
- MCP / external connector は per-client consent・scope 表示・redirect/token 検証を前提にし、token passthrough や broad external upload を禁止する。
- Claude Code Opus 4.8（2026-05）で effort（既定 high）/ ultracode / Dynamic Workflows（Claude が JS orchestration script を書き、隔離 runtime が subagent 群を実行。同時最大 16・1 run 総計 1,000 agent 上限・同一セッション内のみ resumable）が使えるようになり、Claude もローカルで大規模オーケストレーションを自走できる。orchestrator は引き続き role で選ぶ（現状 primary は Codex / GPT-5.5）。ローカルの codify / 検証収束型は Claude ultracode、cloud 並列・長時間 long-horizon 自律は Codex に寄せる。
- 新モデル発表時は委任先モデルだけ更新し、役割の枠組みは維持する。ベンチ（SWE-bench Pro 等）は評価条件差・汚染・loophole で単純序列化できないため（例: SWE-bench Pro は Claude 系の `.git` loophole 悪用が報告され、DeepSWE では GPT-5.5 が Opus を逆転）、スコア差だけで orchestrator / verifier を入れ替えない。

## Claude / Gemini / Codex research 協調

Claude / Gemini / Codex の協調調査は `scripts/multi-ai-research.sh` を使う。install 後は `~/.local/bin/multi-ai-research.sh` から呼び出せる。
git repository 内では、secret / private data を除外した同一 workspace context packet を Claude / Gemini / Codex に共有する。
Gemini など prompt 内 `@...` を file reference と解釈する CLI では、送信直前に `@` を `\u0040` として transport-escape する場合がある。この場合も source packet は同一で、監査は `packet_sha256` と engine 別 prompt hash の両方で行う。

```bash
rtk proxy ./scripts/multi-ai-research.sh \
  --topic "調査したいテーマ" \
  --mode auto
```

- `auto`: git repository では `workspace`、それ以外では `general` として動く。
- `workspace`: git status / diff / source files から sanitized packet を生成し、同じ packet hash を各 engine に渡す。engine 別 transport escape がある場合は prompt hash も併記する。
- `general`: repo と無関係な外部動向調査だけに使う。ユーザーが現在ターンで明示した場合に限り、current request、非機密 summary、public URL、出力 schema だけを渡す。local files / source / workspace packet / shell history / credentials / private data は送らない。
- `packet`: workspace packet に含まれない repo 外 artifact / 追加資料を渡すときに使う。private/local artifact は先に redaction し、policy gate を満たすことを確認する。
- `~/.config/ai-agent-policy.env` または `MULTI_AI_DISABLED_ENGINES` で無効化された engine は起動せず、`local_policy_disabled` として status に記録する。

## Traceary context resume

次の agent が作業を引き継ぐときは、まず Traceary と repo state から復元する。

1. Traceary `handoff` / recent context / memory pack を確認する。
2. `git status --short --branch`、branch、base diff、open PR / Issue を確認する。
3. objective / current_state / blockers / validation state を resume packet にまとめる。
4. 足りない情報だけ質問し、安全に進められる作業は止めない。
5. 外部 AI へ渡す場合は sanitized workspace packet に蒸留する。
