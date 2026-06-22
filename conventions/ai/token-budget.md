# AI agent token budget guidance

この文書は Claude / Codex / Antigravity の共通 token budget 方針をまとめる。品質 gate を下げずに、context size・tool output・subagent fan-out・background work を抑えることを目的にする。

## Structure-Behavior Design Note

### Requirement summary

- 目的: Claude だけでなく Codex / Antigravity の設定でも、長時間自律実行時の token 消費を抑える。
- 現状: Claude 側は auto-compact / Bash output / plugin 常時有効数を調整済み。Codex / Antigravity は workspace packet と tool output、subagent、memory/context discovery に節約余地がある。
- 期待する振る舞い: read-only research / scout は軽めの context と reasoning で回し、deep implementation / security review / merge gate だけ高コスト設定を使う。
- 非対象: credentials の追加、Antigravity 認証方式の強制変更、品質 gate の model downgrade。

### Responsibility assignment

| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| Codex config defaults | `codex/config.toml.template` | CLI の出力/agent/memory の既定値 | live `~/.codex/config.toml` はローカル編集 |
| Antigravity config defaults | `antigravity/settings.json` | sandbox / permission / verbosity の既定値 | repo 固有無視設定は各 repo |
| Multi-AI packet budget | `scripts/multi-ai-research.sh` | 同一 sanitized packet を小さく作る | 各 AI の内部 token accounting |
| Local override policy | `conventions/ai/local-agent-policy.md` / `scripts/lib/agent-policy.sh` | machine / repo ごとに engine・model・budget を上書き | policy で secret / main push gate は弱めない |

### Behavior tests

| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| Default packet budget | no local policy | dry-run multi-ai research | 25KB/file・600KB total・Codex medium が status に出る | script |
| Local override | budget env file | dry-run multi-ai research | override 値が status に出る | script |
| Config readability | temp HOME | install.sh / json.tool | Antigravity settings JSON が有効 | integration |

## Codex guidance

- `tool_output_token_limit=12000` で巨大 command output を context に載せすぎない。
- `model_reasoning_summary="none"` は reasoning summary の出力を抑える。最終回答や検証証跡は別途明示する。
- `agents.max_threads=4` / `agents.max_depth=1` で broad prompt の fan-out を抑える。Codex subagent は各 agent が独立して model/tool work を行い、単一 agent より token を消費する前提で扱う。
- read-only research は `MULTI_AI_CODEX_REASONING_EFFORT=medium` を既定にする。implementation / security review / merge gate は必要に応じて high/xhigh へ上げる。
- `web_search="cached"` を共有既定にし、最新性が必要な場合だけ live search を使う。

## MCP connector / large tool output guidance

`rtk` は shell stdout / stderr を削減できるが、Gmail / Traceary などの MCP connector が返す tool payload は別枠で context に入る。connector-heavy な調査では、品質 gate を下げずに **read scope・result count・body size・fan-out** を制御する。

### 共通手順

1. 初手は list / search / metadata だけにする。本文・添付・raw JSON の一括取得はしない。
2. `limit` / `max_results` / `pageSize` / `body_limit` / fields 指定を使い、まず 5〜20 件に絞る。
3. ID / 件名 / snippet / timestamp / sender / classification を表にして候補を選ぶ。
4. full body / raw payload は選んだ 1〜3 件だけ読む。必要なら `/private/tmp` に保存し、回答・PR コメントには要約と path だけを書く。
5. tool output が長くなる見込みなら、stdout や PR コメントに貼らず、`/private/tmp/<task>-raw.json` + `jq` / `python` の要約に分ける。
6. 追加 AI reviewer / subagent へは raw connector output ではなく、選別済み要約・ID・必要最小限の抜粋だけ渡す。

### Gmail triage

- いきなり thread / message body を bulk read しない。まず Gmail search で query を絞り、件数上限は `max_results` / `pageSize` 相当で 5〜10 件から始める。
- connector が metadata-only / minimal view（例: `view`, `messageFormat`）を持つ場合は、初手でそれを選ぶ。Codex Gmail connector のように search が message id 中心の場合は、ID を絞ってから必要な message だけ読む。
- 初回 payload は、利用中の connector が返せる `id`, `threadId`, `from`, `subject`, `date`, `snippet`, label 程度に抑える。
- 返信要否の判断は snippet で候補を分け、本文は返信候補・期限付き依頼・添付確認が必要な message だけ読む。
- 添付・raw MIME・HTML body は、ユーザーが転送/添付確認を求めた場合など、必要性が明確なときだけ取得する。
- inbox triage の結果は「urgent / needs reply / waiting / FYI」と根拠 message id を残し、本文全文は貼らない。

### Traceary triage

- `traceary sessions --snapshot --json` は session metadata と latest event を含み巨大化しやすい。初手は次のような narrow read にする。

```bash
rtk traceary list --fields ts,kind,session,client,agent,message --limit 20
rtk traceary list --kind command_executed --fields ts,session,client,agent,exit_code,message --limit 20
rtk traceary search "auth_prompt" --limit 10
```

- hook / plugin 状態は `doctor --json` 全量より、まず `hooks print --client <client>` と `doctor --client <client>` を client ごとに見る。
- MCP Traceary tool を使う場合は、`list_events` / `get_context` / `search` の `body_limit` を既定値（または小さめ）にし、`full_body=true` は最後の確認だけにする。
- Traceary 自身の診断では、現在の diagnostic session の transcript 全文を読ませると自己増幅する。session / workspace / time range を絞り、必要なら raw JSON を `/private/tmp/traceary-<task>.json` に保存して要約だけ context に載せる。
- hook 重複・version mismatch・capture gap を見つけたら、修正先を分ける。
  - Traceary 本体 / plugin / MCP read surface: `duck8823/traceary`
  - dotfiles の install / guidance / config / local policy: `duck8823/dotfiles`
  - 個別アプリ repo の hook 設定・CI・検証不足: そのアプリ repo

## Antigravity guidance

- `~/.gemini/antigravity-cli/settings.json` は `enableTerminalSandbox=true`, `toolPermission=request-review`, `verbosity=low` を共有既定にする。
- `multi-ai-research.sh` では sandbox-first の `agy --print --sandbox` を既定にし、空の per-run cwd から stdin prompt を渡す。repo 直接読みではなく sanitized workspace packet を使う。sandbox が host CLI の認証状態だけを隠して `auth_prompt` になった場合は、同一 engine / 同一 prompt / empty cwd / `NO_BROWSER=true` / no `--add-dir` / no `--sandbox` で 1 回だけ authenticated transport retry し、両 attempt を status に残す。
- `MULTI_AI_ANTIGRAVITY_PRINT_TIMEOUT` で Antigravity 側の print timeout を明示し、外側の script timeout と二重に失敗を記録する。
- credentials は dotfiles に入れず、必要なら個人設定で切り替える。

## Primary references

- Codex config basics: https://developers.openai.com/codex/config-basic
- Codex config reference: https://developers.openai.com/codex/config-reference
- Codex non-interactive mode: https://developers.openai.com/codex/noninteractive
- Codex subagents: https://developers.openai.com/codex/subagents
- Antigravity CLI migration: https://antigravity.google/docs/gcli-migration
- Antigravity plugins: https://antigravity.google/docs/plugins
- Antigravity skills: https://antigravity.google/docs/skills
