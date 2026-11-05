#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = 'phaed-one/macOS-Explorer';
const token = process.env.GH_TOKEN;
if (!token) throw new Error('GH_TOKEN is missing. Run with node --env-file=.env scripts/publish-release.mjs');
const run = (command, args) => execFileSync(command, args, { cwd: root, encoding: 'utf8' }).trim();
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const manifest = JSON.parse(await readFile(path.join(root, 'dist/release.json'), 'utf8'));
const version = run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleShortVersionString', 'Resources/Info.plist']);
const build = run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleVersion', 'Resources/Info.plist']);
if (version !== manifest.version || build !== manifest.build) throw new Error('Source version differs from the packaged release');
if (run('git', ['status', '--porcelain'])) throw new Error('Commit and push the release changes before publishing');
const sha = run('git', ['rev-parse', 'HEAD']);
const remoteHead = run('git', ['ls-remote', 'origin', 'refs/heads/main']).split(/\s/)[0];
if (sha !== remoteHead) throw new Error('Push the release commit to origin/main before publishing');
const signer = path.join(root, '.build/artifacts/sparkle/Sparkle/bin/sign_update');
run(signer, ['--account', 'local.pathfind.app', '--verify', 'dist/appcast.xml']);
run('codesign', ['--verify', '--deep', '--strict', 'dist/Explorer.app']);
const [archive, appcast] = await Promise.all([
  readFile(path.join(root, 'dist', manifest.archive)), readFile(path.join(root, 'dist/appcast.xml'))
]);
if (sha256(archive) !== manifest.sha256 || sha256(appcast) !== manifest.appcast_sha256) throw new Error('Packaged release files changed after signing');

async function api(resource, options = {}, allowMissing = false) {
  const response = await fetch(resource.startsWith('https://') ? resource : `https://api.github.com/repos/${repo}/${resource}`, {
    ...options, headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2026-03-10', ...options.headers }
  });
  if (allowMissing && response.status === 404) return null;
  if (!response.ok) throw new Error(`GitHub request failed: HTTP ${response.status}`);
  return response.status === 204 ? null : response.json();
}
const tag = `v${version}`;
const source = await readFile(path.join(root, 'Sources/Pathfind/TerminalLauncher.swift'), 'utf8');
const terminals = [...source.matchAll(/case \.\w+: return "([^"]+)"/g)].map(match => match[1]);
if (terminals.length !== 14) throw new Error('Review the terminal catalog before publishing release notes');
const body = `### What’s new

- **Light and dark themes:** Choose Light or Dark in Settings → Theme. Explorer keeps its own look instead of following macOS.
- **Per-theme appearance:** Every Appearance setting, and the header color behind the toolbar and selected tab, is saved separately for light and dark.
- **Glass styles:** Pick Bright glass, Dark glass, Vivid blur, Soft blur or Smoke. Tinting is now optional, with its own switch.
- **Redesigned Settings:** A wide two-column window with Updates, Theme, Show in Finder and Appearance, all visible without scrolling.
- **Redesigned dialogs:** Full Disk Access setup puts each step next to its button. Permissions shows owner and group, a live \`rwxr-xr-x\` preview, and chmod input side by side.
- **Resize from any edge:** Every window edge and corner now resizes Explorer, with the matching cursor.
- **Drag the window by its tab strip:** Empty space beside the tabs moves the window.
- **Hide folders from This Mac:** Hide any folder in the tree with the eye icon on the This Mac header. Bring one back from the header's right-click menu, or all of them with the undo icon.
- **Drag tree folders into Favorites:** Drag a folder from This Mac onto Favorites, or between two favorites.
- Your home folder is now first in Favorites.
- The sidebar divider is a light hairline, the line under Favorites is gone, and the window outline is off by default.
- Path buttons are flat again, and the color picker's glass covers the whole panel.
- New app icon in dark glass that fits the macOS 26 icon shape.

### Updates

An orange dot on Settings tells you when a new version is available. Open Settings and click **Update** to install it and restart Explorer.

### Terminal support

Right-click a folder or empty space to open a terminal in that folder. Explorer offers your installed terminal apps:
${terminals.map(terminal => `- ${terminal}`).join('\n')}

### Requirements

macOS 14 or later; Liquid Glass requires macOS 26. Apple Silicon build.

Uses the same persistent self-signed identity as previous builds. Not Apple Developer ID signed or notarized.
`;

let release = await api(`releases/tags/${tag}`, {}, true);
if (release && !release.draft) {
  if (!process.argv.includes('--replace')) throw new Error(`${tag} is already published; use --replace only when replacing this release is explicitly authorized`);
  const latest = await api('releases/latest');
  if (release.id !== latest.id) throw new Error('Only the latest release can be replaced');
  await api(`git/refs/tags/${tag}`, {method: 'PATCH', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({sha, force: true})});
}
if (!release) release = await api('releases', { method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ tag_name: tag, target_commitish: sha, name: tag, body, draft: true, prerelease: false }) });
for (const [name, bytes, type] of [[manifest.asset, archive, 'application/zip'], ['appcast.xml', appcast, 'application/xml']]) {
  const existing = release.assets.find(asset => asset.name === name);
  if (existing) await api(`releases/assets/${existing.id}`, { method: 'DELETE' });
  const uploaded = await api(`${release.upload_url.replace(/\{.*$/, '')}?name=${encodeURIComponent(name)}`, {
    method: 'POST', headers: { 'Content-Type': type }, body: bytes
  });
  if (uploaded.size !== bytes.length || uploaded.digest !== `sha256:${sha256(bytes)}`) throw new Error(`${name} checksum mismatch; release left as draft`);
}
release = await api(`releases/${release.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ body, draft: false, make_latest: 'true' }) });
const latest = await api('releases/latest');
if (latest.id !== release.id || latest.body !== body || latest.assets.length < 2) throw new Error('Published release verification failed');
console.log(`Published ${release.html_url} with verified ZIP and signed appcast`);
execFileSync('/usr/bin/swift', ['scripts/install-app.swift'], { cwd: root, stdio: 'inherit' });
if (process.argv.includes('--replace')) {
  await api('actions/workflows/virustotal.yml/dispatches', {method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({ref: 'main', inputs: {tag}})});
  console.log('Started VirusTotal scan for the replacement build');
}
