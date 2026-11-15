import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { publishUpdateSite, updateSiteFiles, verifyUpdateSite } from '../../scripts/publish-update-site.mjs';

const archive = Buffer.from('fixture signed archive');
const appcast = Buffer.from('fixture signed appcast');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const manifest = {
  version: '0.2.8', build: '45', asset: 'Explorer-0.2.8-build45.zip',
  feed_url: 'https://phaed-one.github.io/macOS-Explorer/appcast.xml',
  download_url: 'https://phaed-one.github.io/macOS-Explorer/archives/Explorer-0.2.8-build45.zip',
  sha256: digest(archive), appcast_sha256: digest(appcast),
};

test('site preparation preserves signed bytes and rejects inconsistent release inputs', () => {
  const files = updateSiteFiles(manifest, archive, appcast);
  assert.equal(files.get(`archives/${manifest.asset}`), archive);
  assert.equal(files.get('appcast.xml'), appcast);
  assert.throws(() => updateSiteFiles(manifest, Buffer.from('changed'), appcast), /differ/);
  assert.throws(() => updateSiteFiles({ ...manifest, download_url: 'https://github.com/download' }, archive, appcast), /Unexpected/);
  assert.throws(() => updateSiteFiles({ ...manifest, asset: '../file.zip' }, archive, appcast), /Unexpected/);
});

test('live hosting verification checks both responses and rejects redirects or stale bytes', async t => {
  let mode = 'valid';
  const requests = [];
  const server = createServer((request, response) => {
    requests.push({ method: request.method, url: request.url });
    if (mode === 'redirect') {
      response.writeHead(302, { Location: '/archive.zip' }); response.end(); return;
    }
    response.end(mode === 'stale' ? 'old bytes' : request.url === '/appcast.xml' ? appcast : archive);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const local = { ...manifest, feed_url: `${base}/appcast.xml`, download_url: `${base}/archive.zip` };
  await verifyUpdateSite(local);
  assert.deepEqual(requests, [{ method: 'GET', url: '/appcast.xml' }, { method: 'GET', url: '/archive.zip' }]);
  mode = 'stale';
  await assert.rejects(verifyUpdateSite(local), /packaged bytes/);
  mode = 'redirect';
  await assert.rejects(verifyUpdateSite(local), /fetch failed/);
});

function githubFixture(entries = [], pages = { html_url: 'https://phaed-one.github.io/macOS-Explorer/', source: { branch: 'gh-pages', path: '/' } }) {
  const calls = [];
  const api = async (resource, options = {}) => {
    const body = options.body ? JSON.parse(options.body) : undefined;
    calls.push({ resource, method: options.method ?? 'GET', body });
    if (resource === 'pages') return pages;
    if (resource === 'git/ref/heads/gh-pages') return { object: { sha: 'old-commit' } };
    if (resource === 'git/commits/old-commit') return { tree: { sha: 'old-tree' } };
    if (resource === 'git/trees/old-tree?recursive=1') return { tree: entries };
    if (resource === 'git/blobs' || resource === 'git/trees' || resource === 'git/commits') return { sha: resource };
    if (resource === 'git/refs/heads/gh-pages') return {};
    throw new Error(`Unexpected GitHub API call: ${resource}`);
  };
  return { api, calls };
}

test('publishing retains previous archives and verifies the exact hosted release', async t => {
  const fixture = githubFixture([{ type: 'blob', path: 'archives/previous.zip', sha: 'old-archive', size: 12 }]);
  const urls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    urls.push(url);
    assert.equal(options.redirect, 'error');
    return new Response(url === manifest.feed_url ? appcast : archive);
  });
  await publishUpdateSite(fixture.api, manifest, archive, appcast);
  const tree = fixture.calls.find(call => call.resource === 'git/trees').body;
  assert.equal(tree.base_tree, 'old-tree');
  assert.ok(tree.tree.some(entry => entry.path === `archives/${manifest.asset}`));
  assert.equal(fixture.calls.find(call => call.resource === 'git/refs/heads/gh-pages').body.force, false);
  assert.deepEqual(urls, [manifest.feed_url, manifest.download_url]);
});

test('publishing refuses archive replacement, unrelated Pages sites, and oversized sites before updating the branch', async () => {
  const immutable = githubFixture([{ type: 'blob', path: `archives/${manifest.asset}`, sha: 'different-archive', size: archive.length }]);
  await assert.rejects(publishUpdateSite(immutable.api, manifest, archive, appcast), /immutable/);
  assert.ok(!immutable.calls.some(call => call.resource === 'git/refs/heads/gh-pages'));
  const unrelated = githubFixture([], { html_url: 'https://example.com/', source: { branch: 'main', path: '/docs' } });
  await assert.rejects(publishUpdateSite(unrelated.api, manifest, archive, appcast), /refusing to overwrite/);
  const full = githubFixture([{ type: 'blob', path: 'archives/previous.zip', sha: 'old', size: 950 * 1024 * 1024 }]);
  await assert.rejects(publishUpdateSite(full.api, manifest, archive, appcast), /1 GB/);
  assert.ok(!full.calls.some(call => call.resource === 'git/blobs'));
});

test('first publication creates an orphan hosting branch and configures Pages only after the branch exists', async t => {
  const fixture = githubFixture();
  const api = async (resource, options = {}) => {
    if (resource === 'pages' && !options.method) return null;
    if (resource === 'git/ref/heads/gh-pages') return null;
    if (resource === 'git/refs') {
      fixture.calls.push({ resource, body: JSON.parse(options.body) }); return {};
    }
    return fixture.api(resource, options);
  };
  t.mock.method(globalThis, 'fetch', async url => new Response(url === manifest.feed_url ? appcast : archive));
  await publishUpdateSite(api, manifest, archive, appcast);
  assert.deepEqual(fixture.calls.find(call => call.resource === 'git/commits').body.parents, []);
  const branchIndex = fixture.calls.findIndex(call => call.resource === 'git/refs');
  const pagesIndex = fixture.calls.findIndex(call => call.resource === 'pages' && call.method === 'POST');
  assert.ok(branchIndex >= 0 && pagesIndex > branchIndex);
  assert.equal(fixture.calls[pagesIndex].body.source.branch, 'gh-pages');
});
