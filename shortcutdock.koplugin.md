# Shortcut Dock ![Version](https://img.shields.io/badge/version-v0.6.1-blue)

Shortcut Dock adds a floating, vertical shortcut bar to KOReader. It is designed for touch devices and can be assigned to any gesture supported by KOReader.

## Features

- Floating dock anchored near the lower-left or lower-right corner, without touching the screen edges.
- Compact icon buttons using the same scaled dimensions and standard `ButtonDialog` corner radius as Selection Toolbar.
- Unlimited configurable actions through KOReader's native Dispatcher action picker.
- Configurable button order.
- Optional automatic context visibility for native KOReader actions, with per-action manual overrides.
- Automatic pagination before the enabled buttons would overflow: the up arrow opens the next page and the down arrow returns to the previous page, without a scrollbar.
- An optional separate button above the dock moves it immediately between the left and right sides.
- Context-aware home button:
  - opens the previous document from the file browser;
  - returns to the file browser while reading;
  - resumes the parked reader when Bookshelf is open over it.
- The context-aware home button is fixed at the beginning of the action group and can be hidden in the plugin settings. Its icon changes between a home and an open document according to the current screen, including the Bookshelf overlay.
- Context-aware search button:
  - opens file search in the file browser;
  - opens full-text search while reading;
  - opens Bookshelf's library search while Bookshelf is in the foreground.
- The History action opens Bookshelf's Recent shelf while Bookshelf is in the foreground, and keeps KOReader's native history behavior in other contexts.
- Dynamic Wi-Fi icon reflecting the current Wi-Fi state whenever the dock is opened.
- Optional per-action custom icons with automatic fallback to KOReader icons.
- Two-letter action abbreviations when neither a custom nor a KOReader icon is available; hold the button to see its full name.

## Default buttons

From the bottom upward:

1. Fixed context button: open previous document / file browser / return from Bookshelf to the reader
2. Toggle Wi-Fi
3. Increase frontlight brightness
4. Decrease frontlight brightness
5. Search current context
6. History

Unavailable device actions, such as frontlight controls on devices without a frontlight, are automatically omitted by KOReader.

## Configuration

In the file browser or reader, open:

`Top menu > Tools > Shortcut Dock`

The settings follow the same grouped layout as the other plugins in this repository:

- `Show Shortcut Dock`: opens the dock immediately.
- `Appearance`: controls the dock position and its floating side control.
  - `Dock side`: selects `Left` or `Right`.
  - `Show side-switch button`: shows a separate chevron above the dock that changes its side without opening the settings.
- `Buttons`: controls the fixed and configurable dock buttons.
  - `Show fixed context button`: enables the first contextual button in the main group.
  - `Buttons and order`: opens KOReader's native action selector and shows the current number of configured actions.
  - `Automatic context visibility`: automatically separates native reader and file-browser actions.
  - `Visibility by context`: displays the automatic result and controls manual overrides for each action.
  - `Expected icon filenames`: lists the custom SVG and PNG names accepted for every action.
- `Gesture setup`: displays instructions for assigning the dock to a KOReader gesture.
- `Version: v0.6.1`: shows the installed plugin version.

The side selector and visibility options keep their menu open after a change, making it easier to review related settings.

## Gesture setup

1. Open **Settings > Taps and gestures > Gesture manager**.
2. Choose a gesture.
3. Select **Show Shortcut Dock** from the general actions.

The dock can also be opened from **Tools > Shortcut Dock > Show Shortcut Dock**.

## Configuring buttons

Open **Tools > Shortcut Dock > Buttons > Buttons and order**. KOReader's native action selector lets you add or remove actions and arrange their order. The first configured action is shown at the bottom of the dock, and subsequent actions grow upward.

Selecting **Nothing** removes every configurable action and remains effective when switching between the file browser and reader. The fixed context button may still be displayed independently when its visibility option is enabled.

Open **Tools > Shortcut Dock > Buttons > Visibility by context** to choose one of these options for each configured action:

- **Automatic**: uses the native-action classification when automatic visibility is enabled.
- **Everywhere**: displays the action in every supported screen; this is the default when automatic visibility is disabled.
- **Reader only**: displays the action only while a document is open.
- **File browser and Bookshelf only**: displays the action in the file browser and in Bookshelf, including when Bookshelf is covering a parked reader.

Enable **Tools > Shortcut Dock > Buttons > Automatic context visibility** to classify native KOReader actions automatically. Book map, Table of contents, Bookmarks, reading navigation, typography, and document-layout actions are treated as reader-only. File search, folder navigation, sorting, and file-browser display actions are treated as file-browser and Bookshelf only. General actions such as Wi-Fi, lighting, history, and power controls remain available everywhere.

Manual selections always override the automatic result. Unknown actions and actions registered by other plugins default to **Everywhere**. At the top of the visibility menu, **Use automatic visibility for all actions** clears manual overrides when automatic mode is enabled; with automatic mode disabled, the same command is shown as **Show all actions everywhere**.

The **Show side-switch button** and **Show fixed context button** options independently control the two fixed controls. Both are enabled by default.

Open **Tools > Shortcut Dock > Buttons > Expected icon filenames** to see the exact custom `.svg` and `.png` filenames for every dock action, including the fixed context button.

## Bookshelf compatibility

When the Bookshelf plugin is displayed over a parked reader, Shortcut Dock treats it as a separate context. The fixed button changes to the open-document icon and resumes the parked reader instead of sending another `Home` event. This prevents the button from closing Bookshelf while still showing the home icon.

While Bookshelf is in the foreground, **Search current context** opens its **Search library** dialog. If the reader is above a still-loaded Bookshelf screen, the same button opens the full-text search for the current document. The configured **History** action opens the first shelf whose source is **Recent** only while Bookshelf is in the foreground, including a renamed or customized Recent shelf. If either integration point is unavailable in the installed Bookshelf version, Shortcut Dock falls back to the corresponding native KOReader action.

The integration only uses Bookshelf modules that are already loaded. Bookshelf remains an optional plugin and is not loaded or required by Shortcut Dock.

## Custom icons

Put `.svg` or `.png` files in `shortcutdock.koplugin/icons/`. The plugin checks custom files before using KOReader's built-in icon.

Resolution order:

1. `icons/<dispatcher-action-id>.svg`
2. `icons/<dispatcher-action-id>.png`
3. `icons/<mapped-stock-icon>.svg`
4. `icons/<mapped-stock-icon>.png`
5. KOReader's built-in icon
6. A short abbreviation generated from the action name

Examples: `toggle_wifi.svg`, `history.svg`, `increase_frontlight.svg`, and `shortcutdock_context_search.svg`. The plugin already includes matching chevrons for pagination and changing the dock side, plus the dynamic home and document icons for the fixed context button.

For the fixed context button, `shortcutdock_context_home.svg` overrides the icon in every context. To keep its icon dynamic, use `home.svg` while reading and `book.opened.svg` in the file browser or when Bookshelf is covering a parked reader. In that Bookshelf state, the button resumes the reader instead of sending another Home command. The same names with a `.png` extension are also accepted.

## Saved settings

Shortcut Dock stores its preferences through KOReader's reader settings using these keys:

| Setting key | Purpose |
|---|---|
| `shortcutdock_actions` | Enabled actions and their order |
| `shortcutdock_action_contexts` | Per-action reader/browser visibility |
| `shortcutdock_auto_visibility` | Enables automatic context classification |
| `shortcutdock_side` | Left or right dock position |
| `shortcutdock_show_side_button` | Visibility of the floating side-switch button |
| `shortcutdock_show_context_button` | Visibility of the fixed contextual button |

## Installation

Extract `shortcutdock.koplugin` into KOReader's `plugins` directory and restart KOReader.

- Kindle: `/mnt/us/koreader/plugins/shortcutdock.koplugin`
- Kobo: `/mnt/onboard/.adds/koreader/plugins/shortcutdock.koplugin`
- Android: `<KOReader data directory>/plugins/shortcutdock.koplugin`

## Version

v0.6.1
