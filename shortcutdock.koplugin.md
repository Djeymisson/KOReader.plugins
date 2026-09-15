# Shortcut Dock ![Version](https://img.shields.io/badge/version-v0.22.1-blue)

Shortcut Dock adds a floating, vertical shortcut bar to KOReader. It is designed for touch devices and can be assigned to any gesture supported by KOReader.

## Features

- Floating dock anchored near the lower-left or lower-right corner, without touching the screen edges.
- Fixed placement while open: dragging over the dock does not move it away from its selected side.
- Wi-Fi and night mode run in place and keep the dock open; every other configured action closes it before dispatch.
- Gesture-following position enabled by default, opening the dock on the same half of the screen where the assigned gesture started.
- Compact icon buttons using the same scaled dimensions and standard `ButtonDialog` corner radius as Selection Toolbar.
- Three selectable dock scales: Small keeps the original dimensions, Medium increases them by 20%, and Large by 40%.
- Unlimited configurable actions through KOReader's native Dispatcher action picker.
- Configurable button order.
- Optional automatic context visibility for native KOReader actions, with per-action manual overrides.
- Automatic pagination before the enabled buttons would overflow the configured maximum dock height (100%, 60%, or 33% of the screen): the up arrow opens the next page and the down arrow returns to the previous page, without a scrollbar. The lighting columns follow the resulting action-dock height.
- An optional separate button above the dock moves it immediately between the left and right sides.
- An optional separate close button can be placed at the top of the dock's external controls. It uses `close.svg`, is disabled by default, and has the same height as the side-switch and frontlight toggle buttons.
- Configurable closing method: one block at a time by default, or all blocks at once using the smallest encompassing rectangle and a non-flashing UI update.
- Optional vertical frontlight slider in a separate column beside the action buttons, with a circular thumb, live brightness adjustment, and a dedicated frontlight toggle button.
- Optional second lighting column for frontlight warmth on supported devices, using each device's native warmth range.
- Optional information panel on the screen edge opposite the dock. It can show reading information, network information, or both; when both are enabled, one highlighted button immediately above the action dock switches its content without closing the dock.
- Holding a dock button shows its help text in the compact opposite-edge status block above the information panel instead of opening a modal message.
- Night mode and Wi-Fi execute in place without destroying and rebuilding the dock.
- Wi-Fi progress appears in a compact opposite-edge status panel instead of KOReader's informational popups during inline toggles.
- Reader/browser button:
  - opens the previous document from the file browser;
  - returns to the file browser while reading;
  - resumes the parked reader when Bookshelf is open over it.
- The reader/browser button is fixed at the beginning of the action group on the first pagination page and can be hidden in the plugin settings. It is not repeated on later pages. Its icon changes between `exit_reader.svg` in the active reader and `last_doc.svg` in the file browser or Bookshelf.
- Context-aware search button:
  - opens file search in the file browser;
  - opens full-text search while reading;
  - opens Bookshelf's library search while Bookshelf is in the foreground.
- The History action opens Bookshelf's Recent shelf both from Bookshelf and from a book opened through it, and keeps KOReader's native history behavior when that integration is unavailable.
- Interactive night-mode button using `day_mode.svg` or `night_mode.svg` according to the active display mode.
- Interactive Wi-Fi button using `wifi_on.svg` or `wifi_off.svg` according to the radio state.
- Night mode uses KOReader's active device listener and Wi-Fi uses its native network manager while the dock remains open. Their state-specific icons are refreshed without background polling.
- Optional per-action custom icons with automatic fallback to KOReader icons.
- Two-letter action abbreviations when neither a custom nor a KOReader icon is available; hold the button to see its full name.

## Default buttons

From the bottom upward:

1. Reader/browser button: open previous document / file browser / return from Bookshelf to the reader
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
- `Behavior`: controls where the dock opens and how its visible blocks close.
  - `Dock side: <current side>`: selects `Left`, `Right`, or `Follow gesture side`. Following the gesture is enabled by default, and the configured fixed side is used as a fallback when the dock is opened without gesture coordinates.
  - `Dock and panel closing`: selects `One block at a time` (the default sequential behavior) or `All blocks at once` (one non-flashing update over the smallest rectangle containing the visible elements).
- `Actions and buttons`: controls configurable actions, fixed buttons, and context visibility.
  - `Buttons and order`: opens KOReader's native action selector and shows the current number of configured actions.
  - `Fixed buttons`:
    - `Show reader/browser button`: shows the first dock button; it opens the file browser while reading, opens the last document from the file browser, and returns from Bookshelf to the reader.
    - `Show side-switch button`: shows a separate chevron above the dock that changes its side without opening the settings.
    - `Show close button`: shows a separate close control above the dock. Fixed external controls remain stacked above the action column.
  - `Context visibility`:
    - `Automatic visibility`: automatically separates native reader and file-browser actions.
    - `Per-action visibility`: displays the automatic result and controls manual overrides for each action.
- `Appearance`: controls scale, visible panels and columns, and icon customization.
  - `Dock scale: <current scale>`: selects `Small`, `Medium`, or `Large`. The selected scale applies to the buttons, icons, chevrons, lighting columns, information panel, and pagination calculation.
  - `Maximum dock height: <current percentage>`: limits the action, brightness, and warmth columns to approximately `100%`, `60%`, or `33%` of the screen height. Buttons are paginated when they reach the selected limit; the exact height can vary slightly to preserve complete button rows and usable navigation controls. The default is `100%`.
  - `Information panel`:
    - `Show reading information`: shows or hides the Mini Receipt-inspired reading content. Enabled by default.
    - `Show network information`: shows or hides Wi-Fi state and KOReader's interface, MAC, SSID, IP, gateway, and connectivity details. Disabled by default.
    - `Show book cover at the top`: shows or hides the open document's cover above the reading information.
    - `Panel text alignment`: aligns every line of either panel, including the clock and battery, to the `Left`, `Center`, or `Nearest screen edge`. The last option aligns left when the panel is on the left and right when it is on the right. `Left` is the default.
  - `Lighting controls`:
    - `Show frontlight control`: shows or hides the brightness slider and light toggle on devices with a frontlight.
    - `Show warmth control`: shows or hides the optional warmth slider on devices with natural-light support.
  - `Expected icon filenames`: lists the custom SVG and PNG names accepted for every action.
- `Reset`:
  - `Reset behavior to defaults`: restores gesture-following placement, right-side fallback, and one-block-at-a-time closing while preserving actions, buttons, and appearance.
  - `Reset buttons to defaults`: restores the initial buttons and their order after confirmation without changing the other plugin settings.
  - `Reset behavior and buttons`: additionally restores fixed buttons, default actions, order, and visibility while preserving appearance.
- `Gesture setup`: displays instructions for assigning the dock to a KOReader gesture.
- `Version: v0.22.1`: shows the installed plugin version.

The side selector and visibility options keep their menu open after a change, making it easier to review related settings.

## Gesture setup

1. Open **Settings > Taps and gestures > Gesture manager**.
2. Choose a gesture.
3. Select **Show Shortcut Dock** from the general actions.

With **Behavior > Dock side > Follow gesture side** enabled, the dock opens on the left or right according to the gesture's starting position. Opening it from the Tools menu, a keyboard action, or any event without screen coordinates uses the last fixed side.

The dock can also be opened from **Tools > Shortcut Dock > Show Shortcut Dock**.

## Configuring buttons

Open **Tools > Shortcut Dock > Actions and buttons > Buttons and order**. KOReader's native action selector lets you add or remove actions and arrange their order. The first configured action is shown at the bottom of the dock, and subsequent actions grow upward.

Selecting **Nothing** removes every configurable action and remains effective when switching between the file browser and reader. The reader/browser button may still be displayed independently when its visibility option is enabled.

Open **Tools > Shortcut Dock > Actions and buttons > Context visibility > Per-action visibility** to choose one of these options for each configured action:

- **Automatic**: uses the native-action classification when automatic visibility is enabled.
- **Everywhere**: displays the action in every supported screen; this is the default when automatic visibility is disabled.
- **Reader only**: displays the action only while a document is open.
- **File browser and Bookshelf only**: displays the action in the file browser and in Bookshelf, including when Bookshelf is covering a parked reader.

Enable **Tools > Shortcut Dock > Actions and buttons > Context visibility > Automatic visibility** to classify native KOReader actions automatically. Book map, Table of contents, Bookmarks, reading navigation, typography, and document-layout actions are treated as reader-only. File search, folder navigation, sorting, and file-browser display actions are treated as file-browser and Bookshelf only. General actions such as Wi-Fi, lighting, history, and power controls remain available everywhere.

Manual selections always override the automatic result. Unknown actions and actions registered by other plugins default to **Everywhere**. At the top of the visibility menu, **Use automatic visibility for all actions** clears manual overrides when automatic mode is enabled; with automatic mode disabled, the same command is shown as **Show all actions everywhere**.

The **Show close button**, **Show side-switch button**, and **Show reader/browser button** options independently control those fixed controls. The reader/browser and side-switch buttons are enabled by default; the close button is disabled by default. If enabled, it uses `icons/close.svg` or `icons/close.png`, then KOReader's system `close` icon, and finally the text **Close** when no icon is available. When both information types are enabled, an automatic panel-switch button is placed closest to the action dock, below the side-switch and close controls. The frontlight toggle follows the visibility of the complete frontlight column.

## Information panels

The information panel appears at the opposite edge of the screen: when the dock opens on the left, the panel opens on the right; when the dock opens on the right, the panel opens on the left. It is bottom-aligned using the same screen margin as the dock and uses the same border, white background, and rounded-corner style as its buttons. Reading information is enabled by default, while network information is optional.

The open book's cover is also enabled by default and appears centered at the top of the reading panel when one is available. Shortcut Dock obtains it through KOReader's current-document cover API, scales it down once to the panel's maximum dimensions, and reuses that thumbnail while the same document and dock scale remain active. Missing covers are cached as unavailable too, avoiding repeated extraction attempts. There is no background loading or polling. Configure these options at **Tools > Shortcut Dock > Appearance > Information panel**.

While reading, the panel shows the document title and primary author, current/total page and book percentage, chapter title and progress, estimated time remaining for the book and chapter, today's pages and reading time, the clock, and battery state. It does not show remaining page counts. Stable page labels are used for the displayed book page numbers when enabled, while percentages and estimates continue to follow actual page turns.

In the file browser or Bookshelf, no document-specific fields are invented: the reading panel shows the available daily reading summary, clock, and battery state. Reading-time fields appear only when KOReader's Statistics plugin is enabled and has data. The statistics API is queried once when the dock opens, and the same snapshot is reused across pagination and side changes; there is no timer, background polling, direct database access, or global ReaderUI/FileManager patch.

The network panel displays the current Wi-Fi state and uses KOReader's native network-information provider for available interface, MAC, SSID, IPv4/IPv6, gateway, and gateway-test details. This data is collected when the network panel is opened or selected and refreshed from KOReader's connection events when the dock's Wi-Fi button changes state; there is no background polling. With both reading and network information enabled, one square button immediately above the action dock alternates between them without rebuilding or closing the dock. It uses the same dimensions, border, rounded corners, and press feedback as the frontlight toggle. Its icon indicates the panel currently visible: `reading_info.svg` (with the system open-book icon as fallback) for Reading, or `network_info.svg` for Network. Holding the button describes the current panel and the tap action.

## Inline actions and Wi-Fi status

**Toggle night mode** and **Toggle Wi-Fi** always run without closing or rebuilding the dock. Night mode is sent directly to the active KOReader device listener, while Wi-Fi uses the inline flow described below. Every other configurable action, including **Full screen refresh**, closes the dock before being sent through KOReader's Dispatcher and is not reopened automatically.

Wi-Fi uses KOReader's native network manager and its standard connection events, but replaces informational progress popups from an inline toggle with a dock-styled status block. When either information panel is visible, the status block appears directly above it on the same opposite screen edge. When both panels are disabled, the status block uses its bottom-aligned position. Turning on, scanning, connecting, connected, turning off, offline, and timeout/error states are covered. While KOReader reports a pending connection, the connecting status has no display timeout and remains until the connection succeeds, fails, or the dock is closed. Repeated native scan and authentication messages reuse this same overlay instead of closing and recreating it before each forced repaint. Native network selection, password, and confirmation dialogs remain available because they require user interaction; errors raised later inside those interactive dialogs retain KOReader's native presentation.

The same status block displays button help for three seconds when a dock button is held, including pagination arrows and the fixed controls. These messages are non-modal and do not block touches on the dock, lighting sliders, or the underlying screen. A newer Wi-Fi state always replaces an older help message safely.

Shortcut Dock does not add a second connectivity polling loop. It relies on KOReader's existing checks and schedules only one final timeout check for an attempted connection. Closing the dock also closes its Wi-Fi status block; the underlying network operation continues normally.

## Lighting controls

On devices with a frontlight, the slider is enabled by default and appears in its own column on the inner side of the action dock. Drag or tap toward the top to increase brightness and toward the bottom to decrease it. The circular thumb follows the active brightness level.

A separate compact button at the bottom of this column toggles the frontlight. It uses `icons/light_on.svg` while the light is active and `icons/light_off.svg` while it is off. Turning the light off disables and dims the slider until the same button turns it back on.

The frontlight and warmth columns have the same total height as the rendered action-button dock, including when its maximum height is set to 60% or 33%. Each slider fills the space above its bottom button, and all columns remain aligned along the bottom edge. Disable **Tools > Shortcut Dock > Appearance > Lighting controls > Show frontlight control** to remove the brightness controls.

On devices with natural-light support, **Show warmth control** adds a second optional column. Tap or drag upward for a warmer tone and downward for a cooler tone. Shortcut Dock uses KOReader's native warmth conversion, so devices with ranges such as 0–10, 0–24, or 0–100 retain their actual hardware steps. The control is disabled while the frontlight is off and reads the value only while being drawn or operated; it does not poll in the background.

The warmth column is enabled by default on supported devices. Its bottom button uses `icons/warmth.svg`; tapping it displays the current native warmth level. It can be hidden at **Tools > Shortcut Dock > Appearance > Lighting controls > Show warmth control**. When both lighting columns are enabled, brightness remains next to the action buttons and warmth is placed beside brightness.

Open **Tools > Shortcut Dock > Appearance > Expected icon filenames** to see the exact custom `.svg` and `.png` filenames for every dock action and fixed control, including the frontlight states.

## Bookshelf compatibility

When the Bookshelf plugin is displayed over a parked reader, Shortcut Dock treats it as a separate context. The fixed button changes to `last_doc.svg` and resumes the parked reader instead of sending another `Home` event. This prevents the button from closing Bookshelf while still showing the reader-exit icon.

While Bookshelf is in the foreground, **Search current context** opens its **Search library** dialog. If the reader is above a still-loaded Bookshelf screen, the same button opens the full-text search for the current document. The configured **History** action opens the first shelf whose source is **Recent**, including a renamed or customized Recent shelf. From the reader, it brings the still-loaded Bookshelf back to the foreground already on that shelf. If either integration point is unavailable in the installed Bookshelf version, Shortcut Dock falls back to the corresponding native KOReader action.

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

Examples for regular actions include `history.svg`, `increase_frontlight.svg`, and `shortcutdock_context_search.svg`. The plugin also includes matching chevrons for pagination and changing the dock side, `close.svg` for the optional close button, `exit_reader.svg` / `last_doc.svg` for the reader/browser button, `reading_info.svg` / `network_info.svg` for the information-panel switch, `light_on.svg` / `light_off.svg` for the frontlight toggle, and `warmth.svg` for the warmth column.

For the reader/browser button, use `exit_reader.svg` while reading and `last_doc.svg` in the file browser or when Bookshelf is covering a parked reader. In that Bookshelf state, the button resumes the reader instead of sending another Home command. The same names with a `.png` extension are also accepted.

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
| `shortcutdock_show_close_button` | Visibility of the floating close button; disabled by default |
| `shortcutdock_show_context_button` | Visibility of the reader/browser button |
| `shortcutdock_show_frontlight_slider` | Visibility of the frontlight slider column |
| `shortcutdock_show_warmth_slider` | Visibility of the frontlight warmth column; enabled by default on supported devices |
| `shortcutdock_show_info_panel` | Visibility of the reading-information panel; enabled by default |
| `shortcutdock_show_network_info_panel` | Visibility of the network-information panel; disabled by default |
| `shortcutdock_show_info_panel_cover` | Visibility of the open book's cover at the top of the information panel; enabled by default |
| `shortcutdock_info_panel_text_alignment` | Left, centered, or nearest-screen-edge alignment for all information-panel text |
| `shortcutdock_dock_size` | Selected Small, Medium, or Large dock scale |
| `shortcutdock_max_action_dock_height` | Maximum dock-column height as 100%, 60%, or 33% of the screen; defaults to 100% |
| `shortcutdock_close_together` | Closes all blocks in one non-flashing update over their smallest encompassing rectangle; disabled by default |

## Code organization

- `main.lua`: plugin lifecycle, saved state, migrations, dock sizing, pagination, and action dispatch.
- `modules/widgets.lua`: external close, side-switch, and information-panel controls, lighting sliders, stateful buttons, fixed positioning, and multi-column layout.
- `modules/info_panel.lua`: safe collection and opposite-edge rendering of reading and network details, covers, statistics, clock, battery, and transient status panels.
- `modules/inline_actions.lua`: in-place night-mode and Wi-Fi execution, including Wi-Fi progress redirection and timeout handling.
- `modules/context.lua`: reader, file-browser, and optional Bookshelf integration.
- `modules/icons.lua`: custom/system icon resolution, stateful icons, and safe shared IconWidget patching.
- `modules/menu.lua`: settings menus, action visibility controls, icon-name help, and reset confirmation.

## Installation

Extract `shortcutdock.koplugin` into KOReader's `plugins` directory and restart KOReader.

- Kindle: `/mnt/us/koreader/plugins/shortcutdock.koplugin`
- Kobo: `/mnt/onboard/.adds/koreader/plugins/shortcutdock.koplugin`
- Android: `<KOReader data directory>/plugins/shortcutdock.koplugin`

## Version

v0.22.1
