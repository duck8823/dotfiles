# Provider notes

## GitHub

- PR update API can update textual fields such as `body`, but image binary upload for Markdown attachments is not exposed as a public REST endpoint.
- GitHub Web UI supports attaching files to issues, PRs, discussions, comments, and Markdown files by drag-and-drop/paste/selecting files. The Web UI returns a user attachment URL that can be embedded in Markdown.
- Prefer `scripts/github-pr-attach-screenshot.mjs` for PR descriptions because it drives the supported Web UI behavior instead of relying on private upload endpoints.

Official references:
- https://docs.github.com/rest/pulls/pulls#update-a-pull-request
- https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files
- https://playwright.dev/docs/api/class-browsertype#browser-type-connect-over-cdp
- https://developer.chrome.com/blog/remote-debugging-port

## Confluence Cloud

- Confluence Cloud UI supports uploading files by dragging a file onto a page/doc, selecting the add image/file toolbar action, or using `/image`.
- Confluence Cloud v1 REST content attachment endpoints support multipart attachment upload under `/wiki/rest/api/content/{id}/child/attachment`.
- Displaying an uploaded image in page content uses Confluence storage markup such as `<ac:image><ri:attachment ri:filename="file.png" /></ac:image>` and requires a page body version update.
- The user needs page edit permission and add-attachment permission in the target space.

Official references:
- https://support.atlassian.com/confluence-cloud/docs/upload-a-file/
- https://developer.atlassian.com/cloud/confluence/rest/v1/api-group-content---attachments/
- https://developer.atlassian.com/cloud/confluence/rest/v2/api-group-page/
