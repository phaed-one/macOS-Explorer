# Development

## Build

```sh
zsh scripts/setup-signing.sh # once on your Mac
zsh scripts/setup-updates.sh # once; preserves the update-signing key in Keychain
zsh scripts/build-app.sh
open dist/Explorer.app
```

Each successful build increments the patch version and build number in
`Resources/Info.plist` and creates `dist/Explorer-<version>.zip`. Older ZIPs are
kept. Failed compilation or packaging does not increment the version. To start a
new minor or major release, edit `CFBundleShortVersionString` before building.

To replace a build while keeping its app version, run
`zsh scripts/build-app.sh --same-version`. This increments only the build number
and creates `dist/Explorer-<version>-build<build>.zip`.
Use `zsh scripts/build-app.sh --version X.Y.Z` to build an explicitly chosen
release version. If that ZIP already exists locally, the new archive includes its
build number so the earlier build is preserved.

## Signing

Local builds reuse the **Explorer Local Code Signing** certificate and private key
in your user Keychain. Keep that identity: replacing it changes the app's identity
and can reset macOS privacy permissions. The first update from an older ad-hoc
build requires granting Full Disk Access once more. Subsequent updates using the
same certificate retain a stable signing identity. This self-signed certificate is
for local use; public distribution needs Apple Developer ID signing and
notarization for Gatekeeper trust.

Updates use [Sparkle 2.10.1](https://sparkle-project.org/), the app's only external
dependency. Both update archives and appcast feeds carry Ed25519 signatures.
The private update-signing key stays in Keychain under account
`local.pathfind.app`. Preserve it alongside the code-signing certificate.

## Publish

The builder creates `dist/appcast.xml` and `dist/release.json` with every ZIP.
After committing and pushing a built version, publish it with:

```sh
node --env-file=.env scripts/publish-release.mjs
```

This uploads the signed ZIP and appcast, publishes the release, and replaces
`/Applications/Explorer.app` after stopping any running Explorer instance.
`GH_TOKEN` is used only by the publishing tool; it is never included in the app.

Starting with Explorer 0.2.8, the publisher also maintains the `gh-pages`
branch and configures GitHub Pages to serve that branch's root. It uploads the
exact signed feed and ZIP there before publishing the GitHub Release or
installing the app. `GH_TOKEN` therefore needs repository Contents and Pages
write permissions. An existing Pages site with a different URL or publishing
source is rejected rather than overwritten. The publisher uses GitHub's Git
and Pages APIs; no hosting credentials are added to Explorer.

The app uses `https://phaed-one.github.io/macOS-Explorer/appcast.xml` and archives
under `archives/Explorer-<version>-build<build>.zip`. Local build archive names
remain as described above. Per-build hosting names are immutable; older archives
remain accessible for clients that already fetched an earlier feed. Publishing
stops before the site reaches 950 MiB or an archive reaches 100 MiB, so retention
or hosting can be reviewed without silently deleting an active update URL.

Before completing publication, the publisher waits about ten minutes for Pages
and compares the feed and archive SHA256 hashes with redirects disabled. A failed
hosting check stops publication and local installation. It leaves any uploaded
release assets and Pages commit available for inspection/retry. A new release
remains a draft; an explicitly replaced release was already public. Older apps
continue using the signed GitHub Release feed to discover the migration build.
No Pages changes occur during a local build or test run.

When the user explicitly requests replacing the latest release, build with
`--same-version`, commit and push, then publish with `--replace`. This replaces
the latest release's ZIP and signed feed, moves its source tag to the replacement
commit, installs the matching build, and starts a fresh VirusTotal scan.

## Release scans

`.github/workflows/virustotal.yml` scans the published Explorer ZIP on each new
release. It verifies GitHub's SHA256 digest before submitting, adds report links
to the release notes, waits for the analysis to finish, and updates the README
badge only when the scanned release is still the latest one. The signed appcast
is not submitted as an executable asset.

The workflow uses the repository Actions secret `VT_API_KEY` and its built-in
`GITHUB_TOKEN` with `contents: write`. It never receives the local publishing PAT
or either private signing key. Third-party actions are pinned to commit hashes.
To scan a release again, run **VirusTotal release scan** from GitHub Actions and
enter its tag, or `latest`.

## Tests

Full Disk Access onboarding tests effective access with public directory operations
on protected folders, without reading file contents or TCC databases. macOS has no
public API for the Full Disk Access switch. A privacy denial opens the startup
window; successful access closes it and refreshes open folders. Missing probe
directories and ordinary UNIX permission errors remain unknown rather than
triggering a false warning. Some grants require macOS's Quit & Reopen action.

```sh
swift run PathfindChecks
zsh scripts/check-native.sh
node --test Tests/ReleaseChecks/*.test.mjs
```

To exercise a real network mount, run the native checks with
`PATHFIND_TEST_SERVER` set to a test-share URL. The share must contain
`Explorer-Network-QA.txt`. The check mounts it through NetFS, verifies the file
listing, and disconnects it afterward. Only use a disposable test share.

To regenerate the app icon (needs `rsvg-convert`): `zsh scripts/make-icon.sh`.
