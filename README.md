# KOReader Plugins

This repository contains custom plugins for [KOReader](https://koreader.rocks/).

Each plugin is kept in its own `.koplugin/` folder and has a dedicated documentation file in the repository root. This README is only a general entry point with common installation instructions and links to each plugin's documentation.

## Available plugins

| Plugin | Version | Folder | Documentation |
|---|---|---|---|
| Dictionary Preview | v1.1.4 | `dictionarypreview.koplugin/` | [dictionarypreview.koplugin.md](./dictionarypreview.koplugin.md) |
| Translator Preview | v1.0.2 | `translatorpreview.koplugin/` | [translatorpreview.koplugin.md](./translatorpreview.koplugin.md) |
| Lookup Preview | v1.0.22 | `lookuppreview.koplugin/` | [lookuppreview.koplugin.md](./lookuppreview.koplugin.md) |
| Reader Header Footer | v1.0.10 | `readerheaderfooter.koplugin/` | [readerheaderfooter.koplugin.md](./readerheaderfooter.koplugin.md) |
| Selection Toolbar | v1.0.6 | `selectiontoolbar.koplugin/` | [selectiontoolbar.koplugin.md](./selectiontoolbar.koplugin.md) |
| Quick Dock | v0.23.0 | `quickdock.koplugin/` | [quickdock.koplugin.md](./quickdock.koplugin.md) |
| Image Browser | v0.2.7 | `imagebrowser.koplugin/` | [imagebrowser.koplugin.md](./imagebrowser.koplugin.md) |
| Page Anchor | v1.7.3 | `pageanchor.koplugin/` | [pageanchor.koplugin.md](./pageanchor.koplugin.md) |
| Dictionary Explorer | v1.0.0 | `dictionaryexplorer.koplugin/` | [dictionaryexplorer.koplugin.md](./dictionaryexplorer.koplugin.md) |

Each `.koplugin/` folder contains the files required for KOReader to load the plugin, usually including at least:

```text
_meta.lua
main.lua
```

Some plugins may include additional folders, such as `modules/` or `icons/`. Check each plugin's README before installing or modifying its files.

## Installation

Each plugin version is distributed through a dedicated GitHub Release. The release asset contains the complete plugin folder compressed as a `.zip` file.

For example, the release **Dictionary Preview v1.1.1** includes this asset:

```text
dictionarypreview.koplugin-v1.1.1.zip
```

To install a plugin:

1. Open the GitHub Releases page for this repository.
2. Choose the release for the plugin and version you want to install.
3. Download the `.zip` asset for that release.
4. Extract the archive. It should contain the plugin folder, for example:

```text
dictionarypreview.koplugin/
```

5. Copy the extracted `.koplugin/` folder to KOReader's plugins directory.

Example:

```text
koreader/plugins/dictionarypreview.koplugin/
```

6. Restart KOReader.
7. Read the plugin-specific documentation to learn where to find it in the interface and how to configure it.

The repository source can still be cloned for development, but release assets are the recommended installation method for regular use.

## Updating

To update a plugin:

1. Close KOReader.
2. Replace the old `.koplugin/` folder with the new version.
3. Restart KOReader.

If the plugin stores internal preferences, those settings are usually kept by KOReader even after replacing the plugin files.

## Removing a plugin

To remove a plugin:

1. Close KOReader.
2. Delete the corresponding `.koplugin/` folder from KOReader's plugins directory.
3. Restart KOReader.

Example:

```text
koreader/plugins/plugin-name.koplugin/
```

Settings previously saved by KOReader may remain in internal storage, but they will no longer have any effect once the plugin is removed.

## Compatibility

These plugins are intended for recent KOReader versions and may depend on internal KOReader APIs. Since KOReader is actively developed, future updates may require plugin adjustments.

If a plugin stops loading after a KOReader update, check the plugin-specific README first, then inspect KOReader's logs.

## Development

When adding a new plugin to this repository, it is recommended to follow the same structure:

```text
new-plugin.koplugin/
├── _meta.lua
└── main.lua

new-plugin.koplugin.md
```

Tests, performance budgets and benchmarks live in [`tools/`](./tools/README.md), outside the plugin folders, so they are not part of a release.

### Documentation conventions

Every plugin's root-level `.md` file follows the same section order, so any
plugin's documentation reads the same way. Sections that don't apply to a
given plugin are simply omitted; plugin-specific sections (a feature deep
dive, a settings-key table, a "How it works" write-up) are inserted where
they fit, but the anchor sections below stay in this relative order:

1. `# <Display name> ![Version](https://img.shields.io/badge/version-vX.Y.Z-blue)` — the display name only, without a redundant "KOReader" prefix, and a version badge matching the `PLUGIN_VERSION`/`version` declared in the plugin's own source (not the release tag).
2. A short intro (1–3 paragraphs, no heading) explaining what the plugin does and why.
3. `## Features` — a scannable bullet list.
4. `## Installation` — the plugin's folder tree and the final path under `koreader/plugins/`.
5. Usage, configuration, and internals sections, in whatever order and depth the plugin needs.
6. `## Known limitations` — even a short one; omit only if there truly are none.
7. `## Uninstalling` — remove the folder, restart, note about leftover settings. Every plugin has this section.
8. `## Screenshots` — always the last content section.
9. `## Credits` — only when the plugin is based on, or borrows from, someone else's work.

Keep the version badge and any in-menu "Version: ..." string in sync with
the plugin's actual source; don't hardcode a version number in prose
elsewhere in the file, since it will go stale on the next release.

## License

Check the file headers and each plugin's dedicated documentation for license and credit information.
