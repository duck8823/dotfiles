# AI knowledge organization

この dotfiles では、AI 用の知識を目的別に分ける。

| 種別 | 置き場所 | 役割 | 例 |
|---|---|---|---|
| Rules | `codex/rules/`, `claude/rules/`, global instructions | 常時守る制約・禁止事項・安全ゲート | main 直 push 禁止、policy gate、出力形式 |
| Skills | `codex/skills/<name>/`, `claude/skills/<name>/` | 条件付きで呼び出す再利用 workflow | multi-ai-review、structure-behavior-design、issue-triage |
| Agents | `codex/agents/`, `claude/agents/`, `gemini/agents/` | 狭い責務を持つ worker / reviewer / scout | reviewer、architect、structure-reviewer |
| Prompts / Commands | `claude/commands/`、将来の `codex/prompts/` / `gemini/commands/` | ユーザーが明示起動する orchestration entrypoint | sprint、review-and-merge、implement-issue |
| Guidelines / Conventions | `claude/guidelines/`, `conventions/` | 長めの参照資料・プロジェクト横断規約 | git workflow、言語別 architecture |

## 共通 source of truth

- Multi-AI の role / schema / handoff 境界は `conventions/ai/multi-ai-agent-operations.md` を優先する。
- Agent の有効/無効、Gemini の approval mode / write 可否などのローカル差分は `conventions/ai/local-agent-policy.md` を優先する。
- Hook / observability / Traceary の点検基準は `conventions/ai/agent-hooks-observability.md` を優先する。
- `claude/`, `codex/`, `gemini/` 配下の agent / skill / settings は、上記 convention を各ツール形式へ投影したものとして扱う。

## 配置判断

- 常に有効でなければ危険な制約は **rule / global instruction** に置く。
- 毎回は不要だが、特定タスクで繰り返す手順は **skill** に置く。
- 独立した観点でレビュー・調査・検証させたいものは **agent** に置く。
- 複数 skill / agent を束ねてユーザー操作にしたいものは **command / prompt** に置く。
- 長く、必要時だけ参照すればよい背景知識は **guideline / convention** に置く。

## 自律・協調運用での原則

- Foreground orchestrator は最終判断を持ち、worker / scout の結果を統合する。
- Orchestrator は固定 AI 名ではなく role として扱う。現状は Codex が担うことが多いが、Claude / Gemini / Codex の能力・可用性・local policy に応じて切り替えられるよう、Traceary / git / PR / Issue から context を復元して継続する。
- Background worker は scoped task と検証証跡を返す。
- Scout は repo-wide consistency と diff 外影響を探す。read-only 固定ではなく、write 可否はローカルポリシーと worktree gate で決める。
- policy gate、secret 除外、generated code 除外、CI 判定ルールは skill ではなく常時ルール側にも置く。
- 1つの知識を複数ツールへ展開するときは、内容の source of truth と license / attribution を明記する。
