# Agent hooks and observability

2026-06-20 時点の dotfiles / Traceary / Claude / Antigravity / Codex hook 運用メモです。

## 方針

- hook は **決定論的 gate / audit / format / context injection** に限定する。
- 複雑な判断は hook から直接 LLM に丸投げせず、まず command hook + 共有スクリプトに寄せる。
- Claude の agent-based hooks は experimental のため、production gate は command hook を優先する。
- 監査ログには prompt / command / transcript / session boundary を残す。ただし trace に sensitive data を含める設定は明示管理する。
- agent の有効/無効や Antigravity の write 可否は hook に直書きせず、`conventions/ai/local-agent-policy.md` のローカルポリシーと deterministic gate に分ける。

## 現在の対応状況

| 対象 | dotfiles 管理 | Traceary / plugin 側 | 状態 |
|---|---|---|---|
| Claude Code lifecycle | `claude/settings.json.template` で cmux hook、Bash guard、verify stamp、Edit/Write lint-format、Stop self-review | Traceary Claude plugin | dotfiles template は Traceary hook を直接持たない。plugin / installed settings との merge 前提 |
| Antigravity CLI | `antigravity/settings.json` を `~/.gemini/antigravity-cli/settings.json` に同期 | Traceary v0.21 は `doctor --client antigravity` で capability を診断 | 2026-06-20 時点では公開 hook contract がなく、hooks print は意図的に呼ばない |
| Codex hooks | `codex/config.toml.template` と plugin 機能 | Traceary Codex plugin | plugin 管理。dotfiles に独自 hook script はない |
| Local safety hooks | `claude/hooks/*.sh` | n/a | GitHub / push-ready / worktree / verify stamp は Claude Code で対応済み |

## 点検コマンド

```bash
rtk traceary --version
rtk proxy ~/.local/bin/audit-agent-observability.sh
rtk proxy /bin/zsh -lc 'for c in claude gemini codex antigravity; do traceary doctor --client "$c" --json; done'
rtk proxy /bin/zsh -lc 'for c in claude gemini codex; do traceary hooks print --client "$c"; done'
rtk proxy /bin/zsh -lc 'python3 -m json.tool ~/.claude/settings.json >/dev/null && python3 -m json.tool ~/.gemini/antigravity-cli/settings.json >/dev/null'
```

## Claude / Antigravity / Codex 調査失敗 playbook

`scripts/multi-ai-research.sh` は以下を標準分類する。

| classification | 主な原因 | 対応 |
|---|---|---|
| `local_policy_disabled` | `~/.config/ai-agent-policy.env` / env で engine 無効化 | 起動せず skip として記録し、残りの engine / local verification / CI で補完する |
| `no_effective_engines` | local policy filtering 後に有効 engine が 0 | dry-run 以外は非0終了。local verification / CI へ切り替える |
| `tool_not_found` | CLI 未インストール / PATH 不備 | 該当 engine を skip し、残りの engine で補完する |
| `trust_failed` | CLI の workspace trust 問題 | 空の per-run cwd / sandbox に戻し、直接 repo を読ませる運用には戻さない |
| `auth_prompt` / login 失敗 | headless 認証待ち | ブラウザを開かず停止。fallback せずユーザーに認証修正を依頼 |
| `quota_or_capacity` | quota / capacity / 429 | 1回だけ retry。再失敗なら欠落理由を統合結果に記録 |
| `policy_or_permission_denied` | sandbox / approval reviewer / external AI policy deny | policy を弱めず、repo context を外すか redaction packet を狭める |
| `prompt_file_reference_expansion` | CLI が packet 内の `@...` を file reference と解釈 | Antigravity / legacy Gemini 用 prompt では `@` を `\u0040` として transport-escape し、同一 packet hash を status に残す |
| `process_oom` | workspace scan や巨大 prompt で OOM | 空の per-run cwd で実行し、必要なら packet 上限を下げる |
| `timeout` | headless CLI が応答しない / timeout utility 不在 | Python fallback timeout で終了し、packet サイズを下げて再実行する |
| `command_failed` | CLI 非0終了 / wrapper エラー | stderr / exit code を残し、成功 engine の結果だけ採用する |
| `empty_output` | CLI crash / quota silent failure / stderr-only | stderr と exit code を確認し未検証扱い |

repo research ではローカル repo 内容を隠すのではなく、current orchestrator が sanitized workspace packet を作成してから Claude / Antigravity / Codex に同一 packet を共有する。file-reference expansion がある CLI は送信直前の transport escape で byte-level prompt が異なる場合があるが、source packet は同一 `packet_sha256` で監査する。repo と無関係な一般調査だけ `--mode general` を使う。

## 参考一次情報

- Claude Code hook lifecycle / matcher / hook types: <https://code.claude.com/docs/en/hooks>
- Antigravity CLI migration: <https://antigravity.google/docs/gcli-migration>
- Antigravity plugins: <https://antigravity.google/docs/plugins>
- OpenAI Agents SDK tracing sensitive data: <https://openai.github.io/openai-agents-python/tracing/>
- OpenAI Agents SDK tool guardrails: <https://openai.github.io/openai-agents-js/guides/guardrails/>
- MCP security best practices: <https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices>
