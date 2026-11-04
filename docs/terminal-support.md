# Terminal integration

Folder and folder-background context menus offer these installed applications.
Zero alternatives opens Terminal directly. Exactly one alternative opens that app
directly, labelled `Open in <app>`. Multiple alternatives produce an
`Open in Terminal` submenu with the native chevron, including Terminal. File menus
omit this action.

Detection checks LaunchServices bundle identifiers and standard application
directories, including the user's Applications folder. The app list is refreshed
whenever the context menu is built. Each choice carries the directory and app
selected at that time.

| Application | Directory launch mechanism |
| --- | --- |
| Terminal | Open the directory URL in Terminal |
| iTerm2 | Open the directory URL in iTerm2 |
| Warp | `warp://action/new_window?path=...` |
| Warp Preview | `warppreview://action/new_window?path=...` |
| Ghostty | Open the directory URL in Ghostty |
| kitty | `--directory <path>` |
| Alacritty | `--working-directory <path>` |
| WezTerm | `start --cwd <path>` |
| Hyper | Open the directory URL in Hyper |
| Tabby | `open <path>` |
| Rio | `--working-dir <path>` |
| Contour | `terminal working-directory <path>` |
| Cool Retro Term | `--workdir <path>` |
| cmux | Open the directory URL in cmux |

Argument-based apps are launched as a new application instance, so an already
running instance cannot silently discard startup arguments. Paths are passed as
individual arguments, never shell commands. Warp query values are percent-encoded,
including literal plus signs.

The native checks cover the complete catalog, direct/submenu decisions, exact
app/directory payloads, special characters in paths, both content views, sidebar
folders, and omission from file and mixed-selection menus. Only installed apps
can be exercised on a given Mac; launch protocols for the other apps are checked
against their upstream documentation or source.

Launch references:

- [Warp URI scheme](https://docs.warp.dev/terminal/more-features/uri-scheme)
- [kitty command line](https://sw.kovidgoyal.net/kitty/invocation/)
- [Alacritty CLI](https://github.com/alacritty/alacritty/blob/master/alacritty/src/cli.rs)
- [WezTerm start](https://wezterm.org/cli/start.html)
- [Tabby CLI](https://github.com/Eugeny/tabby/blob/master/app/lib/cli.ts)
- [Rio CLI](https://github.com/raphamorim/rio/blob/main/frontends/rioterm/src/cli.rs)
- [Contour usage](https://github.com/contour-terminal/contour)
- [Cool Retro Term CLI](https://github.com/Swordfish90/cool-retro-term/blob/master/app/main.cpp)
- [cmux directory handling](https://github.com/manaflow-ai/cmux/blob/main/Sources/AppDelegate.swift)
