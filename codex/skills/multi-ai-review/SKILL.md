---
name: multi-ai-review
description: Gemini scout・独立 verifier・Codex integrator を組み合わせ、GitHubメンションではなくローカル実行結果をPRコメントに集約する
---

# Multi-AI Review for Codex

## 目的
Codex 主体の作業でも、Claude 側 dotfiles と同じ考え方で **Gemini scout / 独立 verifier / Codex integrator** の多重レビューを実行する。

この skill は `@claude @gemini multi-ai-review` のような GitHub メンション方式を使わない。外部 AI を GitHub reviewer / collaborator として追加せず、ローカル CLI / subagent の結果を Codex が統合し、`gh pr comment` で PR に記録する。

## トリガー
- ユーザーが `multi-ai-review` を依頼したとき
- 自律PRフローで、PR作成後の多重レビューが必要なとき
- マージ前に Gemini / Claude / Codex の観点を統合したいとき

## 原則

- **GitHubメンション禁止**: `@claude @gemini multi-ai-review` は使わない。
- **GitHub reviewer追加禁止**: Gemini / Claude / Codex などの AI アカウントを reviewer / collaborator に追加しない。
- **投稿はPRコメント**: 統合結果は `gh pr comment` で投稿する。`gh pr review` はユーザーまたはプロジェクト規約で明示される場合以外は使わない。
- **headless優先**: Gemini / Claude Code CLI は headless で実行し、ブラウザ認証プロンプトが出たら止める。
- **外部AIへのデータ送信境界**: PR diff / issue / review comment を Gemini / Claude Code CLI / ai-review へ渡す前に `~/.codex/config.toml` の `[auto_review].policy` を満たすことを確認する。ユーザーが `multi-ai-review` / Claude / Gemini / ai-review 利用を明示し、かつ policy gate を満たす場合は、このリポジトリの PR diff・関連 Issue・レビューコメントを configured external AI CLI に渡す承認済みとして扱う。secrets・認証情報・repo外 private file・Downloads 等を追加で渡す場合だけ確認する。明示がない場合、または policy gate を満たさない場合は確認・skip する。
- **最低2系統**: 2系統以上のレビューが成功すれば統合を続行できる。失敗した系統と理由はコメントに記録する。
- **sandbox拒否時の扱い**: 外部 AI CLI が sandbox / auth / quota で拒否された場合、代替禁止の明示がない限りユーザー確認で停止せず、拒否理由を PR コメントへ記録して default subagent / Codex verifier / local gate で補完する。
- **generated code**: 生成物は原則レビュー対象外。generator / schema / template / build 設定を優先する。
- **CIゲート**: `gh pr checks` の `no checks reported` だけを CI 未設定扱いにする。`fail` / `cancel` / `pending` / 認証・通信エラーはマージ不可として扱う。
- **Structure-Behavior**: Medium / High risk の変更では、手続き化・責務配置・境界/IF・振る舞いテストの観点を必ず統合レビューに含める。
- **rtk等のプロジェクト規約優先**: `AGENTS.md` / `CLAUDE.md` が shell wrapper（例: `rtk`）を要求する場合、すべての shell 実行に従う。

## レビュアー構成

| authored by | 1st pass | 2nd pass | integrator |
|---|---|---|---|
| Codex | Gemini scout | Claude Code reviewer（不可なら default subagent reviewer） | Codex |
| Claude | Gemini scout | Codex verifier | Codex |
| Gemini / 外部生成 | Codex verifier | Claude Code reviewer（不可なら default subagent reviewer） | Codex |
| 不明 | Gemini scout | Codex verifier + 必要なら default subagent reviewer | Codex |

Codex authored PR では利益相反を避け、Codex verifier を独立レビュー扱いにしない。Claude Code CLI が使えない場合は、代替 reviewer の欠落理由を明記する。

## 手順

### 1. 前提確認

1. `AGENTS.md` / `CLAUDE.md` / プロジェクト規約を読む。
2. カレントブランチと対象 PR を確認する。
3. `main` 直作業ではないことを確認する。
4. PR の author / 実装主体を PR本文・コミット・会話履歴から推定する。
5. 外部AIに渡す情報の範囲を確認する。

```bash
PR_NUMBER=${PR_NUMBER:-$(gh pr view --json number --jq '.number')}
PROJECT=$(basename "$(pwd)")
BASE_BRANCH=${BASE_BRANCH:-main}
HEAD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

### 2. コンテキスト収集

diff だけでレビューしない。Issue、PR本文、過去コメント、CI、変更ファイルを含める。

```bash
WORK_DIR=/tmp/${PROJECT}-pr${PR_NUMBER}-multi-ai-review
mkdir -p "$WORK_DIR"

PR_INFO_FILE="$WORK_DIR/pr-info.md"
ISSUE_INFO_FILE="$WORK_DIR/issues.md"
REVIEWS_FILE="$WORK_DIR/reviews.md"
INLINE_COMMENTS_FILE="$WORK_DIR/inline-comments.md"
CHECKS_JSON="$WORK_DIR/checks.json"
CHECKS_ERR="$WORK_DIR/checks.err"
DIFF_FILE="$WORK_DIR/diff.patch"
POLICY_DENIED_FILE="$WORK_DIR/policy-denied.md"
: > "$POLICY_DENIED_FILE"

# PR情報
gh pr view "$PR_NUMBER" --json number,title,body,author,headRefName,baseRefName,url \
  --template 'PR #{{.number}}: {{.title}}{{"\n"}}URL: {{.url}}{{"\n"}}author: {{.author.login}}{{"\n"}}head: {{.headRefName}}{{"\n"}}base: {{.baseRefName}}{{"\n\n"}}{{.body}}' \
  > "$PR_INFO_FILE"

# 関連Issue
: > "$ISSUE_INFO_FILE"
for n in $(gh pr view "$PR_NUMBER" --json body --jq '.body // ""' | grep -oE '#[0-9]+' | tr -d '#' | sort -u); do
  gh issue view "$n" --json number,title,body \
    --template 'Issue #{{.number}}: {{.title}}{{"\n\n"}}{{.body}}{{"\n\n---\n"}}' \
    >> "$ISSUE_INFO_FILE" 2>/dev/null || true
done

# 過去レビュー / インラインコメント
gh pr view "$PR_NUMBER" --json reviews \
  --jq '.reviews[]? | "【" + .state + "】" + .author.login + "\n" + (.body // "") + "\n---"' \
  > "$REVIEWS_FILE" 2>/dev/null || true

gh api repos/$REPO/pulls/$PR_NUMBER/comments \
  --jq '.[]? | (.path // "") + " L" + ((.line // .original_line // 0)|tostring) + ": " + (.body // "") + "\n---"' \
  > "$INLINE_COMMENTS_FILE" 2>/dev/null || true

# CI状態
set +e
gh pr checks "$PR_NUMBER" --json name,bucket,state,workflow,link >"$CHECKS_JSON" 2>"$CHECKS_ERR"
CHECKS_EXIT=$?
set -e

# diff / external AI policy gate
git fetch origin "$BASE_BRANCH" --quiet
SENSITIVE_PATH_RE='(^|/)(\.env(\..*)?|\.aws/|\.ssh/|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?|.*\.(pem|key|p12|pfx)|.*secret.*|.*credential.*|.*token.*|.*history)$'
if git diff --name-only "origin/${BASE_BRANCH}...HEAD" | grep -Eiq "$SENSITIVE_PATH_RE"; then
  echo "sensitive path changed; external AI review skipped by policy" > "$POLICY_DENIED_FILE"
elif git diff "origin/${BASE_BRANCH}...HEAD" --unified=0 | grep -Eq '^\+.*(BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,})'; then
  echo "secret-looking added content; external AI review skipped by policy" > "$POLICY_DENIED_FILE"
fi

if [ -s "$POLICY_DENIED_FILE" ]; then
  : > "$DIFF_FILE"
else
  git diff "origin/${BASE_BRANCH}...HEAD" --unified=10 > "$DIFF_FILE"
fi
```

CI 判定は以下で行う。

```bash
CI_STATUS_FILE="$WORK_DIR/ci-status.md"
if [ -s "$CHECKS_JSON" ] && jq -e 'length > 0' "$CHECKS_JSON" >/dev/null 2>&1; then
  jq -r '.[] | "- " + .name + ": " + .bucket + " (" + .state + ")" + (if .link then " " + .link else "" end)' "$CHECKS_JSON" > "$CI_STATUS_FILE"
  if jq -e 'any(.[]; .bucket == "fail" or .bucket == "cancel" or .bucket == "pending")' "$CHECKS_JSON" >/dev/null; then
    echo "BLOCKING_CHECKS=true" >> "$CI_STATUS_FILE"
  fi
elif grep -qi 'no checks reported' "$CHECKS_ERR"; then
  echo "no checks reported" > "$CI_STATUS_FILE"
else
  {
    echo "checks unavailable/error (exit ${CHECKS_EXIT})"
    cat "$CHECKS_ERR"
  } > "$CI_STATUS_FILE"
  echo "BLOCKING_CHECKS=true" >> "$CI_STATUS_FILE"
fi
```

### 3. Gemini scout

Gemini は repo-wide consistency scout として使う。ブラウザ認証プロンプト、timeout、空出力、非0終了は失敗として扱い、ブラウザを開かない。

```bash
GEMINI_PROMPT_FILE="$WORK_DIR/gemini-prompt.md"
GEMINI_PREFLIGHT_OUT="$WORK_DIR/gemini-preflight.md"
GEMINI_REVIEW_OUT="$WORK_DIR/gemini-review.md"

cat > "$GEMINI_PROMPT_FILE" <<PROMPT
以下の PR を read-only scout / critic としてレビューしてください。

観点:
- 既存パターンとの整合性
- 命名 drift
- docs / config / l10n 更新漏れ
- diff 外影響
- Structure-Behavior drift（肥大 usecase / handler、責務漏れ、data-only model、primitive obsession、IF劣化、振る舞いテスト不足）
- generated code は原則スキップし、generator / schema / template / build 設定を見る

出力:
- 指摘は ファイル名:行番号 形式
- 重大度は MUST / SHOULD / NIT
- 最終判定は APPROVE / REQUEST_CHANGES

## PR
$(cat "$PR_INFO_FILE")

## 関連Issue
$(cat "$ISSUE_INFO_FILE")

## 過去レビュー
$(cat "$REVIEWS_FILE")

## インラインコメント
$(cat "$INLINE_COMMENTS_FILE")

## CI
$(cat "$CI_STATUS_FILE")

## Diff
\`\`\`diff
$(cat "$DIFF_FILE")
\`\`\`
PROMPT

if [ -s "$POLICY_DENIED_FILE" ]; then
  GEMINI_AVAILABLE=false
  echo "skipped: policy_denied: $(cat "$POLICY_DENIED_FILE")" > "$GEMINI_REVIEW_OUT"
else
  GEMINI_AVAILABLE=true
fi
export GEMINI_PREFLIGHT_OUT
if [ "$GEMINI_AVAILABLE" = true ]; then
python3 - <<'PY'
import os, subprocess, sys
prompt = "read-only preflight。1行だけ返してください。"
env = os.environ.copy()
env["GEMINI_SYSTEM_MD"] = os.path.expanduser("~/.gemini/agents/reviewer.md")
env["TERM"] = "xterm-256color"
out_path = os.environ["GEMINI_PREFLIGHT_OUT"]
try:
    proc = subprocess.run(
        ["gemini", "--approval-mode", "plan", "-p", " ", "-e", "none"],
        input=prompt,
        text=True,
        capture_output=True,
        timeout=20,
        env=env,
    )
    text = (proc.stdout or "") + (proc.stderr or "")
except subprocess.TimeoutExpired as exc:
    text = ((exc.stdout or "") if isinstance(exc.stdout, str) else "") + ((exc.stderr or "") if isinstance(exc.stderr, str) else "") + "\nTIMEOUT_AFTER=20\n"
    open(out_path, "w").write(text)
    sys.exit(124)
open(out_path, "w").write(text)
if "Opening authentication page in your browser" in text or "Do you want to continue?" in text:
    sys.exit(42)
if not text.strip() or proc.returncode != 0:
    sys.exit(proc.returncode or 1)
PY
case $? in
  0) ;;
  *) GEMINI_AVAILABLE=false ;;
esac
fi

if [ "$GEMINI_AVAILABLE" = true ]; then
  export GEMINI_PROMPT_FILE GEMINI_REVIEW_OUT
  python3 - <<'PY'
import os, subprocess, sys
prompt = open(os.environ["GEMINI_PROMPT_FILE"]).read()
env = os.environ.copy()
env["GEMINI_SYSTEM_MD"] = os.path.expanduser("~/.gemini/agents/reviewer.md")
env["TERM"] = "xterm-256color"
out_path = os.environ["GEMINI_REVIEW_OUT"]
try:
    proc = subprocess.run(
        ["gemini", "--approval-mode", "plan", "-p", " ", "-e", "none"],
        input=prompt,
        text=True,
        capture_output=True,
        timeout=600,
        env=env,
    )
    text = (proc.stdout or "") + (proc.stderr or "") + f"\nEXIT_CODE={proc.returncode}\n"
except subprocess.TimeoutExpired as exc:
    text = ((exc.stdout or "") if isinstance(exc.stdout, str) else "") + ((exc.stderr or "") if isinstance(exc.stderr, str) else "") + "\nTIMEOUT_AFTER=600\nKILLED=true\n"
    open(out_path, "w").write(text)
    sys.exit(124)
open(out_path, "w").write(text)
if "Opening authentication page in your browser" in text or "Do you want to continue?" in text:
    sys.exit(42)
if not text.strip() or proc.returncode != 0:
    sys.exit(proc.returncode or 1)
PY
  case $? in
    0) ;;
    *) GEMINI_AVAILABLE=false ;;
  esac
fi

if [ "$GEMINI_AVAILABLE" != true ]; then
  echo "Gemini failed or unavailable. See $GEMINI_PREFLIGHT_OUT / $GEMINI_REVIEW_OUT" > "$GEMINI_REVIEW_OUT"
fi
```

### 4. 独立 verifier

Codex authored PR では、可能なら Claude Code CLI を reviewer として使う。Claude Code CLI が使えない、認証待ち、quota、timeout の場合は default subagent reviewer へフォールバックし、欠落理由を記録する。

Claude / 外部生成 authored PR では Codex verifier を使い、実行証跡を必ず含める。

Codex の spawn_agent が使える環境では、ユーザーが `multi-ai-review` を依頼しているため reviewer subagent を使ってよい。固定ロールが `model is not supported` の場合は `agent_type` 未指定の default subagent で同じ依頼を再実行する。

#### verifier prompt

```bash
VERIFIER_PROMPT_FILE="$WORK_DIR/verifier-prompt.md"
VERIFIER_REVIEW_OUT="$WORK_DIR/verifier-review.md"

cat > "$VERIFIER_PROMPT_FILE" <<PROMPT
以下の PR を verifier としてレビューしてください。

観点:
- セキュリティ
- エッジケース
- テスト不足
- 実装意図との不一致
- Structure-Behavior risk（手続き的実装、責務配置、境界/IF、振る舞いテスト）
- generated code は原則スキップし、generator / schema / template / build 設定を見る

必ず確認すること:
1. git diff origin/${BASE_BRANCH}...HEAD
2. プロジェクトの AGENTS.md / CLAUDE.md に記載された test / analyze / lint
3. docs-only の場合は git diff --check、関連 grep、軽量テスト、シェル構文チェック

出力は以下の JSON 形式を含めてください:
{
  "source": "<reviewer>",
  "validated_commands": ["実行したコマンド"],
  "results": {"passed": ["成功項目"], "failed": ["失敗項目"]},
  "residual_risks": ["残リスク"],
  "findings": [
    {"severity": "MUST|SHOULD|NIT", "file": "path:line", "issue": "指摘", "fix": "修正案"}
  ],
  "verdict": "APPROVE|REQUEST_CHANGES"
}

## PR
$(cat "$PR_INFO_FILE")

## 関連Issue
$(cat "$ISSUE_INFO_FILE")

## 過去レビュー
$(cat "$REVIEWS_FILE")

## インラインコメント
$(cat "$INLINE_COMMENTS_FILE")

## CI
$(cat "$CI_STATUS_FILE")
PROMPT
```

Codex CLI で verifier を走らせる場合:

```bash
if [ -s "$POLICY_DENIED_FILE" ]; then
  cat > "$VERIFIER_REVIEW_OUT" <<JSON
{
  "source": "policy-gate",
  "validated_commands": [],
  "results": {"passed": [], "failed": []},
  "residual_risks": ["skipped: policy_denied: $(cat "$POLICY_DENIED_FILE")"],
  "findings": [],
  "verdict": "SKIPPED"
}
JSON
else
  codex exec --full-auto \
    -c 'agents.default.config_file="$HOME/.codex/agents/reviewer.toml"' \
    -o "$VERIFIER_REVIEW_OUT" \
    - < "$VERIFIER_PROMPT_FILE" \
    2>"$WORK_DIR/verifier-review.err" || true
fi
```

Claude Code CLI を使う場合は、headless 実行が可能なことを `claude --help` 等で確認してから使う。対話ログインやブラウザ認証が出た場合は起動せず、fallback する。

### 5. Codex 統合レビュー

Codex integrator は以下を行う。

1. Gemini の repo-wide 指摘を読む。
2. verifier の実行証跡付き指摘を読む。
3. diff と関連コードを自分でも実読する。
4. 指摘を採用 / 棄却する。棄却時は理由と確認根拠を書く。
5. CI 状態をマージゲートとして評価する。
6. PR コメントを作成する。

統合コメントは Markdown ファイルに書いてから投稿する。

```bash
COMMENT_FILE="$WORK_DIR/multi-ai-review-comment.md"
cat > "$COMMENT_FILE" <<'MD'
## 🤖 Multi-AI Review Results

### レビュアー
- Gemini scout: ✅ / ❌（理由）
- Independent verifier: ✅ / ❌（理由）
- Codex integrator: ✅ / ❌

### 🔴 MUST
| 指摘 | ファイル:行 | 検出AI | 採用判断 | 修正案 |
|---|---|---|---|---|

### 🟠 SHOULD
| 指摘 | ファイル:行 | 検出AI | 採用判断 | 修正案 |
|---|---|---|---|---|

### 🟡 NIT
| 指摘 | ファイル:行 | 検出AI | 採用判断 | 修正案 |
|---|---|---|---|---|

### CI / 検証
- ...

### 総合判定
APPROVE / REQUEST_CHANGES
MD

gh pr comment "$PR_NUMBER" --body-file "$COMMENT_FILE"
```

## 修正ループ

- MUST / CRITICAL / HIGH 相当は修正必須。
- SHOULD は、リリース品質・ユーザー影響・保守性に関わるものを原則修正する。
- NIT のみなら integrator が採否を判断する。
- 修正後は test / analyze / lint を再実行する。
- 追加修正・rebase・force-with-lease push 後は再度 multi-ai-review、またはプロジェクト規約に従って `@codex review` を依頼する。
- PR head が変わった場合、古いレビュー結果でマージしない。

## 失敗時の扱い

| 失敗 | 対応 |
|---|---|
| Gemini が browser auth prompt | ブラウザを開かず失敗扱い。理由を記録し fallback |
| Gemini timeout / quota / 空出力 | 1回だけ再試行。失敗なら fallback |
| Claude Code CLI 不可 | default subagent reviewer または Codex verifier に fallbackし、利益相反リスクを明記 |
| Codex reviewer role が model unsupported | `agent_type` 未指定の default subagent で再実行 |
| `gh pr checks` 認証・通信エラー | CI状態不明としてマージ不可 |
| `no checks reported` | CI未設定/未報告。マージ可否は他検証で判断 |

## 禁止

- `@claude @gemini multi-ai-review` を PR コメントに投げること。
- AI アカウントを GitHub reviewer / collaborator に追加すること。
- headless 失敗時に勝手にブラウザログインを進めること。
- テスト未実行で verifier を成功扱いにすること。
- diff に存在しない内容をレビュー結果として捏造すること。
- 失敗したレビュアーを黙って省略すること。
