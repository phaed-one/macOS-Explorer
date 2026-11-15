import { createHash } from 'node:crypto';

const site = 'https://phaed-one.github.io/macOS-Explorer/';
const branch = 'gh-pages';
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const json = body => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

// Keep old archives reachable: a client may have read an earlier signed feed.
export function updateSiteFiles(manifest, archive, appcast) {
  if (!/^Explorer-\d+\.\d+\.\d+-build\d+\.zip$/.test(manifest.asset)
      || manifest.feed_url !== `${site}appcast.xml`
      || manifest.download_url !== `${site}archives/${manifest.asset}`) {
    throw new Error('Unexpected update URLs or archive name; rebuild with the GitHub Pages configuration');
  }
  if (sha256(archive) !== manifest.sha256 || sha256(appcast) !== manifest.appcast_sha256) {
    throw new Error('Update site files differ from the signed release manifest');
  }
  // Git-backed Pages files must remain below GitHub's 100 MiB file limit.
  if (archive.length >= 100 * 1024 * 1024) throw new Error('Update archive exceeds the GitHub Pages source file limit');
  return new Map([
    [`archives/${manifest.asset}`, archive],
    ['appcast.xml', appcast],
    ['.nojekyll', Buffer.alloc(0)],
    ['index.html', Buffer.from('<!doctype html><html lang="en"><meta charset="utf-8"><title>Explorer Updates</title><h1>Explorer Updates</h1><p>Signed updates for <a href="https://github.com/phaed-one/macOS-Explorer">macOS Explorer</a>.</p><p><a href="appcast.xml">Update feed</a></p></html>\n')],
  ]);
}

export async function verifyUpdateSite(manifest) {
  // Redirects are errors: neither file should send app traffic to the release CDN.
  for (const [url, expected] of [[manifest.feed_url, manifest.appcast_sha256], [manifest.download_url, manifest.sha256]]) {
    const response = await fetch(url, {
      redirect: 'error', headers: { 'Cache-Control': 'no-cache' }, signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error(`Update hosting returned HTTP ${response.status}`);
    if (sha256(Buffer.from(await response.arrayBuffer())) !== expected) throw new Error('Update hosting has not served the packaged bytes yet');
  }
}

async function storeSiteFile(api, path, bytes, old) {
  const blobHash = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  if (path.startsWith('archives/') && old && old.sha !== blobHash) {
    throw new Error('An immutable update archive already exists with different bytes; increment the build number');
  }
  const blob = old?.sha === blobHash ? old : await api('git/blobs', json({ content: bytes.toString('base64'), encoding: 'base64' }));
  return { path, mode: '100644', type: 'blob', sha: blob.sha };
}

async function createSiteTree(api, previous, files) {
  const current = previous ? await api(`git/trees/${previous.tree.sha}?recursive=1`) : { tree: [] };
  if (current.truncated) throw new Error('Update site tree is too large to verify safely');
  const retained = current.tree.filter(entry => entry.type === 'blob' && !files.has(entry.path));
  const total = retained.reduce((sum, entry) => sum + entry.size, 0)
    + [...files.values()].reduce((sum, bytes) => sum + bytes.length, 0);
  if (total >= 950 * 1024 * 1024) throw new Error('Update site is approaching the 1 GB Pages limit; review archive retention before publishing');
  const tree = [];
  for (const [path, bytes] of files) {
    tree.push(await storeSiteFile(api, path, bytes, current.tree.find(entry => entry.path === path)));
  }
  return api('git/trees', json({ ...(previous ? { base_tree: previous.tree.sha } : {}), tree }));
}

async function waitForUpdateSite(manifest) {
  console.log('Waiting for GitHub Pages to serve the signed feed and ZIP directly…');
  let lastError;
  const deadline = Date.now() + 10 * 60 * 1000;
  while (Date.now() < deadline) {
    try {
      await verifyUpdateSite(manifest);
      console.log('Verified GitHub Pages update feed and ZIP checksums with redirects disabled');
      return;
    } catch (error) { lastError = error; }
    await new Promise(resolve => setTimeout(resolve, 10000));
  }
  throw new Error(`Update site verification failed; release publication stopped: ${lastError.message}`);
}

// Called only by the explicitly invoked release publisher, never by the app or builder.
export async function publishUpdateSite(api, manifest, archive, appcast) {
  const files = updateSiteFiles(manifest, archive, appcast);
  const pages = await api('pages', {}, true);
  if (pages && (pages.html_url !== site || pages.source?.branch !== branch || pages.source?.path !== '/')) {
    throw new Error('Existing Pages configuration differs from the Explorer update site; refusing to overwrite it');
  }
  const ref = await api(`git/ref/heads/${branch}`, {}, true);
  const previous = ref ? await api(`git/commits/${ref.object.sha}`) : null;
  const tree = await createSiteTree(api, previous, files);
  const commit = await api('git/commits', json({
    message: `Publish Explorer ${manifest.version}, build ${manifest.build} updates`,
    tree: tree.sha, parents: ref ? [ref.object.sha] : [],
  }));
  if (ref) {
    await api(`git/refs/heads/${branch}`, { ...json({ sha: commit.sha, force: false }), method: 'PATCH' });
  } else {
    await api('git/refs', json({ ref: `refs/heads/${branch}`, sha: commit.sha }));
  }
  if (!pages) await api('pages', json({ source: { branch, path: '/' }, build_type: 'legacy' }));
  await waitForUpdateSite(manifest);
}
