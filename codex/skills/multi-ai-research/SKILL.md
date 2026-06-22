---
name: multi-ai-research
description: Claude / Antigravity / Codex の調査協調を安全に回す。外部AIのpolicy拒否、Antigravity auth/quota失敗、空出力を分類し、同一 workspace context packet を共有して情報の偏りを避ける。
---

# Multi-AI Research

## 使う場面

- ユーザーが Claude / Antigravity / Codex にも調査させたいと言ったとき
- 以前の Claude / Antigravity / Codex 調査が policy / trust / auth / quota / empty output で失敗したとき
- repo 固有 context と一般 Web 調査を分離したいとき

## 原則

1. **workspace context packet を共有する**
   - repository 内の調査では、secret / private data を除外した workspace packet を生成し、Claude / Antigravity / Codex に同一 packet を渡す。
   - Antigravity / Antigravity legacy など `@...` を file reference と解釈する CLI では transport-escape により prompt bytes は異なる場合がある。監査は同一 `packet_sha256` と engine 別 prompt hash で行う。
   - general は repo と無関係な外部動向調査だけに使う。ユーザーが現在ターンで明示した場合に限り、current request、非機密 summary、public URL、出力 schema だけを渡す。
   - packet は workspace packet に含まれない repo 外 artifact / 追加資料を明示的に渡すときに使う。private/local artifact は事前に redaction し、policy gate を満たすことを確認する。
2. **失敗は成果物にする**
   - 失敗した AI、exit code、classification、stderr を status に残す。
   - 一部の engine だけ成功した場合も、成功分を採用し欠落理由を明記する。
   - Antigravity `--sandbox` が host CLI の認証状態だけを隠して `auth_prompt` になった場合は、同一 engine / 同一 prompt / empty cwd / `NO_BROWSER=true` / no `--add-dir` / no `--sandbox` で 1 回だけ `authenticated_transport_without_cli_sandbox` retry する。retry でも auth なら停止し、別 engine へ fallback しない。
3. **policy deny を突破しない**
   - sandbox / approval reviewer / policy が拒否したら、設定を弱めず送信境界を狭める。
   - user-explicit general Web 調査では local files / source / workspace packet / shell history / credentials / private data を送らない。repo/source context が必要になったら general を終了し、trusted repo + ticket/PR + sanitized packet の通常 gate に戻す。
   - local-only 調査、Traceary history、web 一次情報、Codex main の直接調査で補完する。

## 推奨コマンド

```bash
rtk proxy ./scripts/multi-ai-research.sh \
  --topic "<topic>" \
  --mode auto
```

install 済みなら:

```bash
rtk proxy ~/.local/bin/multi-ai-research.sh \
  --topic "<topic>" \
  --mode auto
```

`~/.config/ai-agent-policy.env` または環境変数で `MULTI_AI_ENGINES` / `MULTI_AI_DISABLED_ENGINES` を設定している場合はそれを優先する。無効化された engine は `local_policy_disabled` として status に残す。

ユーザーが現在ターンで明示した repo と無関係な public/general Web 調査だけを行う場合:

```bash
rtk proxy ~/.local/bin/multi-ai-research.sh \
  --topic "<topic>" \
  --mode general \
  --engines claude,antigravity,codex
```

repo 固有 context が必要な場合:

```bash
rtk proxy ~/.local/bin/multi-ai-research.sh \
  --prompt-file /tmp/research-prompt.md \
  --mode packet \
  --packet /tmp/sanitized-packet.md \
  --engines claude,antigravity,codex
```

## 統合時に確認する分類

- `ok`: 採用候補。一次情報・不確実性を確認する。
- `local_policy_disabled`: ローカルポリシーで engine が無効。失敗ではなく skip として記録し、残りの engine / local verification で補完する。
- `no_effective_engines`: local policy filtering 後に実行可能 engine が 0。dry-run 以外は非0で終了し、local verification / CI に切り替える。
- `tool_not_found`: CLI が未インストールまたは PATH にない。該当 engine を skip し、残りで補完する。
- `trust_failed`: CLI の workspace trust 問題。workspace packet 実行では空の per-run cwd / sandbox に戻し、直接 repo を読ませる運用には戻さない。
- `auth_prompt`: login / 認証失敗（ブラウザ認証プロンプト・対話ログイン）。Antigravity sandbox 起因の auth-only failure は同一 engine の authenticated transport retry を 1 回だけ許可する。retry 後も auth、または他 engine の auth prompt はここで停止し、ユーザーに認証修正を依頼する。別 engine への暗黙の代替・fallback はしない（設定不備を隠すため禁止）。
- `quota_or_capacity`: 1回だけ retry。再失敗なら欠落理由として記録。
- `policy_or_permission_denied`: 送信境界を狭める。policy を弱めない。
- `prompt_file_reference_expansion`: Antigravity / Antigravity legacy が packet 内の `@...` を file reference と誤解釈している。engine 用 prompt escaping を確認する。
- `process_oom`: 外部 CLI が workspace scan や巨大 prompt で OOM。空の per-run cwd で実行し、必要なら packet 上限を下げる。
- `timeout`: headless CLI が応答しない。Python fallback timeout が効いているか確認し、packet サイズを下げる。
- `command_failed`: CLI が非0終了。stderr / exit code を確認し、成功 engine だけ採用する。
- `empty_output`: stderr / quota / CLI crash を確認し、未検証扱いにする。

## 出力に必ず含めること

- Claude result / Antigravity result / Codex result の採否
- 失敗した系統の classification
- 採用した知見の一次情報 URL
- dotfiles に反映する変更候補（該当する場合）
- 残リスク
