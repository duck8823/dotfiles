# Local agent policy

共有 dotfiles は **capability defaults** を配るだけで、各マシン・各リポジトリでどの AI を使うかはローカルポリシーが最終決定する。

## 方針

- Codex / Claude / Gemini は固定階層ではなく、現在の orchestrator と task scope に応じて協調する。
- 共有 dotfiles は安全側のデフォルトを置くが、Gemini を常に read-only に固定したり、特定 agent の使用を強制したりしない。
- ローカル環境で Gemini が不安定・禁止・quota 不足なら、Gemini を無効化して Codex / Claude / local verification にフォールバックする。
- write を許可する agent は、必ず dedicated branch / worktree、明示スコープ、禁止操作、検証コマンドを持つ。
- policy によって agent を skip した場合は、失敗ではなく `skipped: local_policy_disabled` として記録する。

## 標準 override

`~/.config/ai-agent-policy.env` か環境変数で上書きする。shell として source せず、対応 script は許可された key だけを読み取る。

```bash
# multi-ai-research.sh で使う engine を限定
MULTI_AI_ENGINES=claude,codex

# 特定 engine を無効化。--engines で指定されても skip 記録にする
MULTI_AI_DISABLED_ENGINES=gemini

# Gemini の共有テンプレート既定。write 許可はリポジトリ側の別 policy と worktree gate が必要
MULTI_AI_GEMINI_APPROVAL_MODE=plan
MULTI_AI_GEMINI_SKIP_TRUST=true

# Codex research/verifier の sandbox 既定
MULTI_AI_CODEX_SANDBOX=read-only

# Claude headless research の permission mode 既定
MULTI_AI_CLAUDE_PERMISSION_MODE=plan
```

## 優先順位

1. 明示的なユーザー指示
2. リポジトリの `AGENTS.md` / `CLAUDE.md` / `GEMINI.md`
3. `~/.config/ai-agent-policy.env` / 環境変数
4. dotfiles の共有デフォルト

ただし、secret 除外、main 直 push 禁止、破壊的 remote 操作禁止、CI gate はローカルポリシーでも弱めない。

## Traceary context resume

手書き handoff を標準にしない。次の agent は Traceary / git / PR から復元する。

1. Traceary の `handoff` / recent context / durable memory pack を確認する。
2. `git status --short --branch`、branch、base diff、PR / Issue を確認する。
3. objective / scope / current branch / modified files / validation / blockers を再構成する。
4. 足りない情報だけを質問し、通常は Draft PR / design note / local verification へ進む。
5. 外部 AI へ渡す場合は sanitized workspace packet に蒸留し、raw transcript / secrets / repo 外 private file を渡さない。

## Agent 出力 schema

agent 間の共有 artifact は handoff ではなく resume packet として扱う。

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
  "results": {"passed": [], "failed": []},
  "residual_risks": [],
  "next_actions": []
}
```
