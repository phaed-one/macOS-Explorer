<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="MacOS Explorer icon">
</p>

<h1 align="center">MacOS Explorer</h1>

<p align="center">
  A simple, fast file manager for macOS that fixes the things Finder gets wrong.
</p>

![MacOS Explorer browsing /Applications in icon view, with the folder tree open on the left](docs/screenshot.webp)

MacOS Explorer is a Finder replacement for people who want to see and control their files. You can type any path, browse the whole disk in one tree, see hidden files when you want them, and open as many tabs and windows as you need. It is a native AppKit app with no third-party dependencies, and it runs with your normal user permissions.

Requires macOS 14 or later. Building it requires Swift 6.

## Why not Finder?

| Finder | MacOS Explorer |
| --- | --- |
| No real path bar. You need ⌘⇧G and a dialog to type a path. | The path bar at the top is always editable. Type a path and press Return. |
| The sidebar shows shortcuts, not the disk. | A full folder tree from `/`, with every mounted drive, that expands as you go. |
| Hidden files are all or nothing (⌘⇧.). | Hidden files can be on by default, or turned on for one folder only. |
| Cut and paste works only through a menu trick (⌘⌥V). | Cut, Copy and Paste buttons and shortcuts that work as you'd expect. |
| No F2 to rename, and no "copy path" without extra steps. | F2 renames. Copy Path is in every item's menu. |
| View settings change in ways that are hard to predict. | Each folder remembers its own view, or follows a default you set. |
| Search starts on the whole Mac unless you change a setting. | Search covers the current folder and its subfolders. |
| `/usr`, `/bin` and other system folders are hard to reach. | The whole filesystem is in the tree, and `/` shows hidden folders out of the box. |

## Features

### Paths and navigation

- **Editable path bar.** Type an absolute path, a relative path, or a path starting with `~`, then press Return. ⌘L puts the cursor in the path bar.
- **Folder suggestions as you type.** A list of matching folders appears under the path bar. Use ↑ and ↓ to pick one, then Return or Tab to fill it in. Esc closes the list.
- **Breadcrumb buttons.** Each parent folder of the current location is a button under the toolbar. Click one to jump there.
- **History.** Back (⌘[), Forward (⌘]), parent folder (⌘↑) and Refresh (⌘R). Each tab keeps its own history.
- **Trash as a location.** Type `trash` in the path bar to open it.

### Folder tree

- **Favorites** sit at the top of the tree. Right-click any folder to add it. Right-click a favorite to remove it. The star in the toolbar adds or removes the folder selected in the file pane.
- **This Mac** shows the filesystem root and every mounted drive, including external disks and mounted network shares. The list updates when a drive is mounted or unmounted.
- **Folders load as you expand them**, so even `/` opens instantly. Use → and ← to expand and collapse with the keyboard.
- **Unmount** a drive from its right-click menu. This uses macOS's safe eject. The system disk never offers it.
- **Hide from Tree** removes a drive you don't need to see. Right-click **This Mac** and choose **Show All Filesystems** to bring hidden drives back. A hidden drive can still be opened by typing its path.
- App bundles and other packages can be expanded like folders, so you can look inside `Contents` without "Show Package Contents".

### Views and sorting

- **Icons view** with a size slider, and **Details view** with Name, Date, Kind and Size columns. Click a column header to sort by it.
- **Sort menu** with name, date, kind or size, ascending or descending, and an optional **Folders First**.
- **Natural sorting.** `file2` comes before `file10`.
- **Per-folder views.** Every folder remembers its own view and sort order. The **⋯** menu can make the current view the default for all folders, or set one folder back to the default.
- In Details view, a blue button above the column headers takes you to the parent folder.

### Hidden files

- The **eye** button sets whether hidden files show by default (⌘⇧.).
- The **eye with a folder badge** shows or hides hidden files in the current folder only, and remembers that choice. Right-click it to make that folder follow the default again.
- `/` shows hidden folders out of the box, so `/usr`, `/bin` and `/private` are easy to reach. You can change this like any other folder.
- The folder tree follows the same settings.

### Search

- The search field searches **the current folder and all its subfolders** by file name, using the Spotlight index. Nothing is scanned by hand, so results come back quickly even in large folders.
- Results stay live. Files that appear or disappear while you search are added to or removed from the list.
- Results follow your hidden-file setting and can be sorted like a normal folder.
- The status bar shows the number of results and whether Spotlight is still working. Folders that Spotlight is set to skip are not searched.

### Working with files

- **Toolbar buttons** for New Folder (⌘⇧N), New File, Cut (⌘X), Copy (⌘C), Paste (⌘V), Rename (F2) and Move to Trash (⌘Delete).
- **Open** files in their default app with Return or a double-click.
- **Duplicate** (⌘D) makes a copy next to the original with an unused name.
- **Copy Path** puts the full path of the selected items on the clipboard.
- **Get Info** (⌘I) shows details about an item. Folder sizes are counted in the background.
- **Permissions** lets you change POSIX permissions with checkboxes, an octal mode such as `755`, or a chmod expression such as `u+x`. It does not run a shell.
- **Reveal in Finder** for the times you need Finder.
- **Drag and drop.** A normal drag copies. A right-button drag moves. You can drop onto folders, onto tabs and into other windows.
- **Safe file operations.** Copies and moves run in the background. Existing files are never overwritten. If one item in a batch fails, the batch stops and tells you which one; items already copied stay where they are.
- **Move to Trash asks first.**
- **Live updates.** A folder refreshes by itself when its files change, including changes made by other apps.

### Trash

- **Trash** is the last item under This Mac. It combines the Trash folders from all connected drives in one list.
- **Restore** puts items back where they came from. It uses the location MacOS Explorer saved when it trashed them, or Finder's own "Put Back" record. If neither exists, it asks where to restore to. It never overwrites an existing file.
- **Clear Trash** asks for confirmation before it permanently deletes anything.

### Tabs and windows

- **Tabs** with close buttons and a **+** button. New tab is ⌘T, close tab is ⌘W, and ⌃Tab moves to the next tab.
- **Drag a tab** out of its window to make a new window. Drop it on another window's tab bar to move it there.
- **New Window** with ⌘N, or from the Dock menu.
- **Everything comes back after a restart:** open windows, their tabs and sizes, the expanded folders in each tree, the selection and the pane sizes.

### Appearance

- **Liquid Glass** window background on macOS 26, with an opacity slider (1–100%) and a **Frosting** slider that blends in a frosted backdrop. Earlier macOS versions use the standard blur.
- **Glass tint** color, with a button to go back to the system color.
- **Titlebar tint** with its own color, opacity and on/off switch.
- **Accent color** for button hover and selected rows. It starts from the titlebar tint and can be set on its own.
- **Window outline** that you can recolor or turn off.
- **Hover hints.** Hold the pointer over any toolbar button for a second to see what it does and its shortcut.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Go to path bar | ⌘L |
| Back / Forward | ⌘[ / ⌘] |
| Parent folder | ⌘↑ |
| Refresh | ⌘R |
| Open selection | Return |
| Rename | F2 |
| New folder | ⌘⇧N |
| Cut / Copy / Paste | ⌘X / ⌘C / ⌘V |
| Duplicate | ⌘D |
| Move to Trash | ⌘Delete |
| Get Info | ⌘I |
| Show hidden files | ⌘⇧. |
| New tab / Close tab | ⌘T / ⌘W |
| Next tab | ⌃Tab |
| New window | ⌘N |
| Settings | ⌘, |

## Install

Build the app and open it:

```sh
zsh scripts/build-app.sh
open dist/Explorer.app
```

Then drag `dist/Explorer.app` into `/Applications` if you want to keep it there.

The app runs with your user account's permissions. macOS protects some folders, including parts of the Trash. To browse those, turn on Explorer in **System Settings → Privacy & Security → Full Disk Access**. Settings has a button that opens that page. MacOS Explorer does not get around macOS permissions or System Integrity Protection.

The build is signed for local use only. It is not notarized for distribution.

### App icon

The icon is drawn in [Resources/AppIcon/make-svg.sh](Resources/AppIcon/make-svg.sh). To rebuild `Resources/AppIcon.icns`, run the script below and then build the app again. It needs `rsvg-convert` (`brew install librsvg`). Pass `glow` for the version with a colored glow.

```sh
zsh scripts/make-icon.sh
```

## Not in this version

- Connecting to network servers. Shares you have already mounted do appear.
- Finder tags.
- Very large folders load in one go rather than bit by bit.

## Development

Run the checks:

```sh
swift run PathfindChecks
zsh scripts/check-native.sh
```

The checks are a standalone Swift program, so they run with Apple's Command Line Tools and do not need Xcode.

The code is in two parts. `Sources/Pathfind` is the AppKit app: windows, tabs, the tree, the file views and settings. `Sources/PathfindCore` handles listing folders, sorting, resolving paths, history, Trash records and permissions. The app is not sandboxed. Its bundle identifier is unchanged from earlier builds, so saved windows, favorites and settings carry over.
# MacOS-Explorer
# MacOS-Explorer
