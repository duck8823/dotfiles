# レビューワークフロー

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
| Gemini | repo-wide 一貫性、命名 drift、パターン逸脱、docs/config/l10n drift |
| Codex | セキュリティ、エッジケース、テスト・解析コマンド実行 |
| Claude | 変更意図との整合、ユーザー影響、最終マージ可否 |

### author 別の構成

- **Claude authored PR** → Gemini + Codex + Claude final
- **Codex authored PR** → Gemini + Claude reviewer + Claude final
- **Gemini 由来 / 外部生成パッチ** → Codex + Claude reviewer + Claude final

### 実行ポリシー

- Gemini は原則 `--approval-mode plan` の read-only で走らせる
- Gemini が認証プロンプト・quota・空出力で失敗した場合は、ブラウザ認証で止めずに Codex scout / default subagent へフォールバックする
- Codex は review 時に必要なコマンド（`test_command`, `analyze_command`）を実行して検証する
- Codex の固定ロール subagent がモデル非互換で失敗した場合は、同じ依頼を `agent_type` 未指定の default subagent で再実行する
- Claude は残った論点を統合し、PR の意図とユーザー価値で最終判断する

## AI レビュー設定（プロジェクト CLAUDE.md 規約）

各プロジェクトの `CLAUDE.md` には以下のセクションを設けること。
AI レビューワークフロー実行時にこのセクションを読み取り、ソース収集・コマンド実行を動的に決定する。

```markdown
## AI レビュー設定

### Gemini レビュー用ソース収集
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

1. Gemini reviewer / architect で read-only scout
2. Codex reviewer / architect で security / validation
3. Claude reviewer / architect で実読・統合

### 統合ルール
1. 同じファイル:行に対する指摘を統合（2AI以上 → 高信頼）
2. 1AIのみの指摘 → ソースコード実読で誤検出か確認
3. CRITICAL は無条件採用
4. 統合結果を `gh pr comment` で投稿
