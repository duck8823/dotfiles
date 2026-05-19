#!/usr/bin/env node
import { createRequire } from 'node:module';
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import process from 'node:process';

const require = createRequire(import.meta.url);

const DEFAULT_CHROME_EXECUTABLE =
  process.platform === 'darwin'
    ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    : undefined;
const DEFAULT_VIEWPORT = { width: 1440, height: 1100 };
const DEFAULT_MARKER = '## 動作確認スクリーンショット';
const USER_ATTACHMENT_PATTERN =
  /(?:https:\/\/github\.com\/user-attachments\/assets\/|https:\/\/user-images\.githubusercontent\.com\/|https:\/\/private-user-images\.githubusercontent\.com\/|https:\/\/user-attachments\.githubusercontent\.com\/)/u;
const ARTIFACT_DIR = mkdtempSync(path.join(tmpdir(), 'github-pr-attach-'));

function printHelp() {
  console.log(`Usage:
  node scripts/github-pr-attach-screenshot.mjs --pr <PR URL> --image <PNG path> [--save]

Updates a GitHub PR description by driving the GitHub Web UI with Playwright.
When --save is used, the image is uploaded by GitHub's textarea drag-and-drop
handler, so the PR body gets a normal GitHub user-attachment Markdown URL.
Dry-run never uploads the image or saves the PR body.

Required:
  --pr <url>               GitHub PR URL, e.g. https://github.com/org/repo/pull/123
  --image <path>           PNG/JPEG/GIF file to attach

Browser connection:
  --cdp <endpoint>         Attach to an already logged-in Chrome via CDP
                           (env: GITHUB_PR_CDP_ENDPOINT)
  --user-data-dir <dir>    Launch Chrome with this persistent profile dir
                           (env: GITHUB_PR_USER_DATA_DIR)
  --chrome-profile <name>  Chrome profile name inside --user-data-dir (default: Default)
  --chrome <path>          Chrome executable path
  --github-host <host>     Allowed GitHub host for --pr (default: github.com)
                           (env: GITHUB_PR_HOST)
  --login-wait            If GitHub login is required, wait up to 5 minutes

PR body update:
  --marker <heading>       Replace body content from this heading onward
                           (default: "${DEFAULT_MARKER}")
  --command <command>      Command shown under the screenshot regeneration details
  --save                   Actually click GitHub's save/update button
  --dry-run                Do not upload or save. Writes candidate body under a unique temp dir.
                           Default is dry-run unless --save is specified.

Examples:
  # Attach to an existing Chrome that was started with remote debugging.
  node scripts/github-pr-attach-screenshot.mjs \\
    --cdp http://127.0.0.1:9222 \\
    --pr https://github.com/OWNER/REPO/pull/123 \\
    --image /path/to/screenshot.png \\
    --save

  # Use a dedicated persistent profile. First run with --login-wait and log in once.
  node scripts/github-pr-attach-screenshot.mjs \\
    --user-data-dir /private/tmp/terra-ma-github-pr-profile \\
    --login-wait \\
    --pr https://github.com/OWNER/REPO/pull/123 \\
    --image /path/to/screenshot.png \\
    --save
`);
}

function parseArgs(argv) {
  const args = {
    cdp: process.env.GITHUB_PR_CDP_ENDPOINT,
    userDataDir: process.env.GITHUB_PR_USER_DATA_DIR,
    chromeProfile: process.env.GITHUB_PR_CHROME_PROFILE ?? 'Default',
    chrome: process.env.CHROME_EXECUTABLE ?? DEFAULT_CHROME_EXECUTABLE,
    githubHost: process.env.GITHUB_PR_HOST ?? 'github.com',
    marker: DEFAULT_MARKER,
    command: undefined,
    loginWait: false,
    save: false,
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
      case '--pr':
        args.pr = next();
        break;
      case '--image':
        args.image = next();
        break;
      case '--cdp':
        args.cdp = next();
        break;
      case '--user-data-dir':
        args.userDataDir = next();
        break;
      case '--chrome-profile':
        args.chromeProfile = next();
        break;
      case '--chrome':
        args.chrome = next();
        break;
      case '--github-host':
        args.githubHost = next();
        break;
      case '--marker':
        args.marker = next();
        break;
      case '--command':
        args.command = next();
        break;
      case '--login-wait':
        args.loginWait = true;
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

  if (!args.pr) throw new Error('--pr is required');
  args.pr = normalizePrUrl(args.pr, args.githubHost);
  if (!args.image) throw new Error('--image is required');
  if (!existsSync(args.image)) throw new Error(`image not found: ${args.image}`);
  if (!args.cdp && !args.userDataDir) {
    throw new Error('--cdp or --user-data-dir is required');
  }
  args.dryRun = args.dryRun ?? !args.save;
  return args;
}

function normalizePrUrl(value, githubHost) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`--pr must be a valid URL: ${value}`);
  }

  const expectedHost = String(githubHost || 'github.com').toLowerCase();
  const pathPattern = /^\/[^/]+\/[^/]+\/pull\/\d+\/?$/u;
  if (url.protocol !== 'https:' || url.hostname.toLowerCase() !== expectedHost || !pathPattern.test(url.pathname)) {
    throw new Error(
      `--pr must be an https://${expectedHost}/OWNER/REPO/pull/NUMBER URL. ` +
        'For GitHub Enterprise, pass --github-host <host> or set GITHUB_PR_HOST.',
    );
  }

  url.hash = '';
  url.search = '';
  url.pathname = url.pathname.replace(/\/$/u, '');
  return url.toString();
}

function loadPlaywright() {
  const candidates = [
    process.env.PLAYWRIGHT_CORE_REQUIRE,
    'playwright-core',
    'playwright',
    path.resolve(process.cwd(), 'node_modules/playwright-core'),
    path.resolve(process.cwd(), 'node_modules/playwright'),
    path.resolve(process.cwd(), 'e2e/node_modules/playwright-core'),
    path.resolve(process.cwd(), 'e2e/node_modules/playwright'),
    path.resolve(process.cwd(), 'scenario-scheduler-web-ui/node_modules/playwright-core'),
    path.resolve(process.cwd(), 'scenario-scheduler-web-ui/node_modules/playwright'),
  ].filter(Boolean);

  const errors = [];
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch (error) {
      errors.push(`${candidate}: ${error.message.split('\n')[0]}`);
    }
  }

  throw new Error(
    [
      'Playwright is not available.',
      'Install playwright-core in a local tools directory or set PLAYWRIGHT_CORE_REQUIRE.',
      'Example:',
      '  npm --prefix /private/tmp/terra-ma-playwright install playwright-core',
      '  PLAYWRIGHT_CORE_REQUIRE=/private/tmp/terra-ma-playwright/node_modules/playwright-core node scripts/github-pr-attach-screenshot.mjs ...',
      '',
      'Resolution attempts:',
      ...errors.map((line) => `  - ${line}`),
    ].join('\n'),
  );
}

function log(message) {
  console.log(`[github-pr-attach-screenshot] ${message}`);
}

async function clickFirstVisible(locator, description) {
  const count = await locator.count();
  for (let index = 0; index < count; index += 1) {
    const item = locator.nth(index);
    if (await item.isVisible().catch(() => false)) {
      await item.click();
      log(`clicked ${description} (${index + 1}/${count})`);
      return true;
    }
  }
  return false;
}

async function dumpDebug(page, name) {
  const screenshotPath = path.join(ARTIFACT_DIR, `${name}.png`);
  const buttonsPath = path.join(ARTIFACT_DIR, `${name}-buttons.json`);
  await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => {});
  const buttons = await page
    .locator('button, a[role="button"], summary')
    .evaluateAll((elements) =>
      elements.slice(0, 160).map((element, index) => ({
        index,
        tag: element.tagName,
        text: (element.innerText || '').trim().slice(0, 120),
        ariaLabel: element.getAttribute('aria-label'),
        title: element.getAttribute('title'),
        className: String(element.className || '').slice(0, 200),
      })),
    )
    .catch((error) => [{ error: error.message }]);
  writeFileSync(buttonsPath, JSON.stringify(buttons, null, 2));
  log(`debug artifacts: ${screenshotPath}, ${buttonsPath}`);
}

async function isTargetPrLoaded(page, prUrl) {
  return page.evaluate((targetUrl) => {
    const current = new URL(window.location.href);
    const target = new URL(targetUrl);
    const samePrPath = current.hostname === target.hostname && current.pathname === target.pathname;
    const hasPrBody = Boolean(
      document.querySelector('.js-comment, .timeline-comment, [data-testid="issue-body"]'),
    );
    return samePrPath && hasPrBody;
  }, prUrl).catch(() => false);
}

async function ensureSignedIn(page, args) {
  if (await isTargetPrLoaded(page, args.pr)) return;

  if (!args.loginWait) {
    await dumpDebug(page, 'github-pr-attach-login-required');
    throw new Error(
      'GitHub login or two-factor authentication is required. Re-run with --login-wait and complete authentication in the opened browser, or use a logged-in CDP session.',
    );
  }

  log('GitHub login/2FA is required. Waiting up to 5 minutes for the target PR page...');
  const deadline = Date.now() + 300_000;
  while (Date.now() < deadline) {
    if (await isTargetPrLoaded(page, args.pr)) return;

    const currentUrl = page.url();
    const onGitHubAuthFlow = /github\.com\/(login|session|sessions|settings\/two_factor|sessions\/two-factor|sessions\/verified-device)/u.test(currentUrl);
    if (!onGitHubAuthFlow && !currentUrl.startsWith(args.pr)) {
      await page.goto(args.pr, { waitUntil: 'domcontentloaded' }).catch(() => {});
    }
    await page.waitForTimeout(1_000);
  }

  await dumpDebug(page, 'github-pr-attach-login-timeout');
  throw new Error('timed out waiting for GitHub login/2FA to reach the target PR page');
}

function prDescriptionLocator(page) {
  return page.locator('[id^="pullrequest-"].js-comment').first();
}

async function openDescriptionEditor(page) {
  const description = prDescriptionLocator(page);
  await description.waitFor({ state: 'visible', timeout: 15_000 });

  const menuButton = description.locator('summary.timeline-comment-action').first();
  if (!(await clickFirstVisible(menuButton, 'PR description options menu'))) {
    await dumpDebug(page, 'github-pr-attach-description-menu-not-found');
    throw new Error('could not find the PR description options menu');
  }

  const editMenuItem = page.locator('button.js-comment-edit-button');
  await page.locator('button.js-comment-edit-button:visible').first().waitFor({ state: 'visible', timeout: 15_000 }).catch(() => {});
  if (!(await clickFirstVisible(editMenuItem, 'PR description edit menu item'))) {
    await dumpDebug(page, 'github-pr-attach-edit-not-found');
    throw new Error('could not find the PR description edit control');
  }
}

async function findBodyTextarea(page) {
  const description = prDescriptionLocator(page);
  const textarea = description.locator('form.js-comment-update textarea[name="pull_request[body]"]').first();
  await textarea.waitFor({ state: 'visible', timeout: 15_000 });
  return textarea;
}

function replaceFromMarker(body, marker, replacementPrefix) {
  const index = body.indexOf(marker);
  if (index < 0) return `${body.trimEnd()}\n\n${replacementPrefix}`;

  const before = body.slice(0, index).trimEnd();
  const afterMarker = body.slice(index + marker.length);
  const nextHeadingMatch = afterMarker.match(/\n#{1,6}\s/u);
  const tail = nextHeadingMatch ? afterMarker.slice(nextHeadingMatch.index) : '';
  return `${before}\n\n${replacementPrefix}${tail}`;
}

function mimeType(fileName) {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  return 'image/png';
}

function buildDryRunImageNotice(imagePath) {
  const fileName = path.basename(imagePath);
  return [
    `<!-- dry-run: ${fileName} would be uploaded by GitHub only when --save is used. -->`,
    '',
  ].join('\n');
}

function buildCommandDetails(command) {
  if (!command) return '';
  return [
    '',
    '<details>',
    '<summary>再生成コマンド</summary>',
    '',
    '```bash',
    command,
    '```',
    '',
    '</details>',
    '',
  ].join('\n');
}

async function dropImage(page, textarea, imagePath) {
  const data = readFileSync(imagePath).toString('base64');
  const fileName = path.basename(imagePath);
  const type = mimeType(fileName);

  const dataTransfer = await page.evaluateHandle(
    ({ base64, name, type }) => {
      const bytes = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
      const file = new File([bytes], name, { type });
      const transfer = new DataTransfer();
      transfer.items.add(file);
      return transfer;
    },
    { base64: data, name: fileName, type },
  );

  await textarea.dispatchEvent('drop', { dataTransfer });
  log(`dropped ${fileName} into GitHub markdown textarea`);
}

async function waitForUploadedMarkdown(page, beforeDropValue) {
  await page.waitForFunction(
    ({ patternSource, before }) => {
      const field = document.querySelector(
        'textarea[name="pull_request[body]"], textarea[name="issue[body]"], textarea[name="comment[body]"], textarea.js-comment-field, textarea[aria-label*="Comment" i]',
      );
      if (!field) return false;
      const value = field.value;
      return (
        value !== before &&
        new RegExp(patternSource, 'u').test(value) &&
        !/\[Uploading |Uploading /u.test(value)
      );
    },
    { patternSource: USER_ATTACHMENT_PATTERN.source, before: beforeDropValue },
    { timeout: 90_000 },
  );
}

async function saveEditor(page) {
  const description = prDescriptionLocator(page);
  const saveCandidates = [
    description.locator('form.js-comment-update button[type="submit"]').filter({ hasText: /Update comment|Save changes|Update pull request/i }).first(),
    description.locator('form.js-comment-update button').filter({ hasText: /Update comment|Save changes|Update pull request/i }).first(),
    page.getByRole('button', { name: /Update comment|Save changes|Update pull request/i }).first(),
  ];

  for (const candidate of saveCandidates) {
    if (await clickFirstVisible(candidate, 'save/update button')) return;
  }

  await dumpDebug(page, 'github-pr-attach-save-not-found');
  throw new Error('could not find the PR description save/update button');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { chromium } = loadPlaywright();

  let browser;
  let context;
  let page;
  let connectedOverCdp = false;
  if (args.cdp) {
    log(`connecting to logged-in browser: ${args.cdp}`);
    connectedOverCdp = true;
    browser = await chromium.connectOverCDP(args.cdp);
    context = browser.contexts()[0] ?? (await browser.newContext({ viewport: DEFAULT_VIEWPORT }));
  } else {
    if (!args.chrome || !existsSync(args.chrome)) {
      throw new Error(`Chrome executable not found. Pass --chrome <path>. Current: ${args.chrome ?? '(none)'}`);
    }
    log(`launching Chrome profile: ${args.userDataDir} (${args.chromeProfile})`);
    context = await chromium.launchPersistentContext(args.userDataDir, {
      executablePath: args.chrome,
      headless: false,
      viewport: DEFAULT_VIEWPORT,
      args: [`--profile-directory=${args.chromeProfile}`, '--disable-blink-features=AutomationControlled'],
    });
  }

  try {
    page = await context.newPage();
    page.setDefaultTimeout(15_000);
    log(`opening ${args.pr}`);
    await page.goto(args.pr, { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => {});
    await ensureSignedIn(page, args);
    await openDescriptionEditor(page);

    const textarea = await findBodyTextarea(page);
    const before = await textarea.inputValue();
    log(`PR body length before: ${before.length}`);

    const replacementPrefix = `${args.marker}\n\n`;
    const baseBody = replaceFromMarker(before, args.marker, replacementPrefix);
    const candidatePath = path.join(ARTIFACT_DIR, 'github-pr-description-candidate.md');
    const beforeSavePath = path.join(ARTIFACT_DIR, 'github-pr-description-before-save.png');

    if (args.dryRun) {
      const dryRunBody = `${baseBody.trimEnd()}\n\n${buildDryRunImageNotice(args.image)}${buildCommandDetails(args.command)}`;
      await textarea.fill(dryRunBody);
      writeFileSync(candidatePath, dryRunBody);
      await page.screenshot({ path: beforeSavePath, fullPage: false });
      log(`wrote ${candidatePath}`);
      log(`wrote ${beforeSavePath}`);
      log('dry-run: not uploading or saving. Pass --save to upload the image and update the PR description.');
      return;
    }

    await textarea.fill(baseBody);
    await textarea.focus();
    await page.keyboard.press(process.platform === 'darwin' ? 'Meta+End' : 'Control+End');
    const beforeDrop = await textarea.inputValue();
    await dropImage(page, textarea, args.image);
    await waitForUploadedMarkdown(page, beforeDrop);

    const uploadedBody = await textarea.inputValue();
    const nextBody = `${uploadedBody.trimEnd()}${buildCommandDetails(args.command)}`;
    await textarea.fill(nextBody);
    writeFileSync(candidatePath, nextBody);
    await page.screenshot({ path: beforeSavePath, fullPage: false });
    log(`wrote ${candidatePath}`);
    log(`wrote ${beforeSavePath}`);

    await saveEditor(page);
    await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => {});
    await page.waitForTimeout(1500);
    const savedPath = path.join(ARTIFACT_DIR, 'github-pr-description-saved.png');
    await page.screenshot({ path: savedPath, fullPage: false });
    log('saved PR description');
    log(`wrote ${savedPath}`);
  } finally {
    if (page) await page.close().catch(() => {});
    if (connectedOverCdp) browser?.disconnect();
    else if (browser) await browser.close();
    else await context.close();
  }
}

main().catch((error) => {
  console.error(`[github-pr-attach-screenshot] ERROR: ${error.stack || error.message}`);
  process.exit(1);
});
