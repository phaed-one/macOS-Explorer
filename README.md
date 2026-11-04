<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="macOS Explorer icon">
</p>

<h1 align="center">macOS Explorer</h1>

<p align="center">
  A Liquid Glass Finder replacement for macOS.
</p>

<!-- VIRUSTOTAL_BADGE_START -->
[![VirusTotal release scan](https://badges.cssnr.com/vt/sha/c7a9b88b9f3c07fff2e3ddf1adeaeeda2c7fa343d9c9e22e36639627d2b60e04?label=VirusTotal)](https://www.virustotal.com/gui/file/c7a9b88b9f3c07fff2e3ddf1adeaeeda2c7fa343d9c9e22e36639627d2b60e04)
<!-- VIRUSTOTAL_BADGE_END -->

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

## Install

Download the ZIP from the [latest release](https://github.com/phaed-one/macOS-Explorer/releases/latest),
unzip it, and move **Explorer.app** into **Applications**.

## Using Explorer

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

## Development

See the [development guide](docs/development.md) for building, testing, signing,
and publishing releases.
