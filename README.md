# iSearch

A small keyboard launcher for macOS, in the spirit of Raycast, without the extras. Press ⌘Space to open the bar.

- Finds apps, project folders (Desktop, Documents and the top of the home folder), System Settings pages and entries, and any file in the home folder through Spotlight.
- Sends what you type to Claude: ⌘↵ opens a chat in the Claude app, ⌥↵ an incognito chat in the browser.
- ⇧↵ opens Claude Code in the selected folder, or shows a file in the Finder.
- Results you open often move up; the effect fades after about a month.

## Build

```bash
swift test                    # run the tests
scripts/build-app.sh          # build build/iSearch.app
scripts/build-app.sh --install  # replace /Applications/iSearch.app and start it
```

Requires macOS 14 or later and Swift 6.2.

## Layout

- `Sources/ISearchCore`: search logic without any interface (matching, ranking, scanning, Spotlight, Claude links), covered by `swift test`.
- `Sources/ISearchApp`: the menu bar app, the global hotkey and the panel.
