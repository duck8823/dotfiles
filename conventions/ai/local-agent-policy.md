# Local agent policy

共有 dotfiles は **capability defaults** を配るだけで、各マシン・各リポジトリでどの AI を使うかはローカルポリシーが最終決定する。

## 方針

- Codex / Claude / Gemini は固定階層ではなく、現在の orchestrator と task scope に応じて協調する。
- 共有 dotfiles は安全側のデフォルトを置くが、Gemini を常に read-only に固定したり、特定 agent の使用を強制したりしない。
- ローカル環境で Gemini が不安定・禁止・quota 不足なら、Gemini を無効化して Codex / Claude / local verification にフォールバックする。
- `MULTI_AI_DISABLED_ENGINES=codex` は `multi-ai-research.sh` などの orchestrated engine selection では尊重するが、Claude hook では Codex 自体を全面ブロックしない。Codex は現在 orchestrator として使われることが多いが固定ではないため、write safety は agent 名ではなく branch / worktree gate で制御する。
- write を許可する agent は、必ず dedicated branch / worktree、明示スコープ、禁止操作、検証コマンドを持つ。
- policy によって agent を skip した場合は、失敗ではなく `skipped: local_policy_disabled` として記録する。

## 標準 override

`~/.config/ai-agent-policy.env` か環境変数で上書きする。shell として source せず、対応 script は許可された key だけを読み取る。**同じ key がある場合は環境変数が policy file より優先**する。
実装の正本は `scripts/lib/agent-policy.sh`（install 後は `~/.local/lib/dotfiles/agent-policy.sh`）に置く。

```bash
# multi-ai-research.sh で使う engine を限定
MULTI_AI_ENGINES=claude,codex

# 特定 engine を無効化。--engines で指定されても skip 記録にする
MULTI_AI_DISABLED_ENGINES=gemini

# Gemini の共有テンプレート既定。multi-ai-research は安全のため plan/read-only に強制する
MULTI_AI_GEMINI_APPROVAL_MODE=plan
MULTI_AI_GEMINI_SKIP_TRUST=true

# Gemini write を試す場合は dedicated branch/worktree で明示する
MULTI_AI_GEMINI_ALLOW_WRITE=false

# 必要なときだけ Gemini model を固定。未設定なら CLI の routing/modelSteering に委ねる
MULTI_AI_GEMINI_MODEL=

# Codex research/verifier の sandbox 既定
MULTI_AI_CODEX_SANDBOX=read-only
MULTI_AI_CODEX_REASONING_EFFORT=medium
MULTI_AI_CODEX_MODEL=
MULTI_AI_TOOL_OUTPUT_TOKEN_LIMIT=12000

# workspace packet の既定上限。大きい repo は --packet で明示 context を渡す
MULTI_AI_MAX_FILE_BYTES=25000
MULTI_AI_MAX_TOTAL_BYTES=600000

# Claude headless research の permission mode 既定
MULTI_AI_CLAUDE_PERMISSION_MODE=plan

# research script で plan/read-only 以外を許す非常用。通常は false
MULTI_AI_ALLOW_UNSAFE_RESEARCH_MODES=false
```

## 優先順位

1. 明示的なユーザー指示
2. リポジトリの `AGENTS.md` / `CLAUDE.md` / `GEMINI.md`
3. 実行時の環境変数
4. `~/.config/ai-agent-policy.env`
5. dotfiles の共有デフォルト

ただし、secret 除外、main 直 push 禁止、破壊的 remote 操作禁止、CI gate はローカルポリシーでも弱めない。

## Traceary context resume

手書き handoff を標準にしない。次の agent は Traceary / git / PR から復元する。

1. Traceary の `handoff` / recent context / durable memory pack を確認する。
2. `git status --short --branch`、branch、base diff、PR / Issue を確認する。
3. objective / scope / current branch / modified files / validation / blockers を再構成する。
4. 足りない情報だけを質問し、通常は Draft PR / design note / local verification へ進む。
5. 外部 AI へ渡す場合は sanitized workspace packet に蒸留し、raw transcript / secrets / repo 外 private file を渡さない。

## Agent 出力 schema

agent 間の共有 artifact は handoff ではなく resume packet として扱う。schema の正本は `conventions/ai/multi-ai-agent-operations.md` の **共通 resume schema** を参照する。
