---
description: Claude / Gemini / Codex を安全な headless research partner として並列実行し、失敗理由も記録する
argument-hint: <research-topic>
allowed-tools: ["Bash", "Read"]
---

# Multi-AI Research

調査対象: **$ARGUMENTS**

## 目的

Claude / Gemini / Codex の headless 調査を「失敗して止まる」ではなく、preflight・安全境界・fallback・失敗理由記録つきで回す。

## 原則

- デフォルトは **auto mode**。git repository では sanitized workspace context packet を作り、Claude / Gemini / Codex に同一 packet を渡す。
- Gemini など `@...` を file reference と解釈する CLI では transport-escape により prompt bytes は異なる場合がある。監査は同一 `packet_sha256` と engine 別 prompt hash で行う。
- repo 固有 context は「共有しない」のではなく、secret / private data を除外した同一 packet として共有する。
- repo 外 artifact や追加資料が必要な場合は、人間または foreground orchestrator が先に redaction 済み packet を作り、`--mode packet --packet <file>` で渡す。
- secrets、`.env*`、shell history、repo 外 private file、個人/本番データ raw dump は送らない。
- Gemini の untrusted directory 問題は、workspace packet を作った後に `/private/tmp` + `--skip-trust` で実行して回避する。
- Claude が policy / approval reviewer に拒否された場合は、設定を弱めず status に記録する。

## 実行

```bash
~/.local/bin/multi-ai-research.sh --topic "$ARGUMENTS" --mode auto --engines claude,gemini,codex
```

`~/.local/bin/multi-ai-research.sh` がない場合は、dotfiles root から:

```bash
./scripts/multi-ai-research.sh --topic "$ARGUMENTS" --mode auto --engines claude,gemini,codex
```

出力された `summary.md` を読んで統合する。

## 追加 packet が必要な場合

1. policy gate を確認する。
2. workspace packet に含まれない repo 外 artifact / 追加資料だけ sanitized packet にする。
3. 以下で実行する。

```bash
~/.local/bin/multi-ai-research.sh \
  --prompt-file /tmp/research-prompt.md \
  --mode packet \
  --packet /tmp/sanitized-packet.md \
  --engines claude,gemini,codex
```

## 失敗時の扱い

- `trust_failed`: workspace packet 実行は `/private/tmp` + `--skip-trust` で再実行。直接 repo を読ませる運用には戻さない。
- `auth_prompt`: ブラウザを開かず失敗記録。別 reviewer / local verification に fallback。
- `quota_or_capacity`: 1回だけ時間を置いて再試行。再失敗なら欠落理由を記録。
- `policy_or_permission_denied`: policy を弱めず、送信境界を狭めるか local-only 調査に切り替える。
- `prompt_file_reference_expansion`: Gemini CLI が packet 内の `@...` を file reference と誤解釈している。Gemini 用 prompt escaping を確認する。
- `process_oom`: Gemini / Node が OOM。空の per-run cwd で実行し、必要なら packet 上限を下げる。
- `timeout`: headless CLI が応答しない。packet サイズを下げるか fallback reviewer を使う。
- `command_failed`: CLI が非0終了。stderr / exit code を記録し、成功 engine だけ採用する。
- `empty_output`: quota / auth / CLI crash を疑い、stderr と exit code を記録する。
