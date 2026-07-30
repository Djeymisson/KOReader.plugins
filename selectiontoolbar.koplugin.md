# Selection Toolbar ![Version](https://img.shields.io/badge/version-v1.0.3-blue)

A KOReader plugin that replaces the centered text-selection menu with a compact toolbar displayed near the selected text.

## What it does

When selecting a passage with more than one word, the plugin intercepts the default highlight menu and shows a single row of icon buttons. The toolbar tries to appear below the selection when there is enough space; otherwise, it appears above it.

Available actions:

- Select
- Highlight
- Copy
- Add note
- Wikipedia
- Dictionary
- Translate
- View HTML
- Generate QR code
- Search

Native actions reuse the original `ReaderHighlight` callbacks, preserving KOReader's default behavior. The `Generate QR code` action uses the native `ui/widget/qrmessage` widget when it is available in the installed KOReader version.

## Configuration

In the reader, open:

`Top menu > Settings > Selection toolbar`

Options:

- `Use compact selection toolbar`: enables/disables replacement of the default menu.
- `Appearance`: controls the toolbar's visual presentation.
  - `Show toolbar shadow`: shows or removes the dithered shadow along the right and bottom edges.
- `Visible actions`: lets you choose which actions appear in the toolbar.
  - `Show all actions`: restores all actions.
  - Other items: enable/disable each toolbar action individually.
- `Version: v1.0.3`: shows the installed plugin version.

## Icons

Icons are stored in:

`selectiontoolbar.koplugin/icons/`

The current version loads icons directly from the plugin's own folder. There is no need to copy SVGs to internal KOReader directories or to KOReader's data directory.

Internally, the plugin applies a lightweight patch to `IconWidget` so it can accept direct `.svg`/`.png` file paths passed through the `icon` field. This patch only uses values explicitly defined in the widget, avoiding conflicts with other plugins that also use `IconWidget` or load icons through `file`.

## Organization and performance

The plugin includes a few internal adjustments to reduce repeated work when opening the toolbar:

- icon path caching;
- caching of the `ui/widget/qrmessage` module after the first check;
- cached dithered shadows, shared between toolbar openings of the same size;
- single read of the visible actions when building the toolbar;
- page offset calculation only once before iterating over the selection boxes;
- button metrics centralized in a shared function, including width, height, icon size, and side padding.

## Installation

Copy the `selectiontoolbar.koplugin` folder to KOReader's `plugins` folder:

```text
koreader/plugins/selectiontoolbar.koplugin
```

Then restart KOReader.

## Notes

- `View HTML` only appears when the original action exists for the current document, following KOReader's own rule.
- On very narrow screens, the toolbar remains compact, but it may take up a large portion of the available width if all 10 actions are enabled.
- The plugin is reversible: when disabling the `Use compact selection toolbar` option, the original menu is used again.
- When the plugin is closed, the patch applied to the highlight menu and to `IconWidget` is restored when it is still the active Selection Toolbar patch.
