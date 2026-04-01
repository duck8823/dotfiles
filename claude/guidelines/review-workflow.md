# レビューワークフロー

## コードレビュー指針

- PR レビュー時は、diff に実際に存在する内容のみ報告すること
- CI 状態、変更ファイル数、スコープを推測・捏造しないこと
- 実際の PR データから直接確認できることのみ記載すること
- レビュー対象が見つからない場合、ユーザーに聞く前に `git diff origin/main...HEAD` でブランチ差分を確認すること
- diff に存在しない変更点や問題点を報告しないこと

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
- Codex は review 時に必要なコマンド（`test_command`, `analyze_command`）を実行して検証する
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
- tmux / cmux セッション名にはプロジェクト名・PR番号・対象コマンドを含める

## GitHub CLI パーミッション

`gh pr review` など書き込み系コマンドを使う前に、そのコマンドが許可ツールリストにあるか確認する。
権限やフックでブロックされた場合は即座に `gh pr comment` または `gh api` にフォールバックする。
**権限でブロックされたコマンドを2回以上リトライしない。**

フォールバック順序: `gh pr review` → `gh pr comment` → `gh api repos/{owner}/{repo}/issues/{pr}/comments`

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
