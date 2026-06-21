---
name: multi-ai-review
description: policy-controlled scout・Codex verifier・Claude/Codex integrator を組み合わせてPRを多重レビューする
---

# Multi-AI レビュー

## トリガー
ドラフト PR 作成後に自動呼び出し。または手動で `/multi-ai-review`

## 基本方針

共通 role / schema / failure taxonomy は `conventions/ai/multi-ai-agent-operations.md` と
`conventions/ai/agent-hooks-observability.md` を source of truth とし、この skill は
Claude 側の PR review orchestration だけを定義する。

- **Antigravity** は共有デフォルトでは scout / critic。read-only 固定ではなく local policy 優先
- **Codex** は security / test verifier
- **Claude** は統合判断とマージゲート
- authored-by に応じて利益相反を避ける
- ローカル CLI / subagent の失敗はプロセス停止理由を記録する。transient 失敗（quota / capacity / timeout）では全体を止めず代替 reviewer / local verification / CI で継続するが、login / 認証失敗（auth_prompt / ブラウザ認証プロンプト / 対話ログイン）では暗黙の代替をせず停止し、ユーザーに認証修正を促す。Antigravity `--sandbox` が host CLI の認証状態だけを隠した場合は、同一 engine / 同一 prompt / empty cwd / `NO_BROWSER=true` / no `--add-dir` / no `--sandbox` の authenticated transport retry を 1 回だけ許可し、retry でも auth なら停止する
- Medium / High risk の変更では `structure-reviewer` 観点（手続き化・責務配置・境界/IF・振る舞いテスト）を統合レビューに含める
- Claude / Antigravity / Codex の調査失敗は `multi-ai-research` command / `scripts/multi-ai-research.sh` の分類（`trust_failed` / `auth_prompt` / `quota_or_capacity` / `policy_or_permission_denied` / `prompt_file_reference_expansion` / `process_oom` / `timeout` / `command_failed` / `empty_output`）で記録する

## External AI delegation policy gate

Antigravity / Codex / Claude CLI へ PR diff・local branch diff・関連ソースを渡す前に、`~/.codex/config.toml` の `[auto_review].policy` にある **External AI delegation exception** を満たすことを確認する。

- 作業ディレクトリは trusted repository またはその git worktree に限定する
- 1 ticket / 1 PR にスコープを限定し、複数チケットを1つの review request に束ねない
- `.env`、credentials、tokens、private keys、secret files、shell history、無関係な repo / home directory dump を送らない
- Antigravity は共有デフォルトでは sandbox-first の `agy --print --sandbox ${ANTIGRAVITY_REVIEW_MODEL:+--model $ANTIGRAVITY_REVIEW_MODEL}` で使う。sandbox が host CLI の認証状態だけを隠して `auth_prompt` になった場合は、同じ prompt を empty cwd / `NO_BROWSER=true` / no `--add-dir` / no `--sandbox` で 1 回だけ retry し、両 attempt を記録する。無効化・sandbox・auth retry・write 可否は local policy を優先する
- Codex verifier は `codex exec --full-auto -c 'agents.default.config_file="$HOME/.codex/agents/reviewer.toml"'` を優先する
- policy / Guardian / sandbox の拒否が出た場合は設定を弱めず、`skipped: policy_denied` または具体的な拒否理由を記録して Claude-only fallback に進む

この gate は multi-AI review を止めるためではなく、許可条件を満たすケースで安全に回すための前処理である。

## 外部AIへのデータ送信境界

`multi-ai-review` が明示され、かつ上記 policy gate を満たす場合、PR diff・関連 Issue・レビューコメント・該当ソース・テストログ・repo 内 artifact を configured external AI CLI（Antigravity / Codex / Claude Code / ai-review）に渡すことは承認済みとして扱う。毎回追加確認しない。

追加確認または policy deny が必要なもの:

- secrets / token / API key / 認証情報 / `.env*`
- repo 外 private file（`~/Downloads` の design zip 等を含む。ユーザーが当該 path を明示した場合だけ可）
- 本番データ・個人データの raw dump
- 外部サービスへの書き込み

Sandbox / reviewer が external AI 送信を拒否した場合、設定を弱めず、拒否理由を PR コメントまたは `.ai-logs/` に記録してフォールバックする。代替禁止または Claude Code 委譲が必須指定の場合は停止する。

## 手順

### 1. 差分とコンテキスト収集
```bash
PR_NUMBER=<number>
PROJECT=$(basename "$(pwd)")
DIFF_FILE=/tmp/${PROJECT}-pr${PR_NUMBER}-diff.txt
POLICY_DENIED_FILE=/tmp/${PROJECT}-pr${PR_NUMBER}-policy-denied.md
: > "$POLICY_DENIED_FILE"

SENSITIVE_PATH_RE='(^|/)(\.env(\..*)?|\.aws/|\.ssh/|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?|.*\.(pem|key|p12|pfx)|.*secret.*|.*credential.*|.*token.*|.*history)$'
if git diff --name-only origin/main...HEAD | grep -Eiq "$SENSITIVE_PATH_RE"; then
  echo "sensitive path changed; external AI review skipped by policy" > "$POLICY_DENIED_FILE"
elif git diff origin/main...HEAD --unified=0 | grep -Eq '^\+.*(BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,})'; then
  echo "secret-looking added content; external AI review skipped by policy" > "$POLICY_DENIED_FILE"
fi

if [ -s "$POLICY_DENIED_FILE" ]; then
  : > "$DIFF_FILE"
else
  git diff origin/main...HEAD > "$DIFF_FILE"
fi
gh pr view "$PR_NUMBER"
CHECKS_JSON=/tmp/${PROJECT}-pr${PR_NUMBER}-checks.json
CHECKS_ERR=/tmp/${PROJECT}-pr${PR_NUMBER}-checks.err
set +e
gh pr checks "$PR_NUMBER" --json name,bucket,state,workflow,link >"$CHECKS_JSON" 2>"$CHECKS_ERR"
CHECKS_EXIT=$?
set -e
if [ -s "$CHECKS_JSON" ] && jq -e 'length > 0' "$CHECKS_JSON" >/dev/null 2>&1; then
  if jq -e 'any(.[]; .bucket == "fail" or .bucket == "cancel" or .bucket == "pending")' "$CHECKS_JSON" >/dev/null; then
    echo "checks are failing, cancelled, or pending"
    cat "$CHECKS_JSON"
  fi
elif grep -qi 'no checks reported' "$CHECKS_ERR"; then
  echo "no checks reported"
else
  echo "gh pr checks failed with exit ${CHECKS_EXIT}" >&2
  cat "$CHECKS_ERR" >&2
  exit 1
fi
```

`no checks reported` だけを CI 未設定 / 未報告として扱う。`fail` / `cancel` / `pending` / 認証・通信エラーは分離して統合コメントに明記し、マージ不可として扱う。

### 2. Policy-controlled scout
```bash
cat > /tmp/antigravity-review.md <<PROMPT
以下の PR を local policy に従う scout / critic としてレビューしてください。共有デフォルトでは書き込み不要です。

- 既存パターンとの整合性
- diff 外影響
- docs / config / l10n 更新漏れ
- 命名 drift
- Structure-Behavior drift（肥大 usecase / handler、責務漏れ、data-only model、primitive obsession、IF劣化、振る舞いテスト不足）
- generated なコードと判断できるものは原則スキップし、generator / schema / template 側を見る
- canonical review schema の `verdict` を使い、`decision` など別名の判定フィールドを追加しない
- JSON で返す。最低限 `source`, `verdict`, `required_context_checked`, `missing_context`, `findings`, `validated_commands`, `results`, `residual_risks`, `impacted_files`, `summary` を含める
- `verdict` は APPROVE / REQUEST_CHANGES / INSUFFICIENT_CONTEXT

## Diff
$(cat "$DIFF_FILE")
PROMPT

ANTIGRAVITY_PREFLIGHT_OUT=/tmp/antigravity-review-preflight.md
export ANTIGRAVITY_PREFLIGHT_OUT
if [ -s "$POLICY_DENIED_FILE" ]; then
  echo "skipped: policy_denied: $(cat "$POLICY_DENIED_FILE")" > /tmp/antigravity-review-result.json
else
python3 - <<'PY'
import os, subprocess, sys
prompt = "read-only preflight。1行だけ返してください。"
env = os.environ.copy()
# Antigravity loads installed skills from ~/.gemini/antigravity-cli/skills; no Gemini-era system prompt env is set.
env["TERM"] = "xterm-256color"
env["NO_BROWSER"] = "true"
env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + env.get("PATH", "")
out_path = os.environ["ANTIGRAVITY_PREFLIGHT_OUT"]
try:
    cmd = ["agy", "--print", "--sandbox"]
    if os.environ.get("ANTIGRAVITY_REVIEW_MODEL"):
        cmd += ["-m", os.environ["ANTIGRAVITY_REVIEW_MODEL"]]
    proc = subprocess.run(
        cmd,
        input=prompt,
        text=True,
        capture_output=True,
        timeout=20,
        env=env,
    )
    text = (proc.stdout or "") + (proc.stderr or "")
except subprocess.TimeoutExpired as exc:
    text = ((exc.stdout or "") if isinstance(exc.stdout, str) else "") + ((exc.stderr or "") if isinstance(exc.stderr, str) else "") + "\nTIMEOUT_AFTER=20\n"
    open(os.environ["ANTIGRAVITY_PREFLIGHT_OUT"], "w").write(text)
    sys.exit(124)
open(os.environ["ANTIGRAVITY_PREFLIGHT_OUT"], "w").write(text)
if any(marker.lower() in text.lower() for marker in ["Opening authentication page", "Do you want to continue?", "authentication page", "not authenticated", "please log in", "login required", "not_logged_in", "login_required", "not signed in", "sign in to continue"]):
    sys.exit(42)
if not text.strip() or proc.returncode != 0:
    sys.exit(proc.returncode or 1)
PY

if [ $? -eq 0 ]; then
  python3 - <<'PY'
import os, subprocess, sys
prompt = open("/tmp/antigravity-review.md").read()
env = os.environ.copy()
# Antigravity loads installed skills from ~/.gemini/antigravity-cli/skills; no Gemini-era system prompt env is set.
env["TERM"] = "xterm-256color"
env["NO_BROWSER"] = "true"
env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + env.get("PATH", "")
try:
    cmd = ["agy", "--print", "--sandbox"]
    if os.environ.get("ANTIGRAVITY_REVIEW_MODEL"):
        cmd += ["-m", os.environ["ANTIGRAVITY_REVIEW_MODEL"]]
    proc = subprocess.run(
        cmd,
        input=prompt,
        text=True,
        capture_output=True,
        timeout=600,
        env=env,
    )
    text = (proc.stdout or "") + (proc.stderr or "") + f"\nEXIT_CODE={proc.returncode}\n"
except subprocess.TimeoutExpired as exc:
    text = ((exc.stdout or "") if isinstance(exc.stdout, str) else "") + ((exc.stderr or "") if isinstance(exc.stderr, str) else "") + "\nTIMEOUT_AFTER=600\nKILLED=true\n"
    open("/tmp/antigravity-review-result.json", "w").write(text)
    sys.exit(124)
open("/tmp/antigravity-review-result.json", "w").write(text)
if any(marker.lower() in text.lower() for marker in ["Opening authentication page", "Do you want to continue?", "authentication page", "not authenticated", "please log in", "login required", "not_logged_in", "login_required", "not signed in", "sign in to continue"]):
    sys.exit(42)
if not text.strip() or proc.returncode != 0:
    sys.exit(proc.returncode or 1)
PY
else
  echo "Antigravity preflight failed; fallback required. See $ANTIGRAVITY_PREFLIGHT_OUT" > /tmp/antigravity-review-result.json
fi
fi
```

`POLICY_DENIED_FILE` が空でない場合は Antigravity / Codex CLI へ diff を渡さず、`skipped: policy_denied` と理由を統合コメントに記録して Claude-only fallback + local verification + CI で補完する。preflight または本実行が timeout / 空出力 / 非0終了（login / 認証失敗を除く）になった場合は、Antigravity 失敗として記録 → 1回リトライ → Codex scout / independent reviewer へフォールバックする。preflight または本実行が login / 認証失敗（auth_prompt / "Opening authentication page" / "Do you want to continue?" / "not authenticated" / "login required" / 対話ログイン、exit 42）で停止した場合は、まず sandbox が認証 surface だけを隠した可能性として同一 engine の `authenticated_transport_without_cli_sandbox` retry を 1 回だけ行い、両 attempt の output path / classification を記録する。retry でも auth の場合は、別 engine への暗黙の代替をせず処理を停止し、ユーザーに認証修正を依頼する（設定不備を隠さない）。

### 3. Codex verifier
Claude authored PR または外部生成パッチのときのみ実行する。

```bash
if [ -s "$POLICY_DENIED_FILE" ]; then
  echo "skipped: policy_denied: $(cat "$POLICY_DENIED_FILE")" > /tmp/codex-review-result.json
else
  cat > /tmp/codex-review.md <<PROMPT
以下の PR を verifier としてレビューしてください。

- セキュリティ
- エッジケース
- テスト / 解析コマンドの実行
- 再現手順
- Structure-Behavior risk（手続き的実装、責務配置、境界/IF、振る舞いテスト）
- generated なコードと判断できるものは原則スキップし、generator / schema / template 側を見る

まず以下を実行してください。
1. git diff origin/main...HEAD
2. <test_command>
3. <analyze_command>
PROMPT

  codex exec --full-auto   -c 'agents.default.config_file="$HOME/.codex/agents/reviewer.toml"'   -o /tmp/codex-review-result.json   - < /tmp/codex-review.md 2>/tmp/codex-review.err
fi
```

### 4. Claude 統合
Claude は以下を行う。
1. Antigravity の repo-wide 指摘を確認
2. Codex の実行証跡付き指摘を確認
3. diff 全体を実読して採用 / 棄却を判断
4. PR コメントに統合結果を投稿

### 5. 投稿フォーマット
```markdown
## Multi-AI Review Results

### レビュアー
- Antigravity/policy scout: ✅ / ❌
- Codex verifier or Claude reviewer: ✅ / ❌
- Integrator / Claude specialist: ✅ / ❌

### CRITICAL
| 指摘 | ファイル:行 | 検出AI | 修正案 |

### MAJOR
| 指摘 | ファイル:行 | 検出AI | 修正案 |

### MINOR
| 指摘 | ファイル:行 | 検出AI | 修正案 |
```

### 6. 修正ループ
- CRITICAL / MAJOR → 修正 → 再レビュー
- MINOR のみ → Claude がマージ可否を最終判断
- レビュー後に追加修正・rebase・force-with-lease push をした場合は、最新 head に対して再度 `@codex review` を依頼する
- docs-only PR の標準検証は `git diff --check`、関連 grep、リポジトリ既存の軽量テスト（例: `python3 tests/test_install_sync.py`）、シェル構文チェックを優先する

### 7. エラーハンドリング
- Antigravity / Codex が transient 失敗（quota / capacity / timeout / 空出力 / 非0終了、login / 認証失敗を除く）→ 1回リトライ
- Antigravity が headless 認証プロンプト（login / 認証失敗）で停止 → ブラウザを開かず処理を停止し、別 engine への暗黙の代替をせずユーザーに認証修正を依頼する（設定不備を隠さないため fallback / リトライしない）
- Codex の固定ロール subagent が `model is not supported` で失敗 → `agent_type` 未指定の default subagent で代替
- 2回目も失敗 → Claude reviewer で補完
- 最低2系統のレビューが成功すれば統合を続行する。欠落した系統と理由は PR コメントに記録する
