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

```sh
swift run PathfindChecks
zsh scripts/check-native.sh
```

To regenerate the app icon (needs `rsvg-convert`): `zsh scripts/make-icon.sh`.
