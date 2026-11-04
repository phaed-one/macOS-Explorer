<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="macOS Explorer icon">
</p>

<h1 align="center">macOS Explorer</h1>

<p align="center">
  A Liquid Glass Finder replacement for macOS.
</p>

![macOS Explorer](docs/screenshot-2.webp)

Windows File Explorer's editable path bar, full-disk folder tree, combined with Finder's Spotlight search, Trash put-back and native look. Multi-tab and multi-window. Native AppKit with built-in updates. Requires macOS 14; Liquid Glass on macOS 26.

## What Finder doesn't have

- An editable path bar, always visible. Type absolute, relative or `~` paths, with folder suggestions as you type.
- A sidebar folder tree of the whole disk, starting at `/`, with every mounted drive. App bundles expand like folders.
- Hidden files shown for one folder only, or for all folders. `/` shows `/usr`, `/bin` and other hidden system folders out of the box.
- New empty files, from the toolbar or the right-click menu.
- Windows-style keys: F2 renames, Return opens.
- Right-drag to move files.
- Search that covers the current folder and its subfolders by default, using the Spotlight index.
- A permissions editor that takes octal (`755`) or chmod-style strings (`u+x,go-w`).
- Liquid Glass window on macOS 26, with opacity, frosting and tint settings, plus custom titlebar tint, accent color and window outline.

## Build

```sh
zsh scripts/setup-signing.sh # once on your Mac
zsh scripts/setup-updates.sh # once; preserves the update-signing key in Keychain
zsh scripts/build-app.sh
open dist/Explorer.app
```

Each successful build increments the patch version and build number in `Resources/Info.plist`
and creates `dist/Explorer-<version>.zip`. Older ZIPs are kept. Failed compilation or
packaging does not increment the version. To start a new minor or major release,
edit `CFBundleShortVersionString` before building.

To replace a build while keeping its app version, run
`zsh scripts/build-app.sh --same-version`. This increments only the build number
and creates `dist/Explorer-<version>-build<build>.zip`.
Use `zsh scripts/build-app.sh --version X.Y.Z` to build an explicitly chosen
release version. If that ZIP already exists locally, the new archive includes its
build number so the earlier build is preserved.

Local builds reuse the **Explorer Local Code Signing** certificate and private key
in your user Keychain. Keep that identity: replacing it changes the app's identity
and can reset macOS privacy permissions. The first update from an older ad-hoc
build requires granting Full Disk Access once more. Subsequent updates using the
same certificate retain a stable signing identity. This self-signed certificate is
for local use; public distribution still needs Apple Developer ID signing and
notarization for Gatekeeper trust.

In Explorer → Settings → Default File Manager, choose **Use Explorer as Default**
to send “Show in Finder” requests from other apps to Explorer. **Restore Finder**
switches back. Reopen other apps after changing this; a logout may be needed for
cached settings. macOS does not let any app take over opening folders, so folders
double-clicked on the desktop or in the Dock still open in Finder. Apps explicitly
targeting Finder and system Open/Save dialogs are unaffected.

To see protected folders, give Explorer Full Disk Access in System Settings → Privacy & Security.

Right-click a folder (in the tree or either content view), or empty space in a
folder, and choose **Open in Terminal**. With only Terminal installed, it opens
Terminal directly. With exactly one alternative installed, it opens that app
directly. Direct actions are named **Open in Terminal**, **Open in Warp**, etc.
With multiple alternatives, a submenu lists the installed apps,
including Terminal.

Supported terminals: **Terminal, iTerm2, Warp, Warp Preview, Ghostty, kitty,
Alacritty, WezTerm, Hyper, Tabby, Rio, Contour, Cool Retro Term, and cmux**.
Only installed applications are offered. The selected folder becomes the terminal's
working directory. File context menus do not include this action.

Explorer quietly checks for updates at launch. When one is available, an orange
dot appears on Settings. The Updates section at the top of Settings shows the new
version and an **Update** button. Sparkle downloads, verifies, replaces, and
relaunches the app through its standard installation flow. No update popups or
automatic downloads occur during the launch check. Offline failures appear only
in Settings, with a retry button.

Updates use [Sparkle 2.10.1](https://sparkle-project.org/), the app's only external
dependency. Both update archives and appcast feeds carry Ed25519 signatures;
the private key stays in the user's Keychain under account `local.pathfind.app`.
Keep that key as well as the local code-signing certificate for future releases.
The builder creates `dist/appcast.xml` and `dist/release.json` with every ZIP.
After committing and pushing a built version, publish it with
`node --env-file=.env scripts/publish-release.mjs`. This uploads the signed ZIP
and appcast, publishes the release, and replaces `/Applications/Explorer.app`
after stopping any running Explorer instance.

To regenerate the app icon (needs `rsvg-convert`): `zsh scripts/make-icon.sh`

## Tests

```sh
swift run PathfindChecks
zsh scripts/check-native.sh
```

## Not supported yet

- Connecting to network servers (mounted shares work)
- Finder tags

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Go to path bar | ⌘L |
| Back / forward | ⌘[ / ⌘] |
| Parent folder | ⌘↑ |
| Refresh | ⌘R |
| Open | Return |
| Rename | F2 |
| New folder | ⌘⇧N |
| Cut / copy / paste | ⌘X / ⌘C / ⌘V |
| Duplicate | ⌘D |
| Move to Trash | ⌘Delete |
| Get Info | ⌘I |
| Show hidden files | ⌘⇧. |
| New tab / close tab | ⌘T / ⌘W |
| Next tab | ⌃Tab |
| New window | ⌘N |
| Settings | ⌘, |
