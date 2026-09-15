# Shortcut Dock ![Version](https://img.shields.io/badge/version-v0.19.1-blue)

Shortcut Dock adds a floating, vertical shortcut bar to KOReader. It is designed for touch devices and can be assigned to any gesture supported by KOReader.

## Features

- Floating dock anchored near the lower-left or lower-right corner, without touching the screen edges.
- Fixed placement while open: dragging over the dock does not move it away from its selected side.
- Optional keep-open behavior for inline actions. The dock safely closes for dispatch and reopens only when the action did not open another dialog or change context.
- Gesture-following position enabled by default, opening the dock on the same half of the screen where the assigned gesture started.
- Compact icon buttons using the same scaled dimensions and standard `ButtonDialog` corner radius as Selection Toolbar.
- Three selectable dock scales: Small keeps the original dimensions, Medium increases them by 20%, and Large by 40%.
- Unlimited configurable actions through KOReader's native Dispatcher action picker.
- Configurable button order.
- Optional automatic context visibility for native KOReader actions, with per-action manual overrides.
- Automatic pagination before the enabled buttons would overflow: the up arrow opens the next page and the down arrow returns to the previous page, without a scrollbar.
- An optional separate button above the dock moves it immediately between the left and right sides.
- Optional vertical frontlight slider in a separate column beside the action buttons, with a circular thumb, live brightness adjustment, and a dedicated frontlight toggle button.
- Optional second lighting column for frontlight warmth on supported devices, using each device's native warmth range.
- Optional reading-information panel on the screen edge opposite the dock, enabled by default, with an optional book cover, book and chapter progress, estimated time remaining, today's reading, clock, and battery status.
- Night mode, Wi-Fi, and full-screen refresh execute in place when keep-open behavior is enabled, without destroying and rebuilding the dock.
- Wi-Fi progress appears in a compact opposite-edge status panel instead of KOReader's informational popups during inline toggles.
- Context-aware home button:
  - opens the previous document from the file browser;
  - returns to the file browser while reading;
  - resumes the parked reader when Bookshelf is open over it.
- The context-aware home button is fixed at the beginning of the action group on the first pagination page and can be hidden in the plugin settings. It is not repeated on later pages. Its icon changes between a home and an open document according to the current screen, including the Bookshelf overlay.
- Context-aware search button:
  - opens file search in the file browser;
  - opens full-text search while reading;
  - opens Bookshelf's library search while Bookshelf is in the foreground.
- The History action opens Bookshelf's Recent shelf while Bookshelf is in the foreground, and keeps KOReader's native history behavior in other contexts.
- Interactive night-mode button using `day_mode.svg` or `night_mode.svg` according to the active display mode.
- Interactive Wi-Fi button using `wifi_on.svg` or `wifi_off.svg` according to the radio state.
- Night mode and Wi-Fi use KOReader's native Dispatcher actions. The dock closes before dispatch so the event reaches the active KOReader screen, and the state-specific icon is refreshed the next time the dock opens without background polling.
- Optional per-action custom icons with automatic fallback to KOReader icons.
- Two-letter action abbreviations when neither a custom nor a KOReader icon is available; hold the button to see its full name.

## Default buttons

From the bottom upward:

1. Fixed context button: open previous document / file browser / return from Bookshelf to the reader
2. Toggle Wi-Fi
3. Toggle night mode
4. Search current context
5. History

Brightness is controlled by the dedicated slider, so incremental brightness buttons are no longer part of the initial configuration. They remain available in KOReader's native action selector for users who prefer them. Unavailable device actions are automatically omitted by KOReader.

## Configuration

In the file browser or reader, open:

`Top menu > Tools > Shortcut Dock`

The settings follow the same grouped layout as the other plugins in this repository:

- `Show Shortcut Dock`: opens the dock immediately.
- `Behavior`: controls where the dock opens and what happens after an action.
  - `Dock side: <current side>`: selects `Left`, `Right`, or `Follow gesture side`. Following the gesture is enabled by default, and the configured fixed side is used as a fallback when the dock is opened without gesture coordinates.
  - `Keep dock open after actions`: enabled by default; keeps the same dock open for night mode, Wi-Fi, and full refresh, reopens it after other compatible actions, and leaves it closed when an action opens another screen or dialog.
- `Actions and buttons`: controls configurable actions, fixed buttons, and context visibility.
  - `Buttons and order`: opens KOReader's native action selector and shows the current number of configured actions.
  - `Fixed buttons`:
    - `Show fixed context button`: enables the first contextual button in the main group.
    - `Show side-switch button`: shows a separate chevron above the dock that changes its side without opening the settings.
  - `Context visibility`:
    - `Automatic visibility`: automatically separates native reader and file-browser actions.
    - `Per-action visibility`: displays the automatic result and controls manual overrides for each action.
- `Appearance`: controls scale, visible panels and columns, and icon customization.
  - `Dock size: <current size>`: selects `Small`, `Medium`, or `Large`. The selected scale applies to the buttons, icons, chevrons, lighting columns, information panel, and pagination calculation.
  - `Reading information panel`:
    - `Show panel`: shows or hides the Mini Receipt-inspired information block.
    - `Show book cover at the top`: shows or hides the open document's cover above the reading information.
  - `Lighting controls`:
    - `Show frontlight control`: shows or hides the brightness slider and light toggle on devices with a frontlight.
    - `Show warmth control`: shows or hides the optional warmth slider on devices with natural-light support.
  - `Expected icon filenames`: lists the custom SVG and PNG names accepted for every action.
- `Reset`:
  - `Reset behavior to defaults`: restores gesture-following placement, right-side fallback, and keep-open behavior while preserving actions, buttons, and appearance.
  - `Reset buttons to defaults`: restores the initial buttons and their order after confirmation without changing the other plugin settings.
  - `Reset behavior and buttons`: additionally restores fixed buttons, default actions, order, and visibility while preserving appearance.
- `Gesture setup`: displays instructions for assigning the dock to a KOReader gesture.
- `Version: v0.19.1`: shows the installed plugin version.

The side selector and visibility options keep their menu open after a change, making it easier to review related settings.

## Gesture setup

1. Open **Settings > Taps and gestures > Gesture manager**.
2. Choose a gesture.
3. Select **Show Shortcut Dock** from the general actions.

With **Behavior > Dock side > Follow gesture side** enabled, the dock opens on the left or right according to the gesture's starting position. Opening it from the Tools menu, a keyboard action, or any event without screen coordinates uses the last fixed side.

The dock can also be opened from **Tools > Shortcut Dock > Show Shortcut Dock**.

## Configuring buttons

Open **Tools > Shortcut Dock > Actions and buttons > Buttons and order**. KOReader's native action selector lets you add or remove actions and arrange their order. The first configured action is shown at the bottom of the dock, and subsequent actions grow upward.

Selecting **Nothing** removes every configurable action and remains effective when switching between the file browser and reader. The fixed context button may still be displayed independently when its visibility option is enabled.

Open **Tools > Shortcut Dock > Actions and buttons > Context visibility > Per-action visibility** to choose one of these options for each configured action:

- **Automatic**: uses the native-action classification when automatic visibility is enabled.
- **Everywhere**: displays the action in every supported screen; this is the default when automatic visibility is disabled.
- **Reader only**: displays the action only while a document is open.
- **File browser and Bookshelf only**: displays the action in the file browser and in Bookshelf, including when Bookshelf is covering a parked reader.

Enable **Tools > Shortcut Dock > Actions and buttons > Context visibility > Automatic visibility** to classify native KOReader actions automatically. Book map, Table of contents, Bookmarks, reading navigation, typography, and document-layout actions are treated as reader-only. File search, folder navigation, sorting, and file-browser display actions are treated as file-browser and Bookshelf only. General actions such as Wi-Fi, lighting, history, and power controls remain available everywhere.

Manual selections always override the automatic result. Unknown actions and actions registered by other plugins default to **Everywhere**. At the top of the visibility menu, **Use automatic visibility for all actions** clears manual overrides when automatic mode is enabled; with automatic mode disabled, the same command is shown as **Show all actions everywhere**.

The **Show side-switch button** and **Show fixed context button** options independently control those fixed controls. Both are enabled by default. The frontlight toggle follows the visibility of the complete frontlight column.

## Reading information panel

The information panel is enabled by default and appears at the opposite edge of the screen: when the dock opens on the left, the panel opens on the right; when the dock opens on the right, the panel opens on the left. It is bottom-aligned using the same screen margin as the dock and uses the same border, white background, and rounded-corner style as its buttons.

The open book's cover is also enabled by default and appears centered at the top of the panel when one is available. Shortcut Dock obtains it through KOReader's current-document cover API, scales it down once to the panel's maximum dimensions, and reuses that thumbnail while the same document and dock scale remain active. Missing covers are cached as unavailable too, avoiding repeated extraction attempts. There is no background loading or polling. Configure both options at **Tools > Shortcut Dock > Appearance > Reading information panel**.

While reading, the panel shows the document title and primary author, current/total page and book percentage, chapter title and progress, estimated time remaining for the book and chapter, today's pages and reading time, the clock, and battery state. It does not show remaining page counts. Stable page labels are used for the displayed book page numbers when enabled, while percentages and estimates continue to follow actual page turns.

In the file browser or Bookshelf, no document-specific fields are invented: the panel shows the available daily reading summary, clock, and battery state. Reading-time fields appear only when KOReader's Statistics plugin is enabled and has data. The statistics API is queried once when the dock opens, and the same snapshot is reused across pagination and side changes; there is no timer, background polling, direct database access, or global ReaderUI/FileManager patch. Disable the block at **Tools > Shortcut Dock > Appearance > Reading information panel > Show panel**.

## Inline actions and Wi-Fi status

When **Keep dock open after actions** is enabled, **Toggle night mode**, **Toggle Wi-Fi**, and **Full screen refresh** run without closing the dock or rebuilding its widgets. Night mode and full refresh are sent directly to the active KOReader device listener; all other configurable actions retain the safer close, dispatch, and conditional-reopen flow when appropriate.

Wi-Fi uses KOReader's native network manager and its standard connection events, but replaces informational progress popups from an inline toggle with a dock-styled status block. When the reading-information panel is visible, the status block appears directly above it on the same opposite screen edge. When that panel is disabled, the status block uses its bottom-aligned position. Turning on, scanning, connecting, connected, turning off, offline, and timeout/error states are covered. While KOReader reports a pending connection, the connecting status has no display timeout and remains until the connection succeeds, fails, or the dock is closed. Native network selection, password, and confirmation dialogs remain available because they require user interaction; errors raised later inside those interactive dialogs retain KOReader's native presentation.

Shortcut Dock does not add a second connectivity polling loop. It relies on KOReader's existing checks and schedules only one final timeout check for an attempted connection. Closing the dock also closes its Wi-Fi status block; the underlying network operation continues normally.

## Lighting controls

On devices with a frontlight, the slider is enabled by default and appears in its own column on the inner side of the action dock. Drag or tap toward the top to increase brightness and toward the bottom to decrease it. The circular thumb follows the active brightness level.

A separate compact button at the bottom of this column toggles the frontlight. It uses `icons/light_on.svg` while the light is active and `icons/light_off.svg` while it is off. Turning the light off disables and dims the slider until the same button turns it back on.

The frontlight column normally has the same total height as the action-button dock. When the action dock is shorter than one third of the screen, the column uses half of the screen height so it remains comfortable to operate. The slider fills the space above the toggle button, and the column's bottom edge stays aligned with the action dock. Disable **Tools > Shortcut Dock > Appearance > Lighting controls > Show frontlight control** to remove both controls.

On devices with natural-light support, **Show warmth control** adds a second optional column. Tap or drag upward for a warmer tone and downward for a cooler tone. Shortcut Dock uses KOReader's native warmth conversion, so devices with ranges such as 0–10, 0–24, or 0–100 retain their actual hardware steps. The control is disabled while the frontlight is off and reads the value only while being drawn or operated; it does not poll in the background.

The warmth column is enabled by default on supported devices. Its bottom button uses `icons/warmth.svg`; tapping it displays the current native warmth level. It can be hidden at **Tools > Shortcut Dock > Appearance > Lighting controls > Show warmth control**. When both lighting columns are enabled, brightness remains next to the action buttons and warmth is placed beside brightness.

Open **Tools > Shortcut Dock > Appearance > Expected icon filenames** to see the exact custom `.svg` and `.png` filenames for every dock action and fixed control, including the frontlight states.

## Bookshelf compatibility

When the Bookshelf plugin is displayed over a parked reader, Shortcut Dock treats it as a separate context. The fixed button changes to the open-document icon and resumes the parked reader instead of sending another `Home` event. This prevents the button from closing Bookshelf while still showing the home icon.

While Bookshelf is in the foreground, **Search current context** opens its **Search library** dialog. If the reader is above a still-loaded Bookshelf screen, the same button opens the full-text search for the current document. The configured **History** action opens the first shelf whose source is **Recent** only while Bookshelf is in the foreground, including a renamed or customized Recent shelf. If either integration point is unavailable in the installed Bookshelf version, Shortcut Dock falls back to the corresponding native KOReader action.

The integration only uses Bookshelf modules that are already loaded. Bookshelf remains an optional plugin and is not loaded or required by Shortcut Dock.

## Custom icons

Put `.svg` or `.png` files in `shortcutdock.koplugin/icons/`. The plugin checks custom files before using KOReader's built-in icon.

Resolution order for regular actions:

1. `icons/<dispatcher-action-id>.svg`
2. `icons/<dispatcher-action-id>.png`
3. `icons/<mapped-stock-icon>.svg`
4. `icons/<mapped-stock-icon>.png`
5. KOReader's built-in icon
6. A short abbreviation generated from the action name

The two stateful actions use their state-specific names before the regular resolution order: `day_mode.svg` / `night_mode.svg` and `wifi_on.svg` / `wifi_off.svg`. These files are checked only when the dock is drawn or the corresponding action changes state; there is no periodic polling.

Examples for regular actions include `history.svg`, `increase_frontlight.svg`, and `shortcutdock_context_search.svg`. The plugin also includes matching chevrons for pagination and changing the dock side, the dynamic home and document icons for the fixed context button, `light_on.svg` / `light_off.svg` for the frontlight toggle, and `warmth.svg` for the warmth column.

For the fixed context button, `shortcutdock_context_home.svg` overrides the icon in every context. To keep its icon dynamic, use `home.svg` while reading and `book.opened.svg` in the file browser or when Bookshelf is covering a parked reader. In that Bookshelf state, the button resumes the reader instead of sending another Home command. The same names with a `.png` extension are also accepted.

## Saved settings

Shortcut Dock stores its preferences through KOReader's reader settings using these keys:

| Setting key | Purpose |
|---|---|
| `shortcutdock_actions` | Enabled actions and their order |
| `shortcutdock_action_contexts` | Per-action reader/browser visibility |
| `shortcutdock_auto_visibility` | Enables automatic context classification |
| `shortcutdock_side` | Left or right dock position |
| `shortcutdock_side_mode` | Selects a fixed position or follows the gesture side; gesture following is the default |
| `shortcutdock_show_side_button` | Visibility of the floating side-switch button |
| `shortcutdock_show_context_button` | Visibility of the fixed contextual button |
| `shortcutdock_show_frontlight_slider` | Visibility of the frontlight slider column |
| `shortcutdock_show_warmth_slider` | Visibility of the frontlight warmth column; enabled by default on supported devices |
| `shortcutdock_show_info_panel` | Visibility of the reading-information panel; enabled by default |
| `shortcutdock_show_info_panel_cover` | Visibility of the open book's cover at the top of the information panel; enabled by default |
| `shortcutdock_dock_size` | Selected Small, Medium, or Large dock scale |
| `shortcutdock_keep_open_after_action` | Reopens the dock after compatible inline actions; enabled by default |

## Code organization

- `main.lua`: plugin lifecycle, saved state, migrations, dock sizing, pagination, and action dispatch.
- `modules/widgets.lua`: lighting sliders, stateful frontlight button, fixed positioning, and multi-column layout.
- `modules/info_panel.lua`: safe collection and opposite-edge rendering of reading progress, covers, statistics, clock, battery, and transient status panels.
- `modules/inline_actions.lua`: in-place night mode, Wi-Fi, and full-refresh execution, including Wi-Fi progress redirection and timeout handling.
- `modules/context.lua`: reader, file-browser, and optional Bookshelf integration.
- `modules/icons.lua`: custom/system icon resolution, stateful icons, and safe shared IconWidget patching.
- `modules/menu.lua`: settings menus, action visibility controls, icon-name help, and reset confirmation.

## Installation

Extract `shortcutdock.koplugin` into KOReader's `plugins` directory and restart KOReader.

- Kindle: `/mnt/us/koreader/plugins/shortcutdock.koplugin`
- Kobo: `/mnt/onboard/.adds/koreader/plugins/shortcutdock.koplugin`
- Android: `<KOReader data directory>/plugins/shortcutdock.koplugin`

## Version

v0.19.1
