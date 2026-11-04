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
const body = `### Built-in updates

- Explorer checks quietly for updates each time it starts, without opening update dialogs or downloading updates automatically.
- A small orange dot on Settings indicates a new release.
- The Updates section at the top of Settings shows the available version. Click **Update** to download, verify, install, and relaunch through Sparkle's standard update flow.
- Manual checks and offline retry are available in Settings.
- Both the update feed and download are signed with Ed25519. Downloads are verified before extraction.

The updater is included starting in 0.1.4. Install this release manually once; future releases can be installed from Settings.

### Folder terminal actions

Right-click a folder in the tree, Details view, or Icons view, or empty space in the content pane. With no alternatives installed, **Open in Terminal** opens macOS Terminal. With one alternative, the action is named **Open in [app]** and opens it directly. With multiple alternatives, **Open in Terminal** has a native submenu chevron and lists the installed apps, including Terminal. File menus omit this action.

Supported terminal applications:
${terminals.map(terminal => `- ${terminal}`).join('\n')}

### Requirements and signing

macOS 14 or later; Liquid Glass requires macOS 26. Apple Silicon build.

The app keeps the same persistent self-signed identity as prior builds. It is not Apple Developer ID signed or notarized. Updates are independently authenticated by Sparkle's signed feed and archive.
`;
let release = await api(`releases/tags/${tag}`, {}, true);
if (release && !release.draft) throw new Error(`${tag} is already published; refusing to replace it without review`);
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
