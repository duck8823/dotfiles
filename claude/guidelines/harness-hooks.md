# ハーネスフック挙動リファレンス

Claude Code の hook（`~/.claude/hooks/*.sh`）が何をブロック・警告し、どんな条件でスキップするかを記す。hook が永続的にブロック / 警告するときに、根本原因を理解せず `--no-verify` 等でバイパスしないために参照する。

## 検証スタンプ方式（push / ready ガード）

`record-verify-stamp.sh` (PostToolUse) と `check-verify-before-push.sh` (PreToolUse) で、analyze / test を通していない状態での push / ready を抑止する。

### スタンプファイル
- 保存先: `~/.cache/claude-code/verify-stamp-<repo_hash>`
- repo_hash: リポジトリの絶対パスを md5 した値（worktree ごとに別スタンプ）

### 記録条件（PostToolUse）
以下のコマンドが成功（`tool_response` に `FAILED` / `Error` / `panic` 等のパターンなし）したとき、unix time を書き込む。

- `flutter analyze` / `flutter test`
- `go vet` / `go test`
- `npm test` / `npm run lint`

### クリア条件
- `git commit` 実行時にスタンプを削除する（コミットを跨いだら再検証を要求）

### チェック対象（PreToolUse）
- 対象コマンド: `git push` / `gh pr ready`
- 対象プロジェクト: `pubspec.yaml` / `go.mod` / `package.json` のいずれかが存在
- スキップ条件: 直近の差分が `*.md` / `*.txt` のみ（`origin/<branch>..HEAD` で判定）

### ブロックではなく警告
- スタンプ未記録時は stderr に警告を出すのみで、コマンド自体は通す
- 「警告が出たから飛ばす」ではなく、**push / ready 前に検証コマンドを実行してから進む**のが正しい運用

### 想定される失敗パターン
- 検証出力に `error:` / `Error:` / `FAILED` 等のキーワードが含まれていると成功でも `has_error=1` 判定でスタンプが立たない（パッケージが警告を「error」と表現するケース）。回避は出力フィルタか手動スタンプ生成（`date +%s > ~/.cache/claude-code/verify-stamp-<hash>`）
- 新規ブランチ（`origin/<branch>` 未存在）はドキュメントのみでも常にチェック対象。初回 push 後は正しくスキップされる

## gh コマンドガード（`check-gh-commands.sh`）

PR / リリース系コマンドの先回り検出。**block（exit 2）は要件未充足を示し、要件を満たせば通る**。`--no-verify` 的な抜け道はない。

| コマンド | 挙動 |
|---|---|
| `gh pr create` で `--draft` / `-d` なし | block。ドラフト必須 |
| `gh pr merge` 実行時にレビューコメント不在 | block。`🤖 AI コードレビュー結果` を含む comment 必須 |
| 同上で `Gemini` / `Codex` の signature が PR コメントに無い | block。Multi-AI レビュー必須 |
| `gh pr review` | warning（権限フックでブロックされ得るため `gh pr comment` 推奨） |
| `gh api ... collaborators` / reviewers 追加 | block。AI アカウントを collaborator にしない |
| `git tag` / `git push --tags` / `git push --follow-tags` / `gh release create` | block。タグ・リリースはユーザー承認後 |
| commit message に「レビュー指摘対応」等 | block。「何を・なぜ変えたか」で書き直す |

`gh pr comment && gh pr ready && gh pr merge` のような **コマンドチェーンは hook がチェーン全体に対して評価する**ため、要件未充足の merge が混じるとチェーン全部が block される。**必ず分離実行**する。

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

## バイパスの禁止

- `--no-verify` / `git commit -n` で hook を回避しない。block の根本原因を解消する
- スタンプの強制生成は最終手段。検証コマンドの出力フィルタや lint 設定の見直しを優先する
- hook の挙動が誤っていると判断した場合は、`~/.claude/hooks/*.sh` のソースを読んでから dotfiles にプルリクを送る
