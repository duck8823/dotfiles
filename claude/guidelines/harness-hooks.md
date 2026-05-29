# ハーネスフック挙動リファレンス

Claude Code の hook（`~/.claude/hooks/*.sh`）が何をブロック・警告し、どんな条件でスキップするかを記す。hook が永続的にブロック / 警告するときに、根本原因を理解せず `--no-verify` 等でバイパスしないために参照する。

Traceary / Gemini / Codex を含む横断 hook・observability 点検は
`conventions/ai/agent-hooks-observability.md` を参照する。

Claude lifecycle の失敗監査は `PostToolUseFailure` / `StopFailure` / `SubagentStop` /
`SessionEnd` を cmux に転送する。これらは監査用途で、重い判定や LLM 呼び出しは行わない。

## 検証スタンプ方式（push / ready ガード）

`record-verify-stamp.sh` (PostToolUse) と `check-verify-before-push.sh` (PreToolUse) で、analyze / test を通していない状態での push / ready を抑止する。

### スタンプファイル
- 保存先: `~/.cache/claude-code/verify-stamp-<repo_hash>`
- repo_hash: リポジトリの絶対パスを md5 した値（worktree ごとに別スタンプ）

### 記録条件（PostToolUse）
以下のコマンドが成功（`tool_response` に非0 exit / 行頭エラー / panic 等の失敗パターンなし）したとき、unix time を書き込む。

- `flutter analyze` / `flutter test`
- `go vet` / `go test`
- `npm test` / `npm run lint` / `npm run typecheck`
- `cargo test` / `cargo clippy`
- `pytest` / `python -m pytest` / `python3 -m pytest` / `uv run pytest`
- `ruff check`

### クリア条件
- `git commit` 実行時にスタンプを削除する（コミットを跨いだら再検証を要求）

### チェック対象（PreToolUse）
- 対象コマンド: `git push` / `gh pr ready`
- 対象プロジェクト: `pubspec.yaml` / `go.mod` / `package.json` / `Cargo.toml` / `pyproject.toml` のいずれかが存在
- スキップ条件: 直近の差分が `*.md` / `*.txt` のみ（`origin/<branch>..HEAD` で判定）

### ブロックではなく警告
- スタンプ未記録時は stderr に警告を出すのみで、コマンド自体は通す
- 「警告が出たから飛ばす」ではなく、**push / ready 前に検証コマンドを実行してから進む**のが正しい運用

### 想定される失敗パターン
- 失敗検出は `exit code <非0>` / `exit status <非0>` / 行頭 `FAILED` / 行頭 `ERROR` / 行頭 `error:` / TypeScript `error TSxxxx:` / `panic:` / 行頭 `Command failed` に限定する。`exit code 0` や `No errors` ではスタンプを落とさない。
- 新規ブランチ（`origin/<branch>` 未存在）はドキュメントのみでも常にチェック対象。初回 push 後は正しくスキップされる

## gh コマンドガード（`check-gh-commands.sh`）

PR / リリース系コマンドの先回り検出。**block（exit 2）は要件未充足を示し、要件を満たせば通る**。`--no-verify` 的な抜け道はない。

| コマンド | 挙動 |
|---|---|
| `gh pr create` で `--draft` / `-d` なし | block。ドラフト必須 |
| `gh pr create` で title/body に ticket 参照がない、または複数ある | block。`Closes #123` または `[PROJ-123]` を1つだけ明示 |
| `gh pr create --fill` | block。commit message 由来の未検証本文が混入するため、`--title` / `--body` / `--body-file` で ticket を明示 |
| `gh pr ready` 実行時に PR title/body の ticket 参照が 0 または複数 | block。ready 前に PR metadata を 1 ticket に直す |
| `gh pr merge` 実行時にレビューコメント不在 | block。`🤖 AI コードレビュー結果` を含む comment 必須 |
| 同上で `Gemini` / `Codex` の signature が PR コメントに無い | block。Multi-AI レビュー必須 |
| 同上で PR title/body の ticket 参照が 0 または複数 | block。1 PR = 1 ticket を満たすまで merge 不可 |
| `gh pr review` | warning（権限フックでブロックされ得るため `gh pr comment` 推奨） |
| `gh api ... collaborators` / reviewers 追加 | block。AI アカウントを collaborator にしない |
| `git tag` / `git push --tags` / `git push --follow-tags` / `gh release create` | block。タグ・リリースはユーザー承認後 |
| commit message に「レビュー指摘対応」「address review feedback」「fix review comments」等 | block。「何を・なぜ変えたか」で書き直す |
| `git commit` の staged changes が多数ファイル・多数関心事に広がる | warning。`DOTFILES_COMMIT_SPLIT_STRICT=true` の場合は block |

`gh pr comment && gh pr ready && gh pr merge` のような **コマンドチェーンは hook がチェーン全体に対して評価する**ため、要件未充足の merge が混じるとチェーン全部が block される。**必ず分離実行**する。

### 1 PR = 1 ticket / commit split の考え方

- ticket 参照は GitHub Issue なら `Closes #123`、Jira 等なら `[PROJ-123]` を使う
- 1 PR に複数 ticket が入った場合は、既存 PR を閉じるのではなく、対象 ticket に scope を戻し、残りは別 branch / 別 PR に分割する
- 1 ticket の中では複数コミット可。ただし各コミットは「何を・なぜ変えたか」が説明できる意味単位にする
- レビュー指摘で発生した変更は「レビュー対応」コミットにしない。既存コミットに fixup / amend するか、変更内容を表すメッセージにする
- hook の commit split 判定は機械的な過大 staged 変更の検出に留める。最終的な分割判断は `git diff --cached` を読んで行う

## Codex / Gemini worktree ガード（`check-codex-worktree.sh`）

`codex exec` または `gemini`（`--approval-mode plan` 以外 = write モード）を `main` / `master` ブランチで実行しようとすると block。

回避: `git worktree add .codex-work/<task> -b <branch>` を作ってから実行する。Claude サブエージェントは `isolation: worktree` 設定で自動的に隔離される。

## 権限チェック（`check-permissions.sh`）

セッション最初の `gh` コマンド実行時に `gh auth status` を確認し、認証エラーがあれば warning を出す。block ではない。

## 編集後の自動 lint / format

- `post-edit-lint.sh`: 編集後の linter 実行
- `post-write-format.sh`: 書き込み後の formatter 実行

これらは PostToolUse でプロジェクト固有の lint / format を呼び出す。失敗しても block にはならない（修正は後続のステップで行う）。

## Stop hook（`stop-self-review.sh`）

セッション停止時に未コミットの変更があると、stdout で「セルフレビューを検討してください」と通知する。block ではない。

## Stop hook（`stop-work-guard.sh`）

作業依頼に対し assistant がツールを一度も使わずに停止しようとした場合、**1 回だけ** `decision: block` で継続を促す。以下は素通り（block しない）:

- 壁打ち・質問・相談（疑問形や相談語を含む入力）
- 完了済み・ユーザー判断待ちでの停止（その旨を一言述べて再度停止すれば通る）
- 同一ユーザーターンでの 2 回目以降（最終ユーザー入力の uuid で turn を識別。無限ループしない）
- transcript 解析不能・例外時（fail-safe で素通り）

block されたら、作業が残っていれば継続する。意図的な停止（完了・壁打ち・要判断）なら、その旨を述べてから再度停止する。`stop_hook_active` は公式未記載のため依存せず、状態ファイル（session ごとの最終ターン uuid）でループを防いでいる。

## バイパスの禁止

- `--no-verify` / `git commit -n` で hook を回避しない。block の根本原因を解消する
- スタンプの強制生成は最終手段。検証コマンドの出力フィルタや lint 設定の見直しを優先する
- hook の挙動が誤っていると判断した場合は、`~/.claude/hooks/*.sh` のソースを読んでから dotfiles にプルリクを送る
