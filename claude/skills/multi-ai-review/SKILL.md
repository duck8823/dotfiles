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

## 手順

### 1. 差分とコンテキスト収集
```bash
PR_NUMBER=<number>
PROJECT=$(basename "$(pwd)")
DIFF_FILE=/tmp/${PROJECT}-pr${PR_NUMBER}-diff.txt

git diff origin/main...HEAD > "$DIFF_FILE"
gh pr view "$PR_NUMBER"
gh pr checks "$PR_NUMBER"
```

### 2. Gemini scout
```bash
cat > /tmp/gemini-review.md <<PROMPT
以下の PR を read-only scout / critic としてレビューしてください。

- 既存パターンとの整合性
- diff 外影響
- docs / config / l10n 更新漏れ
- 命名 drift
- generated なファイルは原則スキップし、generator / schema / template 側を見る

## Diff
$(cat "$DIFF_FILE")
PROMPT

GEMINI_SYSTEM_MD=$HOME/.gemini/agents/reviewer.md   TERM=xterm-256color   gemini --approval-mode plan -p ' ' -e none   < /tmp/gemini-review.md > /tmp/gemini-review-result.json 2>&1
```

### 3. Codex verifier
Claude authored PR または外部生成パッチのときのみ実行する。

```bash
cat > /tmp/codex-review.md <<PROMPT
以下の PR を verifier としてレビューしてください。

- セキュリティ
- エッジケース
- テスト / 解析コマンドの実行
- 再現手順
- generated なファイルは原則スキップし、generator / schema / template 側を見る

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

### 7. エラーハンドリング
- Gemini / Codex が失敗 → 1回リトライ
- 2回目も失敗 → Claude reviewer で補完
- 最低2系統のレビューが成功すれば統合を続行する
