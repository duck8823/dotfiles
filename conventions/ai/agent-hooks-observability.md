# Agent hooks and observability

2026-05-24 時点の dotfiles / Traceary / Claude / Gemini / Codex hook 運用メモです。

## 方針

- hook は **決定論的 gate / audit / format / context injection** に限定する。
- 複雑な判断は hook から直接 LLM に丸投げせず、まず command hook + 共有スクリプトに寄せる。
- Claude の agent-based hooks は experimental のため、production gate は command hook を優先する。
- Claude Code の lifecycle event 名は公式 hooks reference を一次情報とし、`PostToolUseFailure` / `StopFailure` / `SubagentStop` / `SessionEnd` は 2026-05-24 時点の確認済み event として扱う。
- Gemini hooks は stdout に最終 JSON、ログは stderr に出す。
- 監査ログには prompt / command / transcript / session boundary を残す。ただし trace に sensitive data を含める設定は明示管理する。

## 現在の対応状況

| 対象 | dotfiles 管理 | Traceary / plugin 側 | 状態 |
|---|---|---|---|
| Claude Code lifecycle | `claude/settings.json.template` で cmux hook（SessionStart / UserPromptSubmit / Stop / StopFailure / PostToolUseFailure / SubagentStop / SessionEnd）、Bash guard、verify stamp、Edit/Write lint-format、Stop self-review | Traceary plugin は SessionStart / UserPromptSubmit / PreToolUse(Task/Agent) / PostToolUse / PostToolUseFailure / Stop / SubagentStop / PreCompact / PostCompact / SessionEnd 等を提供 | dotfiles template は Traceary hook を直接持たない。plugin / installed settings との merge 前提 |
| Gemini CLI hooks | `gemini/settings.json` で `hooksConfig.enabled=true` | Traceary extension は BeforeAgent / AfterAgent / AfterTool / PreCompress / SessionStart / SessionEnd を提供 | user/global extension 依存。project `.gemini/settings.json` は dotfiles 管理対象外 |
| Codex hooks | `codex/config.toml.template` と plugin 機能 | Traceary Codex plugin は SessionStart / UserPromptSubmit / PostToolUse / Stop transcript/session stop を提供 | plugin 管理。dotfiles に独自 hook script はない |
| Local safety hooks | `claude/hooks/*.sh` | n/a | GitHub / push-ready / worktree / verify stamp は Claude Code で対応済み |

## 2026-05-24 audit snapshot

`traceary doctor` は sandbox 内では SQLite DB を開けず fail するため、実状態確認は sandbox 外で実行した。

```text
traceary 0.18.0
claude: pass=15 warn=1 fail=0
gemini: pass=13 warn=2 fail=0
codex:  pass=13 warn=1 fail=0
```

warning の内訳:

- Claude: dotfiles workspace の Claude memory activation missing（accepted memories 0）
- Gemini: project `.gemini/settings.json` がない、Gemini memory activation missing（accepted memories 0）
- Codex: Codex memory activation stale（accepted memories 0）

判断:

- plugin version は Claude / Gemini / Codex すべて traceary 0.18.0 と一致。
- warning は hook 不通ではなく memory activation / project config の注意。accepted memory がない現状では即時修正不要。
- Gemini 実行時に壊れた `~/.gemini/extensions/nanobanana` が warning を出す。dotfiles 外のローカル extension として整理対象。

## 次に強化するなら

1. **Traceary hook 差分の定期点検**
   `scripts/audit-agent-observability.sh` で `traceary doctor` / `traceary hooks print` / installed settings JSON validation を束ね、必要に応じて dotfiles template / installed settings の差分を確認する。
2. **failure hook の監査**
   Claude の `PostToolUseFailure` / `StopFailure` / `SubagentStop` / `SessionEnd` は cmux へ転送する。Traceary plugin と重複するため、重い処理は入れず監査ログ用途に限定する。
3. **hook script の共有 lib 化**
   各 hook は薄い wrapper にし、コマンド解析・secret 判定・PR gate 判定は共通 script に寄せる。
4. **Gemini trust / headless preflight を明文化**
   未trusted directory では `--approval-mode plan` が override される。repo を渡さない一般調査だけ `--skip-trust` を許容し、repo 調査では trusted workspace / policy gate を必須にする。
5. **observability と secret 方針の分離**
   Traceary / OpenAI Agents SDK などの trace は便利だが、入力・出力・tool payload が sensitive data を含む可能性がある。trace include sensitive data は明示 opt-in にする。

## Claude / Gemini / Codex 調査失敗 playbook

`scripts/multi-ai-research.sh` は以下を標準分類する。

| classification | 主な原因 | 対応 |
|---|---|---|
| `trust_failed` | Gemini の untrusted workspace | workspace packet を生成後、実行は `/private/tmp` + `--skip-trust`。直接 repo を読ませる運用には戻さない |
| `auth_prompt` | headless 認証待ち | ブラウザを開かず失敗記録。local reviewer / Codex verifier へ fallback |
| `quota_or_capacity` | quota / capacity / 429 | 1回だけ retry。再失敗なら欠落理由を統合結果に記録 |
| `policy_or_permission_denied` | sandbox / approval reviewer / external AI policy deny | policy を弱めず、repo context を外すか redaction packet を狭める |
| `prompt_file_reference_expansion` | Gemini CLI が packet 内の `@...` を file reference と解釈 | Gemini 用 prompt では `@` を `\u0040` として transport-escape し、同一 packet hash を status に残す |
| `process_oom` | Gemini / Node が workspace scan や巨大 prompt で OOM | 空の per-run cwd で実行し、必要なら packet 上限を下げる |
| `timeout` | headless CLI が応答しない / timeout utility 不在 | Python fallback timeout で終了し、packet サイズを下げて再実行する |
| `command_failed` | CLI 非0終了 / wrapper エラー | stderr / exit code を残し、成功 engine の結果だけ採用する |
| `empty_output` | CLI crash / quota silent failure / stderr-only | stderr と exit code を確認し未検証扱い |

repo research ではローカル repo 内容を隠すのではなく、foreground orchestrator が sanitized workspace packet を作成してから Claude / Gemini / Codex に同一 packet を共有する。Gemini など file-reference expansion がある CLI は送信直前の transport escape で byte-level prompt が異なる場合があるが、source packet は同一 `packet_sha256` で監査する。これにより policy / trust 問題を抑えつつ、情報の偏りを避ける。repo と無関係な一般調査だけ `--mode general` を使う。

## 点検コマンド

```bash
rtk traceary --version
rtk proxy ~/.local/bin/audit-agent-observability.sh
rtk proxy /bin/zsh -lc 'for c in claude gemini codex; do traceary doctor --client "$c" --json; done'
rtk proxy /bin/zsh -lc 'for c in claude gemini codex; do traceary hooks print --client "$c"; done'
rtk proxy /bin/zsh -lc 'python3 -m json.tool ~/.claude/settings.json >/dev/null && python3 -m json.tool ~/.gemini/settings.json >/dev/null'
```

## 参考一次情報

- Claude Code hook lifecycle / matcher / hook types: <https://code.claude.com/docs/en/hooks>
- Gemini CLI hook stdout/stderr rule: <https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/writing-hooks.md>
- Gemini CLI configuration precedence: <https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/configuration.md>
- OpenAI Agents SDK tracing sensitive data: <https://openai.github.io/openai-agents-python/tracing/>
- OpenAI Agents SDK tool guardrails: <https://openai.github.io/openai-agents-js/guides/guardrails/>
- MCP security best practices: <https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices>
