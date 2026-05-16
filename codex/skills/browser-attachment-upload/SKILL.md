---
name: browser-attachment-upload
description: Upload or embed screenshots/images into web products, especially GitHub PR descriptions/comments and Confluence Cloud pages. Use when Codex needs to attach local Playwright screenshots, generated images, or other image files to PRs, Jira/Confluence documentation, review evidence, or Markdown/ADF/storage-backed pages using a logged-in browser session, GitHub Web UI user-attachments, or Confluence REST attachments.
---

# Browser Attachment Upload

Use this skill to turn a local image file into an artifact embedded in a remote work item.
Prefer official APIs when they support attachments; otherwise drive the product Web UI with Playwright using a dedicated logged-in browser profile.

## Decision tree

1. **GitHub PR description / comment**: use `scripts/github-pr-attach-screenshot.mjs`.
   - GitHub REST can update PR body text, but does not provide a public image upload API for PR Markdown attachments.
   - The script uses GitHub Web UI drag-and-drop upload, waits for a `user-attachments` Markdown URL, then saves the PR body.
2. **Confluence Cloud page**: use `scripts/confluence-attach-image.mjs`.
   - Upload the image as a page attachment via Confluence REST.
   - With `--embed`, append an `<ac:image>` storage macro to the page body.
3. **Jira / Confluence via MCP**: if an MCP tool already accepts an attachment ID but does not upload the file, first upload with the Confluence script or product UI, then call the MCP tool with the returned ID/filename.
4. **Unknown editor**: use a dedicated Playwright profile and the product's drag/drop file upload control; do not pass secrets through page scripts or logs.

## GitHub PR images

Run with a dedicated profile so GitHub login survives between sessions:

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

If Chrome was intentionally started with a remote debugging port, attach to the existing logged-in browser:

```bash
node ~/.codex/skills/browser-attachment-upload/scripts/github-pr-attach-screenshot.mjs \
  --cdp http://127.0.0.1:9222 \
  --pr https://github.com/OWNER/REPO/pull/123 \
  --image /path/to/screenshot.png \
  --save
```

Rules:
- Default is dry-run. Pass `--save` to modify GitHub.
- Complete login and 2FA in the opened browser when `--login-wait` is used.
- Keep screenshots in `/tmp` or task-local directories; do not commit review-only screenshots unless the user explicitly wants repository artifacts.
- If GitHub DOM changes, inspect `/tmp/github-pr-attach-*.png` and `/tmp/github-pr-attach-*-buttons.json` produced by the script.

## Confluence Cloud images

Upload only:

```bash
ATLASSIAN_SITE=https://example.atlassian.net \
ATLASSIAN_EMAIL=you@example.com \
ATLASSIAN_API_TOKEN=... \
node ~/.codex/skills/browser-attachment-upload/scripts/confluence-attach-image.mjs \
  --page-id 123456789 \
  --image /path/to/screenshot.png \
  --save
```

Upload and embed at the end of the page body:

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

Rules:
- Use an env var for the API token; do not put the token in command arguments, PR descriptions, or logs.
- The script uses Confluence Cloud v1 content attachment endpoints because they support multipart page attachment upload.
- If a same-named attachment already exists, the script attempts to update the attachment data.
- `--embed` edits the page storage body and increments the page version. Avoid it on heavily edited pages unless the user accepts version-conflict risk.
- For Confluence docs that intentionally contain a marker, pass `--marker '<!-- codex-attachment-upload -->'` and keep that marker in the page body.

## Validation checklist

- Confirm the target URL/page/PR before `--save`.
- Run `node --check <script>` after editing bundled scripts.
- For GitHub, confirm the saved PR body visually or via `gh pr view --json body` when available.
- For Confluence, confirm the upload response contains an attachment and, if embedded, reopen the page or fetch page body after update.
- Record commands and whether the operation changed the remote artifact.

## References

Load `references/providers.md` when endpoint details, official docs, or troubleshooting notes are needed.
