---
name: multi-ai-research
description: Claude / Gemini / Codex の調査協調を安全に回す。外部AIのpolicy拒否、Gemini trust/auth/quota失敗、空出力を分類し、同一 workspace context packet を共有して情報の偏りを避ける。
---

# Multi-AI Research

## 使う場面

- ユーザーが Claude / Gemini / Codex にも調査させたいと言ったとき
- 以前の Claude / Gemini / Codex 調査が policy / trust / auth / quota / empty output で失敗したとき
- repo 固有 context と一般 Web 調査を分離したいとき

## 原則

1. **workspace context packet を共有する**
   - repository 内の調査では、secret / private data を除外した workspace packet を生成し、Claude / Gemini / Codex に同一 packet を渡す。
   - Gemini など `@...` を file reference と解釈する CLI では transport-escape により prompt bytes は異なる場合がある。監査は同一 `packet_sha256` と engine 別 prompt hash で行う。
   - general は repo と無関係な外部動向調査だけに使う。
   - packet は workspace packet に含まれない repo 外 artifact / 追加資料を明示的に渡すときに使う。
2. **失敗は成果物にする**
   - 失敗した AI、exit code、classification、stderr を status に残す。
   - 一部の engine だけ成功した場合も、成功分を採用し欠落理由を明記する。
3. **policy deny を突破しない**
   - sandbox / approval reviewer / policy が拒否したら、設定を弱めず送信境界を狭める。
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

repo 固有 context が必要な場合:

```bash
rtk proxy ~/.local/bin/multi-ai-research.sh \
  --prompt-file /tmp/research-prompt.md \
  --mode packet \
  --packet /tmp/sanitized-packet.md \
  --engines claude,gemini,codex
```

## 統合時に確認する分類

- `ok`: 採用候補。一次情報・不確実性を確認する。
- `local_policy_disabled`: ローカルポリシーで engine が無効。失敗ではなく skip として記録し、残りの engine / local verification で補完する。
- `trust_failed`: Gemini workspace trust 問題。workspace packet 実行では `/private/tmp` + `--skip-trust` で再実行し、直接 repo を読ませる運用には戻さない。
- `auth_prompt`: headless 失敗。ブラウザを開かず fallback。
- `quota_or_capacity`: 1回だけ retry。再失敗なら欠落理由として記録。
- `policy_or_permission_denied`: 送信境界を狭める。policy を弱めない。
- `prompt_file_reference_expansion`: Gemini CLI が packet 内の `@...` を file reference と解釈した。Gemini 用 prompt escaping を確認する。
- `process_oom`: Gemini / Node が workspace scan や巨大 prompt で OOM。空の per-run cwd で実行し、必要なら packet 上限を下げる。
- `timeout`: headless CLI が応答しない。Python fallback timeout が効いているか確認し、packet サイズを下げる。
- `command_failed`: CLI が非0終了。stderr / exit code を確認し、成功 engine だけ採用する。
- `empty_output`: stderr / quota / CLI crash を確認し、未検証扱いにする。

## 出力に必ず含めること

- Claude result / Gemini result / Codex result の採否
- 失敗した系統の classification
- 採用した知見の一次情報 URL
- dotfiles に反映する変更候補
- 残リスク
