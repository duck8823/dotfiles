---
name: multi-ai-review
description: Gemini scout・Codex verifier・Claude integrator を組み合わせてPRを多重レビューする
---

# Multi-AI レビュー

## トリガー
ドラフト PR 作成後に自動呼び出し。または手動で `/multi-ai-review`

## 基本方針

- **Gemini** は read-only scout / critic
- **Codex** は security / test verifier
- **Claude** は統合判断とマージゲート
- authored-by に応じて利益相反を避ける
- ローカル CLI / subagent の失敗はプロセス停止理由を記録し、ブラウザ認証や固定モデル問題で作業を止めない


## External AI delegation policy gate

Gemini / Codex / Claude CLI へ PR diff・local branch diff・関連ソースを渡す前に、`~/.codex/config.toml` の `[auto_review].policy` にある **External AI delegation exception** を満たすことを確認する。

- 作業ディレクトリは trusted repository またはその git worktree に限定する
- 1 ticket / 1 PR にスコープを限定し、複数チケットを1つの review request に束ねない
- `.env`、credentials、tokens、private keys、secret files、shell history、無関係な repo / home directory dump を送らない
- Gemini は `gemini --approval-mode plan -p ' ' -e none` の read-only scout のみで使う
- Codex verifier は `codex exec --full-auto -c 'agents.default.config_file="$HOME/.codex/agents/reviewer.toml"'` を優先する
- policy / Guardian / sandbox の拒否が出た場合は設定を弱めず、`skipped: policy_denied` または具体的な拒否理由を記録して Claude-only fallback に進む

この gate は multi-AI review を止めるためではなく、許可条件を満たすケースで安全に回すための前処理である。

## 手順

### 1. 差分とコンテキスト収集
```bash
PR_NUMBER=<number>
PROJECT=$(basename "$(pwd)")
DIFF_FILE=/tmp/${PROJECT}-pr${PR_NUMBER}-diff.txt

git diff origin/main...HEAD > "$DIFF_FILE"
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

### 2. Gemini scout
```bash
cat > /tmp/gemini-review.md <<PROMPT
以下の PR を read-only scout / critic としてレビューしてください。

- 既存パターンとの整合性
- diff 外影響
- docs / config / l10n 更新漏れ
- 命名 drift
- generated なコードと判断できるものは原則スキップし、generator / schema / template 側を見る

## Diff
$(cat "$DIFF_FILE")
PROMPT

GEMINI_PREFLIGHT_OUT=/tmp/gemini-review-preflight.md
export GEMINI_PREFLIGHT_OUT
python3 - <<'PY'
import os, subprocess, sys
prompt = "read-only preflight。1行だけ返してください。"
env = os.environ.copy()
env["GEMINI_SYSTEM_MD"] = os.path.expanduser("~/.gemini/agents/reviewer.md")
env["TERM"] = "xterm-256color"
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
    open(os.environ["GEMINI_PREFLIGHT_OUT"], "w").write(text)
    sys.exit(124)
open(os.environ["GEMINI_PREFLIGHT_OUT"], "w").write(text)
if "Opening authentication page in your browser" in text or "Do you want to continue?" in text:
    sys.exit(42)
if not text.strip() or proc.returncode != 0:
    sys.exit(proc.returncode or 1)
PY

if [ $? -eq 0 ]; then
  python3 - <<'PY'
import os, subprocess, sys
prompt = open("/tmp/gemini-review.md").read()
env = os.environ.copy()
env["GEMINI_SYSTEM_MD"] = os.path.expanduser("~/.gemini/agents/reviewer.md")
env["TERM"] = "xterm-256color"
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
    open("/tmp/gemini-review-result.json", "w").write(text)
    sys.exit(124)
open("/tmp/gemini-review-result.json", "w").write(text)
if "Opening authentication page in your browser" in text or "Do you want to continue?" in text:
    sys.exit(42)
if not text.strip() or proc.returncode != 0:
    sys.exit(proc.returncode or 1)
PY
else
  echo "Gemini preflight failed; fallback required. See $GEMINI_PREFLIGHT_OUT" > /tmp/gemini-review-result.json
fi
```

preflight または本実行が timeout / 認証プロンプト / 空出力 / 非0終了になった場合は、Gemini 失敗として Codex scout / independent reviewer へフォールバックする。

### 3. Codex verifier
Claude authored PR または外部生成パッチのときのみ実行する。

```bash
cat > /tmp/codex-review.md <<PROMPT
以下の PR を verifier としてレビューしてください。

- セキュリティ
- エッジケース
- テスト / 解析コマンドの実行
- 再現手順
- generated なコードと判断できるものは原則スキップし、generator / schema / template 側を見る

まず以下を実行してください。
1. git diff origin/main...HEAD
2. <test_command>
3. <analyze_command>
PROMPT

codex exec --full-auto   -c 'agents.default.config_file="$HOME/.codex/agents/reviewer.toml"'   -o /tmp/codex-review-result.json   - < /tmp/codex-review.md 2>/tmp/codex-review.err
```

### 4. Claude 統合
Claude は以下を行う。
1. Gemini の repo-wide 指摘を確認
2. Codex の実行証跡付き指摘を確認
3. diff 全体を実読して採用 / 棄却を判断
4. PR コメントに統合結果を投稿

### 5. 投稿フォーマット
```markdown
## Multi-AI Review Results

### レビュアー
- Gemini scout: ✅ / ❌
- Codex verifier or Claude reviewer: ✅ / ❌
- Claude final: ✅ / ❌

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
- Gemini / Codex が失敗 → 1回リトライ
- Gemini が headless 認証プロンプトで停止 → ブラウザを開かず停止し、Codex scout / independent reviewer で代替
- Codex の固定ロール subagent が `model is not supported` で失敗 → `agent_type` 未指定の default subagent で代替
- 2回目も失敗 → Claude reviewer で補完
- 最低2系統のレビューが成功すれば統合を続行する。欠落した系統と理由は PR コメントに記録する
