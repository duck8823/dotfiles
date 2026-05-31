# AI agent token budget guidance

この文書は Claude / Codex / Gemini の共通 token budget 方針をまとめる。品質 gate を下げずに、context size・tool output・subagent fan-out・background work を抑えることを目的にする。

## Structure-Behavior Design Note

### Requirement summary

- 目的: Claude だけでなく Codex / Gemini の設定でも、長時間自律実行時の token 消費を抑える。
- 現状: Claude 側は auto-compact / Bash output / plugin 常時有効数を調整済み。Codex / Gemini は workspace packet と tool output、subagent、memory/context discovery に節約余地がある。
- 期待する振る舞い: read-only research / scout は軽めの context と reasoning で回し、deep implementation / security review / merge gate だけ高コスト設定を使う。
- 非対象: credentials の追加、Gemini 認証方式の強制変更、品質 gate の model downgrade。

### Conceptual model

| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Scope budget | packet file size / total size | 外部 AI に渡す workspace context を制限する | secrets と raw home dump は渡さない |
| Output budget | tool output token / chars | 長い tool output を truncation / file path 参照へ寄せる | 失敗原因と再現 path は残す |
| Agent fan-out budget | max threads / max depth | subagent 並列数と再帰を制限する | 必要な観点が明示されたときだけ増やす |
| Background budget | memory generation / session retention | heavy external-context session の background memory work を減らす | durable memory が必要な事実は明示的に残す |

### Responsibility assignment

| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| Codex config defaults | `codex/config.toml.template` | CLI の出力/agent/memory の既定値 | live `~/.codex/config.toml` はローカル編集 |
| Gemini config defaults | `gemini/settings.json` | tool output / directory tree / discovery の既定値 | repo 固有無視設定は各 repo `.geminiignore` |
| Multi-AI packet budget | `scripts/multi-ai-research.sh` | 同一 sanitized packet を小さく作る | 各 AI の内部 token accounting |
| Local override policy | `conventions/ai/local-agent-policy.md` / `scripts/lib/agent-policy.sh` | machine / repo ごとに engine・model・budget を上書き | policy で secret / main push gate は弱めない |

### Boundaries / interfaces

| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| `MULTI_AI_*` env vars | `multi-ai-research.sh` | policy file parsing / defaults | invalid numeric/effort は warning + safe default |
| Codex config | Codex CLI | model selection remains local | `codex doctor` で config loaded を確認 |
| Gemini config | Gemini CLI | OAuth/API key difference | JSON valid + CLI lightweight commandで読み込み確認 |

### Behavior tests

| Behavior | Given | When | Then | Level |
|---|---|---|---|
| Default packet budget | no local policy | dry-run multi-ai research | 25KB/file・600KB total・Codex medium が status に出る | script |
| Local override | budget env file | dry-run multi-ai research | override 値が status に出る | script |
| Config readability | temp CODEX_HOME | `codex doctor` | `config loaded` が出る | integration |
| Gemini settings readability | settings path override | `gemini --list-extensions` | exit 0 | integration |

## Codex guidance

- `tool_output_token_limit=12000` で巨大 command output を context に載せすぎない。
- `model_reasoning_summary="none"` は reasoning summary の出力を抑える。最終回答や検証証跡は別途明示する。
- `agents.max_threads=4` / `agents.max_depth=1` で broad prompt の fan-out を抑える。Codex 公式 docs では subagent は各 agent が独立して model/tool work を行い、単一 agent より token を消費すると説明されている。
- read-only research は `MULTI_AI_CODEX_REASONING_EFFORT=medium` を既定にする。implementation / security review / merge gate は必要に応じて high/xhigh へ上げる。
- `web_search="cached"` を共有既定にし、最新性が必要な場合だけ live search を使う。

## Gemini guidance

- `tools.truncateToolOutputThreshold=12000` と `ui.compactToolOutput=true` で長い tool output を抑える。
- `context.includeDirectoryTree=false` で初回 request に directory tree を入れず、`glob` / `grep_search` / `list_directory` で必要範囲だけ読む。
- `context.discoveryMaxDirs=80` は subdirectory `GEMINI.md` 探索を抑える共有既定。大規模 monorepo で local context が必要なら repo-local settings で増やす。
- `.geminiignore` で build / generated / vendor / logs を除外する。Gemini CLI docs によると `.geminiignore` は `read_many_files` など対応 tool の対象から除外する。
- Gemini CLI の token caching は API key / Vertex AI では有効だが、OAuth personal では cached content creation が使えない。credentials は dotfiles に入れず、必要なら個人設定で切り替える。

## Primary references

- Codex config basics: https://developers.openai.com/codex/config-basic
- Codex config reference: https://developers.openai.com/codex/config-reference
- Codex non-interactive mode: https://developers.openai.com/codex/noninteractive
- Codex subagents: https://developers.openai.com/codex/subagents
- Gemini CLI configuration: https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/configuration.md
- Gemini CLI token caching: https://google-gemini.github.io/gemini-cli/docs/cli/token-caching.html
- Gemini ignore: https://google-gemini.github.io/gemini-cli/docs/cli/gemini-ignore.html
