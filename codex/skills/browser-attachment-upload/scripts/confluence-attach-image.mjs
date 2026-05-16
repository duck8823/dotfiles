#!/usr/bin/env node
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const DEFAULT_MARKER = '<!-- codex-attachment-upload -->';

function printHelp() {
  console.log(`Usage:
  node scripts/confluence-attach-image.mjs --page-id <id> --image <path> [--save] [--embed]

Uploads an image as a Confluence Cloud page attachment via REST API. With --embed,
appends an <ac:image> storage fragment to the page body after the upload.

Required:
  --page-id <id>           Confluence page ID
  --image <path>           PNG/JPEG/GIF/WebP file

Auth / site:
  --site <url>             Atlassian site base URL, e.g. https://example.atlassian.net
                           (env: ATLASSIAN_SITE)
  --email <email>          Atlassian account email (env: ATLASSIAN_EMAIL)
  --token-env <name>       Env var holding an Atlassian API token
                           (default: ATLASSIAN_API_TOKEN)

Options:
  --filename <name>        Attachment filename. Defaults to basename(image)
  --comment <text>         Attachment comment
  --alt <text>             Image alt text. Defaults to filename
  --embed                  Also update the page body to display the image
  --marker <html>          If present in storage body, insert image after this marker;
                           otherwise append at the end. Default: ${DEFAULT_MARKER}
  --version-message <text> Page update message for --embed
  --save                   Actually upload/update. Default is dry-run.
  --dry-run                Print the planned request and storage macro only

Examples:
  ATLASSIAN_SITE=https://example.atlassian.net \\
  ATLASSIAN_EMAIL=you@example.com \\
  ATLASSIAN_API_TOKEN=... \\
  node scripts/confluence-attach-image.mjs \\
    --page-id 123456789 \\
    --image /tmp/screenshot.png \\
    --embed \\
    --save
`);
}

function parseArgs(argv) {
  const args = {
    site: process.env.ATLASSIAN_SITE,
    email: process.env.ATLASSIAN_EMAIL,
    tokenEnv: 'ATLASSIAN_API_TOKEN',
    marker: DEFAULT_MARKER,
    save: false,
    embed: false,
    dryRun: undefined,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      i += 1;
      if (i >= argv.length) throw new Error(`${arg} requires a value`);
      return argv[i];
    };

    switch (arg) {
      case '--help':
      case '-h':
        printHelp();
        process.exit(0);
        break;
      case '--site':
        args.site = next();
        break;
      case '--email':
        args.email = next();
        break;
      case '--token-env':
        args.tokenEnv = next();
        break;
      case '--page-id':
        args.pageId = next();
        break;
      case '--image':
        args.image = next();
        break;
      case '--filename':
        args.filename = next();
        break;
      case '--comment':
        args.comment = next();
        break;
      case '--alt':
        args.alt = next();
        break;
      case '--embed':
        args.embed = true;
        break;
      case '--marker':
        args.marker = next();
        break;
      case '--version-message':
        args.versionMessage = next();
        break;
      case '--save':
        args.save = true;
        break;
      case '--dry-run':
        args.dryRun = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!args.pageId) throw new Error('--page-id is required');
  if (!args.image) throw new Error('--image is required');
  if (!existsSync(args.image)) throw new Error(`image not found: ${args.image}`);
  args.filename ??= path.basename(args.image);
  args.alt ??= args.filename;
  args.site = args.site?.replace(/\/+$/u, '');
  args.dryRun = args.dryRun ?? !args.save;
  return args;
}

function mimeType(fileName) {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  return 'image/png';
}

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function imageStorageMacro(filename, alt) {
  return `<p><ac:image ac:alt="${escapeXml(alt)}"><ri:attachment ri:filename="${escapeXml(filename)}" /></ac:image></p>`;
}

function authHeaders(args) {
  if (!args.site) throw new Error('--site or ATLASSIAN_SITE is required');
  if (!args.email) throw new Error('--email or ATLASSIAN_EMAIL is required');
  const token = process.env[args.tokenEnv];
  if (!token) throw new Error(`${args.tokenEnv} is required`);
  return {
    Authorization: `Basic ${Buffer.from(`${args.email}:${token}`).toString('base64')}`,
  };
}

async function readJson(response) {
  const text = await response.text();
  if (!text) return undefined;
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function safeErrorSummary(body) {
  if (!body || typeof body !== 'object') return '';
  const parts = [];
  for (const key of ['message', 'errorMessage', 'statusCode']) {
    if (typeof body[key] === 'string' || typeof body[key] === 'number') {
      parts.push(`${key}: ${body[key]}`);
    }
  }
  if (Array.isArray(body.errorMessages) && body.errorMessages.length > 0) {
    parts.push(`errorMessages: ${body.errorMessages.slice(0, 3).join('; ')}`);
  }
  if (Array.isArray(body.errors) && body.errors.length > 0) {
    parts.push(`errors: ${body.errors.slice(0, 3).join('; ')}`);
  }
  return parts.length > 0 ? `\n${parts.join('\n')}` : '';
}

async function confluenceFetch(args, urlPath, init = {}) {
  const headers = {
    Accept: 'application/json',
    ...authHeaders(args),
    ...(init.headers ?? {}),
  };
  const response = await fetch(`${args.site}${urlPath}`, { ...init, headers });
  const body = await readJson(response);
  if (!response.ok) {
    throw new Error(`${init.method ?? 'GET'} ${urlPath} failed: ${response.status} ${response.statusText}${safeErrorSummary(body)}`);
  }
  return body;
}

async function findAttachment(args, filename) {
  const data = await confluenceFetch(
    args,
    `/wiki/rest/api/content/${encodeURIComponent(args.pageId)}/child/attachment?filename=${encodeURIComponent(filename)}`,
  );
  return data?.results?.[0];
}

async function uploadAttachment(args) {
  const form = new FormData();
  const bytes = readFileSync(args.image);
  form.set('file', new Blob([bytes], { type: mimeType(args.filename) }), args.filename);
  if (args.comment) form.set('comment', args.comment);

  const urlPath = `/wiki/rest/api/content/${encodeURIComponent(args.pageId)}/child/attachment`;
  const headers = {
    ...authHeaders(args),
    Accept: 'application/json',
    'X-Atlassian-Token': 'no-check',
  };
  let response = await fetch(`${args.site}${urlPath}`, { method: 'POST', headers, body: form });
  let body = await readJson(response);
  if (response.ok) return body;

  const existing = await findAttachment(args, args.filename).catch(() => undefined);
  if (!existing?.id) {
    throw new Error(`POST ${urlPath} failed: ${response.status} ${response.statusText}${safeErrorSummary(body)}`);
  }

  const updatePath = `/wiki/rest/api/content/${encodeURIComponent(args.pageId)}/child/attachment/${encodeURIComponent(existing.id)}/data`;
  const updateForm = new FormData();
  updateForm.set('file', new Blob([bytes], { type: mimeType(args.filename) }), args.filename);
  if (args.comment) updateForm.set('comment', args.comment);
  response = await fetch(`${args.site}${updatePath}`, { method: 'POST', headers, body: updateForm });
  body = await readJson(response);
  if (!response.ok) {
    throw new Error(`POST ${updatePath} failed: ${response.status} ${response.statusText}${safeErrorSummary(body)}`);
  }
  return body;
}

async function embedImage(args, storageMacro) {
  const page = await confluenceFetch(
    args,
    `/wiki/rest/api/content/${encodeURIComponent(args.pageId)}?expand=body.storage,version,space`,
  );
  const current = page.body?.storage?.value ?? '';
  const nextValue = current.includes(args.marker)
    ? current.replace(args.marker, `${args.marker}${storageMacro}`)
    : `${current}${storageMacro}`;

  const payload = {
    id: page.id,
    type: page.type ?? 'page',
    title: page.title,
    space: page.space?.key ? { key: page.space.key } : undefined,
    body: { storage: { value: nextValue, representation: 'storage' } },
    version: {
      number: Number(page.version?.number ?? 1) + 1,
      minorEdit: true,
      message: args.versionMessage ?? `Attach ${args.filename}`,
    },
  };

  return confluenceFetch(args, `/wiki/rest/api/content/${encodeURIComponent(args.pageId)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
}

function printPlan(args, storageMacro) {
  console.log(JSON.stringify({
    dryRun: true,
    pageId: args.pageId,
    site: args.site ?? null,
    image: args.image,
    filename: args.filename,
    uploadEndpoint: `/wiki/rest/api/content/${args.pageId}/child/attachment`,
    embed: args.embed,
    storageMacro,
  }, null, 2));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const storageMacro = imageStorageMacro(args.filename, args.alt);

  if (args.dryRun) {
    printPlan(args, storageMacro);
    return;
  }

  const attachment = await uploadAttachment(args);
  const output = { attachment, storageMacro };
  if (args.embed) {
    output.page = await embedImage(args, storageMacro);
  }
  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error(`[confluence-attach-image] ERROR: ${error.stack || error.message}`);
  process.exit(1);
});
