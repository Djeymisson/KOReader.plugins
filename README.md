# KOReader Plugins

This repository contains custom plugins for [KOReader](https://koreader.rocks/).

Each plugin is kept in its own `.koplugin/` folder and has a dedicated documentation file in the repository root. This README is only a general entry point with common installation instructions and links to each plugin's documentation.

## Available plugins

| Plugin | Version | Folder | Documentation |
|---|---|---|---|
| Plain UI Custom | v1.0.0 | `plainui-custom.koplugin/` | [plainui-custom.koplugin.md](./plainui-custom.koplugin.md) |
| Dictionary Preview | v1.1.1 | `dictionarypreview.koplugin/` | [dictionarypreview.koplugin.md](./dictionarypreview.koplugin.md) |
| Reader Header Footer | v1.0.1 | `readerheaderfooter.koplugin/` | [readerheaderfooter.koplugin.md](./readerheaderfooter.koplugin.md) |
| Selection Toolbar | v1.0.0 | `selectiontoolbar.koplugin/` | [selectiontoolbar.koplugin.md](./selectiontoolbar.koplugin.md) |

Each `.koplugin/` folder contains the files required for KOReader to load the plugin, usually including at least:

```text
_meta.lua
main.lua
```

Some plugins may include additional folders, such as `modules/` or `icons/`. Check each plugin's README before installing or modifying its files.

## Installation

1. Download or clone this repository.
2. Choose the plugin you want to install.
3. Copy the corresponding `.koplugin/` folder to KOReader's plugins directory.

Example:

```text
koreader/plugins/plugin-name.koplugin/
```

On some devices, especially Kindle, the path may look like this:

```text
/extensions/koreader/plugins/plugin-name.koplugin/
```

4. Restart KOReader.
5. Read the plugin-specific README to learn where to find it in the interface and how to configure it.

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

The root-level `.md` file should explain the plugin's purpose, installation steps, configuration options, and known limitations.

## License

Check the file headers and each plugin's dedicated documentation for license and credit information.
