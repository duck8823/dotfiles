# レビューワークフロー

## Review context packet

レビュー時の必須 context と `required_context_checked` の形式は `conventions/ai/review-context-schema.md` を参照する。reviewer / verifier / integrator は、何を確認したかをレビュー結果に残す。

必須カテゴリ:

- tickets / issue / ticket
- PR intent / motivation
- docs / user-facing behavior
- conventions / architecture / quality gate
- codebase / caller / existing pattern
- prior reviews / inline comments
- test evidence / CI / 未実行理由

`docs-only-light` / `policy-docs` / `low` lane では巨大 context を要求せず、関連 docs、軽量 grep、`git diff --check`、既存の軽量テストで代替してよい。risk lane は `conventions/ai/quality-gates.md` を正本とする。不足により判断できない場合は `INSUFFICIENT_CONTEXT` とし、推測で approve しない。

## Quality gates

レビュー前 / Ready 前 / merge 前の品質 gate は `conventions/ai/quality-gates.md` を正本とする。レビュー運用はこの文書、品質 artifact と blocking policy は quality gates を優先して確認する。

## コードレビュー指針

- PR レビュー時は、diff に実際に存在する内容のみ報告すること
- CI 状態、変更ファイル数、スコープを推測・捏造しないこと
- 実際の PR データから直接確認できることのみ記載すること
- レビュー対象が見つからない場合、ユーザーに聞く前に `git diff origin/main...HEAD` でブランチ差分を確認すること
- diff に存在しない変更点や問題点を報告しないこと
- generated なコードと判断できるものは原則レビュー対象外とし、generator / schema / template / build 設定側を優先して確認すること

### diff 外の対応漏れチェック

diff の内容を確認した後、以下の観点で diff 外のソースコードも積極的に調査し、対応漏れがないか確認すること。

- 変更に対応して修正すべき他のファイル・モジュールが残っていないか
- 同様のパターンが他箇所にあり、同じ修正が必要でないか
- 変更によって影響を受ける呼び出し元・依存箇所が適切に対応されているか
- ドキュメント・設定ファイル・スキーマなど、コード以外の更新漏れがないか

調査した結果、問題がなければ「確認済み・問題なし」と明記すること。

## レビュー担当の役割分担

| レビュアー | 主観点 |
|---|---|
| Codex | セキュリティ、エッジケース、テスト・解析コマンド実行、統合コメント |
| Antigravity | repo-wide 一貫性、命名 drift、パターン逸脱、docs/config/l10n drift（local policy で無効化可） |
| Claude | 変更意図との整合、ユーザー影響、必要時の統合判断 |
| structure-reviewer | 手続き化、責務配置、境界/IF劣化、振る舞いテスト不足 |

### author 別の構成

- **Codex authored PR** → Antigravity または Claude reviewer + independent local verification（Codex 自己レビューだけで完結しない）
- **Claude authored PR** → Codex verifier + Antigravity/Claude reviewer
- **Antigravity 由来 / 外部生成パッチ** → Codex verifier + Claude reviewer
- local policy で無効な agent は skip 理由を記録して代替する

### 実行ポリシー

- Antigravity は共有デフォルトでは `agy --print --sandbox` で走らせるが、無効化・sandbox・write 可否は local policy を優先する
- Antigravity が quota・capacity・空出力で失敗した場合は、ブラウザ認証で止めずに Codex scout / default subagent へフォールバックする。ただし **認証プロンプト（login 失敗）の場合は fallback せず停止し、ユーザーに認証修正を依頼する**（暗黙の engine 代替は設定不備を隠す）
- Codex は review 時に必要なコマンド（`test_command`, `analyze_command`）を実行して検証する
- Codex の固定ロール subagent がモデル非互換で失敗した場合は、同じ依頼を `agent_type` 未指定の default subagent で再実行する
- Codex が current orchestrator の場合は Codex が統合コメントを作り、ユーザー影響が大きい論点だけ Claude specialist へ渡す。Orchestrator は固定ではない


## External AI delegation policy gate

Multi-AI review は `~/.codex/config.toml` の `[auto_review].policy` に定義された **External AI delegation exception** を満たす場合に実行する。満たさない場合は、拒否条件を記録して Claude-only review + local verification + CI にフォールバックする。

許可条件の要点:

- trusted repository / git worktree 上で実行する
- 1 ticket / 1 PR 単位に限定する
- PR diff / local branch diff / 関連ソース / テスト出力など、レビューに必要な最小情報だけを渡す
- secret / `.env` / unrelated repo dump / home directory dump を渡さない
- Antigravity は共有デフォルトでは sandbox 付き scout。local policy で無効化・write 可否を上書き可。Codex verifier は reviewer config を使う
- policy deny 時に Guardian / sandbox / approval 設定を弱めない

## AI レビュー設定（プロジェクト CLAUDE.md 規約）

各プロジェクトの `CLAUDE.md` には以下のセクションを設けること。
AI レビューワークフロー実行時にこのセクションを読み取り、ソース収集・コマンド実行を動的に決定する。

```markdown
## AI レビュー設定

### Antigravity レビュー用ソース収集
- `source_dirs`: `src/ test/ docs/`
- `source_extensions`: `ts js json md`
- `source_exclude`: `*.min.js`

### Codex レビュー用コマンド
- `test_command`: `npm test`
- `analyze_command`: `npm run lint`
```

セクションがないプロジェクトでは、Claude がプロジェクト構造（`pubspec.yaml` / `package.json` / `go.mod` 等）を確認して適切に判断すること。

## PR & レビューワークフロー

- PR を作成する際は、必ずドラフト PR（`--draft`）を使用する
- AI アカウント（Gemini、Codex など）を GitHub コラボレーターやレビュアーとして追加しない
- AI コードレビューは PR コメントとしてシミュレートする（`gh pr comment` を使用）
- レビューツールが失敗した場合は、1回だけリトライしてそれでも失敗したらスキップして失敗を記録する
- レビュー後に追加修正・rebase・force-with-lease push をした場合は、再度 `@codex review` を依頼して最新 head に対する結果を確認する
- `gh pr checks` が `no checks reported` の場合だけ CI未設定/未報告として扱う。失敗・キャンセル・pending・認証/通信エラーはマージ不可として分離して記録する
- tmux / cmux セッション名にはプロジェクト名・PR番号・対象コマンドを含める

## GitHub CLI パーミッション

`gh pr review` など書き込み系コマンドを使う前に、そのコマンドが許可ツールリストにあるか確認する。
権限やフックでブロックされた場合は即座に `gh pr comment` または `gh api` にフォールバックする。
**権限でブロックされたコマンドを2回以上リトライしない。**

フォールバック順序: `gh pr review` → `gh pr comment` → `gh api repos/{owner}/{repo}/issues/{pr}/comments`

## E2E / ブラウザ自動操作レビュー

- **ブラウザ/UI E2E は Playwright を第一選択**とする
- API / Go E2E などブラウザ以外の E2E は各プロジェクト・言語別規約を優先する（例: `conventions/go/testing.md` の runn）
- Claude in Chrome / MCP は、ログイン済みセッションの単発読み取り確認など軽いケースに限定し、回帰・網羅・スクリーンショット証跡は Playwright を使う

## Multi-AI 多重レビュー

Architect / Reviewer ロールを組み合わせて実行し結果を統合する。標準構成は以下。

1. Codex reviewer / architect で security / validation
2. local policy が許す場合は Antigravity reviewer / architect で scout
3. Medium / High risk では structure-reviewer で Structure-Behavior drift を確認
4. 必要に応じて Claude reviewer / architect でユーザー影響・統合判断

### Structure-Behavior drift チェック

- handler / controller / usecase / service が orchestration を超えて core rule を抱えていないか
- data-only model、primitive obsession、hidden side effect、decision logic と IO の混在がないか
- consumer-oriented でない巨大 IF、boolean flag、infra DTO leakage がないか
- private method / call order ではなく、観測可能な振る舞い・状態遷移・エラー・境界値を守るテストがあるか

### 統合ルール
1. 同じファイル:行に対する指摘を統合（2AI以上 → 高信頼）
2. 1AIのみの指摘 → ソースコード実読で誤検出か確認
3. CRITICAL は無条件採用
4. 統合結果を `gh pr comment` で投稿
