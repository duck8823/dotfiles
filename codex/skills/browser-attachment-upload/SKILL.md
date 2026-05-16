---
name: browser-attachment-upload
description: GitHub PR description/comment や Confluence Cloud ページへ、ローカルの Playwright スクリーンショット・生成画像・画像ファイルをアップロード/埋め込みする。PRレビュー証跡、Jira/Confluenceドキュメント、Markdown/Confluence storage body に画像を貼る必要があるときに使う。ログイン済みブラウザ、GitHub Web UI user-attachments、Confluence REST attachments を安全に使い分ける。
---

# Browser Attachment Upload

ローカル画像をリモートの作業アイテムへ添付・埋め込みするためのスキル。公式APIで添付できる場合はAPIを優先し、APIがない場合は専用ログイン済みブラウザプロファイルをPlaywrightで操作する。

## 判断フロー

1. **GitHub PR description / comment**: `scripts/github-pr-attach-screenshot.mjs` を使う。
   - GitHub REST API は PR body の文字列更新はできるが、PR Markdown attachment の公開画像アップロードAPIはない。
   - スクリプトは GitHub Web UI の drag-and-drop 添付を使い、`user-attachments` Markdown URL の挿入を待ってからPR本文を保存する。
2. **Confluence Cloud page**: `scripts/confluence-attach-image.mjs` を使う。
   - Confluence REST でページ添付ファイルとしてアップロードする。
   - `--embed` を付けると `<ac:image>` storage macro をページ本文に追加する。
3. **Jira / Confluence via MCP**: MCPが attachment ID は受け取れるがアップロードできない場合、先にConfluenceスクリプトまたはWeb UIでアップロードし、返却されたID/ファイル名をMCPに渡す。
4. **未対応のWeb editor**: 専用Playwright profileで対象プロダクトのdrag/drop upload controlを操作する。secretをページスクリプト・ログ・PR本文に渡さない。

## GitHub PR 画像添付

GitHubログインを継続できるよう、専用profileで実行する。

```bash
PLAYWRIGHT_CORE_REQUIRE=/private/tmp/terra-ma-playwright/node_modules/playwright-core \
node ~/.codex/skills/browser-attachment-upload/scripts/github-pr-attach-screenshot.mjs \
  --user-data-dir /private/tmp/codex-github-upload-profile \
  --login-wait \
  --pr https://github.com/OWNER/REPO/pull/123 \
  --image /path/to/screenshot.png \
  --command 'npm run capture:screenshot' \
  --save
```

Chromeをremote debugging付きで起動している場合は、既存ログイン済みブラウザへattachできる。

```bash
node ~/.codex/skills/browser-attachment-upload/scripts/github-pr-attach-screenshot.mjs \
  --cdp http://127.0.0.1:9222 \
  --pr https://github.com/OWNER/REPO/pull/123 \
  --image /path/to/screenshot.png \
  --save
```

ルール:
- デフォルトはdry-run。GitHubを書き換えるときだけ `--save` を付ける。
- `--login-wait` 使用時は、開いたブラウザでログインと2FAを完了する。
- review-only screenshot は `/tmp` またはタスクローカルに置く。ユーザーが明示しない限りリポジトリに画像をcommitしない。
- GitHub DOM変更で壊れた場合は、スクリプトがログ出力する一意の一時ディレクトリ内の screenshot / buttons JSON を確認する。

## Confluence Cloud 画像添付

アップロードのみ:

```bash
ATLASSIAN_SITE=https://example.atlassian.net \
ATLASSIAN_EMAIL=you@example.com \
ATLASSIAN_API_TOKEN=... \
node ~/.codex/skills/browser-attachment-upload/scripts/confluence-attach-image.mjs \
  --page-id 123456789 \
  --image /path/to/screenshot.png \
  --save
```

アップロードしてページ末尾へ埋め込む:

```bash
ATLASSIAN_SITE=https://example.atlassian.net \
ATLASSIAN_EMAIL=you@example.com \
ATLASSIAN_API_TOKEN=... \
node ~/.codex/skills/browser-attachment-upload/scripts/confluence-attach-image.mjs \
  --page-id 123456789 \
  --image /path/to/screenshot.png \
  --embed \
  --version-message 'Attach dashboard screenshot' \
  --save
```

ルール:
- API token は環境変数で渡す。コマンド引数、PR本文、ログにtokenを書かない。
- Confluence Cloud v1 content attachment endpoint を使う。multipart page attachment upload に対応しているため。
- 同名attachmentが既にある場合、スクリプトはattachment data更新を試みる。
- `--embed` はページstorage bodyを編集してversionを進める。共同編集中ページではversion conflictリスクをユーザーに明示する。
- Confluence本文に挿入位置markerを置く場合は `--marker '<!-- codex-attachment-upload -->'` を使い、そのmarkerをページ本文に残す。

## 検証チェックリスト

- `--save` 前に対象PR URL / Confluence page IDを確認する。
- bundled scriptを編集したら `node --check <script>` を実行する。
- GitHubは保存後にPR本文を目視、または可能なら `gh pr view --json body` で確認する。
- Confluenceはupload responseにattachmentが含まれること、`--embed` 時はページ再取得または画面表示で画像を確認する。
- 実行コマンド、remote artifactを書き換えたか、残リスクを記録する。

## References

endpoint詳細、公式doc、troubleshootingが必要なら `references/providers.md` を読む。
