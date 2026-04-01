---
description: 複数のGitHubイシューを優先順位順に自律的に実装・レビュー・マージする
argument-hint: [issue-numbers...] or "auto" (自動優先順位付け)
allowed-tools: ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "Task"]
---

# スプリントワークフロー

対象: **$ARGUMENTS**
- 番号指定の場合: 例 `395 396 397` → 順番に処理
- `auto` の場合: `gh issue list` から優先度を自動判定

## ステップ1: スプリント計画

### 引数が "auto" の場合
```bash
gh issue list --state open --json number,title,labels,milestone
```
上記の結果から以下の優先度でソート:
1. `bug` ラベル (最高優先)
2. マイルストーン付き
3. `feature` ラベル
4. `enhancement` ラベル
5. `chore` ラベル

上位3〜5件をユーザーに提示して確認を取る。

### 番号指定の場合
指定された番号順に処理計画を表示し、ユーザーに確認を取る。
**必ず `gh issue view <number>` でイシュー番号とタイトルをダブルチェックすること。**

### 1-3. 全イシューの scout pass（Gemini + Codex 並列）

イシューを確定した後、実装ループに入る前に全イシューの **2系統 scout** を実施する。

- **Gemini**: repo-wide scout / critic
  - 既存パターン、命名一貫性、diff 外影響、docs / config / l10n drift
- **Codex**: worker / verifier 視点の scout
  - テスト戦略、セキュリティ、実装分割、validation plan

**スキップ条件:** l10n テキストのみ・定数追加のみ・1行レベルの自明な修正はそのイシューの scout を省略してよい。

```bash
PROJECT=$(basename "$(pwd)")
PROJECT_DIR=$(pwd)
SPRINT_TMP_FILES=()

for ISSUE_NUMBER in "${ISSUES[@]}"; do
  ISSUE_CONTENT=$(gh issue view "$ISSUE_NUMBER" --json number,title,body,labels     --template 'Issue #{{.number}}: {{.title}}
Labels: {{range .labels}}{{.name}} {{end}}

{{.body}}')
  PROJECT_CONTEXT=$(head -80 CLAUDE.md 2>/dev/null || echo "（なし）")

  GEMINI_PROMPT_FILE="/tmp/${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout.md"
  CODEX_PROMPT_FILE="/tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout.md"

  SPRINT_TMP_FILES+=(
    "$GEMINI_PROMPT_FILE"
    "/tmp/${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout-result.md"
    "$CODEX_PROMPT_FILE"
    "/tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout-result.md"
    "/tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout.err"
  )

  cat > "$GEMINI_PROMPT_FILE" <<PROMPT_EOF
以下のイシューについて、read-only でリポジトリ全体を探索し、scout / critic として提案してください。
コードは変更しないこと。

## プロジェクト規約
${PROJECT_CONTEXT}

## 実装対象イシュー
${ISSUE_CONTENT}

## 見てほしい観点
1. 関連する既存実装・パターン・命名規約
2. diff 外で影響を受けるファイル、呼び出し元、関連ドキュメント
3. docs / config / l10n / schema 更新漏れの有無
4. 実装を Claude foreground に残すべきかどうか

## 回答形式
### 既存パターン
### 影響ファイル一覧
### drift チェック（docs/config/l10n）
### リスク・注意点
### 実装担当の推奨（Claude / Codex と理由）
### 不明点・要確認事項（なければ「なし」）
PROMPT_EOF

  cat > "$CODEX_PROMPT_FILE" <<PROMPT_EOF
以下のイシューについて、worker / verifier 視点で設計提案してください。
コードは変更しないこと。

## プロジェクト規約
${PROJECT_CONTEXT}

## 実装対象イシュー
${ISSUE_CONTENT}

## 見てほしい観点
1. 変更を小さく分ける実装順序
2. 書くべきテスト、異常系、境界値、セキュリティ確認
3. 実行すべき validation command
4. Codex worker に向くか、Claude foreground に残すべきか

## 回答形式
### 実装アプローチ
### テスト戦略
### セキュリティ・エッジケース
### validation plan
### 実装担当の推奨（Claude / Codex と理由）
### 不明点・要確認事項（なければ「なし」）
PROMPT_EOF

done

for ISSUE_NUMBER in "${ISSUES[@]}"; do
  tmux new-session -d -s ${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout     "TERM=xterm-256color gemini --approval-mode plan -p ' ' -e none      < /tmp/${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout.md      > /tmp/${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout-result.md 2>&1;      printf 'EXIT_CODE=%s\n' \$? >> /tmp/${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout-result.md;      tmux wait-for -S ${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout-done"

  tmux new-session -d -s ${PROJECT}-issue${ISSUE_NUMBER}-codex-scout     "cd ${PROJECT_DIR} && codex exec -s read-only      -o /tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout-result.md      - < /tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout.md      2>/tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout.err;      printf 'EXIT_CODE=%s\n' \$? >> /tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout-result.md;      tmux wait-for -S ${PROJECT}-issue${ISSUE_NUMBER}-codex-scout-done"
done

for ISSUE_NUMBER in "${ISSUES[@]}"; do
  tmux wait-for ${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout-done
  tmux wait-for ${PROJECT}-issue${ISSUE_NUMBER}-codex-scout-done
done
```

### 1-4. scout 結果の Issue コメント投稿 & 不明点の分類・処理

各イシューの scout 結果を GitHub Issue にコメント投稿して永続化する。
不明点は **エンドユーザー体験に関わるものだけ** ユーザーに確認し、技術的なものは自律判断して Issue コメントに記録する。

```bash
QUESTIONS=""
declare -A ROUTING  # ROUTING[ISSUE_NUMBER]="claude" or "codex"

for ISSUE_NUMBER in "${ISSUES[@]}"; do
  GEMINI_RESULT=$(cat /tmp/${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout-result.md 2>/dev/null || echo "（Gemini scout 失敗）")
  CODEX_RESULT=$(cat /tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout-result.md 2>/dev/null || echo "（Codex scout 失敗）")

  # ルーティング判断は Claude が両方の結果を読み、後述の基準で決める
  # ROUTING[$ISSUE_NUMBER]="claude" または "codex"

  gh issue comment "$ISSUE_NUMBER" --body "## 🤖 Multi-AI scout 結果

### Gemini scout
${GEMINI_RESULT}

### Codex scout
${CODEX_RESULT}

---
**実装担当:** ${ROUTING[$ISSUE_NUMBER]:-claude}"

  Q_GEMINI=$(echo "$GEMINI_RESULT" | awk '/### 不明点・要確認事項/{f=1; next} f && /^### /{exit} f{print}' | grep -v 'なし' | head -10)
  Q_CODEX=$(echo "$CODEX_RESULT" | awk '/### 不明点・要確認事項/{f=1; next} f && /^### /{exit} f{print}' | grep -v 'なし' | head -10)
  Q_COMBINED=$(printf "%s
%s" "$Q_GEMINI" "$Q_CODEX" | sed '/^$/d' | head -10)

  [ -n "$Q_COMBINED" ] && QUESTIONS+="### Issue #${ISSUE_NUMBER}
${Q_COMBINED}

"
done

if [ -n "$QUESTIONS" ]; then
  echo "=== scout で確認が必要な事項（エンドユーザー体験に関わるもの）==="
  echo -e "$QUESTIONS"
  echo "上記を確認してから実装ループに入ります。回答をお願いします。"
fi
```

**ルーティング判断基準:**

| 条件 | 担当 |
|------|------|
| UI コンポーネントの実装・変更を含む | **Claude** |
| 複数レイヤーにわたる複雑なビジネスロジック | **Claude** |
| 5ファイル超の連鎖修正（大規模リファクタリング） | **Claude** |
| バグ修正（原因特定が必要・複雑な再現条件） | **Claude** |
| Gemini が「diff 外影響が広い」と判断した | **Claude** |
| テストのみ追加・拡充（実装変更なし） | **Codex** |
| CI/CD・シェルスクリプト・設定ファイル変更 | **Codex** |
| 単純な CRUD 追加（UI なし・既存パターンあり） | **Codex** |
| l10n / 定数 / 設定値の追加（ロジック変更なし） | **Codex** |
| セキュリティ修正・バリデーション追加 | **Codex** |
| 技術調査・スパイク | **Codex** |

**優先ルール:** UI 変更を1つでも含む → Claude。判断できない → Claude（下振れ許容）。

## ステップ2: 各イシューの処理ループ

各イシューに対して以下を順番に実行する:

### 2-1. イシュー確認

```bash
gh issue view <number>
gh issue view <number> --comments | tail -80
```

scout コメントを読み、実装方針・影響ファイル・担当ルーティングを確認する。

### 2-2. 実装（ルーティング）

ステップ1-4 で決定した `ROUTING[$ISSUE_NUMBER]` に従って実装担当を選択する。

#### 2-2a: Claude が実装する場合

- `main` から新しいブランチを作成: `feature/issue-<number>-<short-description>`
- scout コメントを参照しつつ関連ファイルを読んで既存パターンを確認する
- まずテストを書き、次に実装する（TDD推奨）
- 全レイヤーにわたって実装する（model, repository, service, UI, i18n, tests など）
- `test_command`（CLAUDE.md の AI レビュー設定）でテスト通過を確認
- `analyze_command`（CLAUDE.md の AI レビュー設定）でエラーがないことを確認
- Gemini scout が指摘した docs / config / l10n drift を取りこぼさない

#### 2-2b: Codex が実装する場合

**実装依頼プロンプト生成（handoff-to-codex.md テンプレートに準拠）:**

```bash
CODEX_IMPL_PROMPT_FILE="/tmp/${PROJECT}-issue${ISSUE_NUMBER}-impl-prompt.md"
SPRINT_TMP_FILES+=(
  "$CODEX_IMPL_PROMPT_FILE"
  "/tmp/${PROJECT}-issue${ISSUE_NUMBER}-impl-result.md"
  "/tmp/${PROJECT}-issue${ISSUE_NUMBER}-impl-result.err"
)

GEMINI_RESULT=$(cat /tmp/${PROJECT}-issue${ISSUE_NUMBER}-gemini-scout-result.md 2>/dev/null || echo "（Gemini scout なし）")
CODEX_SCOUT_RESULT=$(cat /tmp/${PROJECT}-issue${ISSUE_NUMBER}-codex-scout-result.md 2>/dev/null || echo "（Codex scout なし）")
CODEX_TEST_CMD=$(grep 'test_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/' | tr -d '\n')
CODEX_ANALYZE_CMD=$(grep 'analyze_command' CLAUDE.md 2>/dev/null | sed 's/.*`\([^`]*\)`[^`]*$/\1/' | tr -d '\n')
ISSUE_CONTENT=$(gh issue view "$ISSUE_NUMBER" --json number,title,body   --template 'Issue #{{.number}}: {{.title}}

{{.body}}')
ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --json title --jq '.title')

cat > "$CODEX_IMPL_PROMPT_FILE" <<PROMPT_EOF
以下のイシューを実装してください。

## Objective
Issue #${ISSUE_NUMBER} を実装する: ${ISSUE_TITLE}

## イシュー内容
${ISSUE_CONTENT}

## Out of Scope
- イシューで明示されていないリファクタリング
- 関係のない既存コードの変更

## Constraints
- ブランチ: feature/issue-${ISSUE_NUMBER}-<short-description>（main から作成）
- コミットメッセージは日本語で記述すること
- 既存の命名規約・コード規約（CLAUDE.md 参照）に従うこと
- main への直接コミット禁止

## Gemini scout（repo-wide / drift）
${GEMINI_RESULT}

## Codex scout（worker / verifier）
${CODEX_SCOUT_RESULT}

## Required Validation
${CODEX_TEST_CMD:+- \`$CODEX_TEST_CMD\`}
${CODEX_ANALYZE_CMD:+- \`$CODEX_ANALYZE_CMD\`}

## Output Format
- 変更ファイル一覧
- テスト・解析コマンドの実行結果
- 残リスク・未対応事項
PROMPT_EOF

codex exec --full-auto   -o /tmp/${PROJECT}-issue${ISSUE_NUMBER}-impl-result.md   - < "$CODEX_IMPL_PROMPT_FILE"   2>/tmp/${PROJECT}-issue${ISSUE_NUMBER}-impl-result.err
IMPL_EXIT=$?
echo "EXIT_CODE=${IMPL_EXIT}" >> /tmp/${PROJECT}-issue${ISSUE_NUMBER}-impl-result.md
```

**実装完了後の確認（Claude が担当）:**
1. `test_command` / `analyze_command` をローカルで再実行して結果を確認
2. 失敗があれば Claude がフォローアップ修正
3. コミット分割を整理する（論理的な単位になっているか確認）
4. Gemini scout の drift 指摘が反映済みか確認する
5. ドラフト PR 作成 → 2-3 へ

**フォールバック:**
- EXIT_CODE 非ゼロ → 1回リトライ（同じコマンドを再実行）
- 2回目も失敗 → Claude が実装に切り替え（2-2a フローへ）

### 2-3. コミット分割 & ドラフトPR作成
- 実装を論理的なコミットに分割する（1つの関心事につき1コミット）
- **コミットメッセージは日本語で記述する**（例: `feat: 散歩履歴の削除機能を追加`）
```bash
git push -u origin HEAD
gh pr create --draft --title "..." --body "Closes #<number>

..."
```

### 2-4. AI 並列レビュー

実装担当（Claude / Codex）に応じてレビュアー構成を変える。**忖度なしの厳格なレビュー**を行うこと。
問題がないコードでも無理に問題を作り出す必要はないが、発見した問題は重大度に関わらずすべて報告する。

#### レビュアー構成

**Claude が実装した場合（Gemini scout + Codex verifier + Claude final）:**
| # | AI | 実行方法 | 役割 |
|---|-----|---------|------|
| 1 | Gemini CLI | tmux + `gemini --approval-mode plan -p` | 1st pass（設計・一貫性・diff 外影響） |
| 2 | Codex CLI | tmux + `codex exec` | 1st pass（実装品質・セキュリティ・テスト実行） |
| 3 | Claude Code | メインセッション / Task | 最終レビュー（マージ判断） |

**Codex が実装した場合（利益相反回避）:**
| # | AI | 実行方法 | 役割 |
|---|-----|---------|------|
| 1 | Gemini CLI | tmux + `gemini --approval-mode plan -p` | 1st pass（設計・一貫性・diff 外影響） |
| 2 | Claude Code (Task) | サブエージェント | Codex 代替（実装品質・セキュリティ観点） |
| 3 | Claude Code | メインセッション | 最終レビュー（マージ判断） |
| ~~Codex~~ | スキップ | — | 実装担当のため利益相反回避 |

以降のレビュー詳細は `/review-and-merge` に従う。Critical / Major 指摘が出たら修正して再レビューを回す。

## ステップ3: マージ後処理

各 PR のマージ後に以下を行う。

```bash
git checkout main
git pull origin main
gh issue list --state open --limit 10
```

- 関連 Issue がクローズされたことを確認する
- 次に着手するイシューを優先順位に従って選ぶ
- スプリント対象が残っていれば次の Issue に進む

## 注意事項

- **コミットメッセージは必ず日本語**で記述する
- **Gemini は原則 read-only scout / critic** として使い、実装担当にしない
- **Codex は worker / verifier** として使い、実装した PR ではレビュアーから外す
- **Claude は最終統合責任** を持つ
- `gh pr review` がブロックされたら即座に `gh pr comment` にフォールバックする
