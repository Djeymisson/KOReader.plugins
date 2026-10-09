# Selection Toolbar ![Version](https://img.shields.io/badge/version-v1.7.0-blue)

A KOReader plugin that replaces the centered text-selection menu with a compact toolbar displayed near the selected text, and adds draggable handles and a margin line marker to adjust and visualize the selection.

The plugin is developed for **EPUB** documents only (KOReader's crengine engine). In PDF, DjVu, CBZ and other paged documents it stays inactive: KOReader's native selection menu is used and the plugin's menu is not shown.

## Features

- Replaces KOReader's default highlight menu with a single row of icon buttons whenever more than one word is selected.
- The toolbar appears below the selection when there is enough space, otherwise above it. Alternatively, it can be kept at a fixed position: centered at the bottom of the screen, or at the top when the selection is in the lower part of the screen.
- When the selection fills the screen, the toolbar is pinned to the screen edge opposite to the last selection point (top if you last selected near the bottom, and vice versa), and slid sideways so it covers neither selection handle when the width allows it.
- Native actions reuse the original `ReaderHighlight` callbacks, preserving KOReader's default behavior.
- Icons are loaded directly from the plugin's own folder — no need to copy files into internal KOReader directories.
- Selection handles: while the toolbar is open, a handle is drawn at the start and at the end of the selection. Drag a handle to extend or shrink the selection; dragging one past the other swaps them. Four handle styles are available (lollipop, teardrop, brackets and flag tabs), with an optional high-contrast outline.
- Cross-page selection: dragging a handle into a page corner continues the selection on the next or previous page, reusing KOReader's own corner-scroll behavior (`Long-press on text > Auto-scroll when selection reaches a corner` must be enabled).
- Line marker: a vertical line in the page margin beside the selected lines, one per visible page in two-page mode.
- Reversible: disabling the plugin restores the original menu immediately.

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

The `Generate QR code` action uses the native `ui/widget/qrmessage` widget when it is available in the installed KOReader version.

## Installation

Copy the plugin folder to KOReader's `plugins` directory:

```text
selectiontoolbar.koplugin/
├── _meta.lua
├── main.lua
└── icons/
    ├── add_note.svg
    ├── copy.svg
    ├── dictionary.svg
    ├── highlight.svg
    ├── qr_code.svg
    ├── search.svg
    ├── select.svg
    ├── translate.svg
    ├── view_html.svg
    └── wikipedia.svg
```

The final path should look like this:

```text
koreader/plugins/selectiontoolbar.koplugin/
```

Then restart KOReader.

## Configuration

In the reader, open:

`Top menu > Settings > Selection toolbar`

Options:

- `Use compact selection toolbar`: enables/disables replacement of the default menu.
- `Appearance`: controls the toolbar's visual presentation. While this submenu (or `Visible actions`) is open, a live preview follows each change: a sheet titled `Preview`, docked across the bottom of the screen with rounded top corners, a thick border and a dithered shadow cast upwards over the page, where the toolbar lies over a few lines of sample text, as it would over the book, so borders, shadow and separators can be judged against text. When the menu leaves little room, fewer sample lines are shown. The preview is hidden while a dialog (such as an option's help) is shown, or when the menu is too tall to leave room for it, and it closes when you leave these submenus.
  - `Toolbar position`: where the toolbar is shown.
    - `Near the selection` (default): right below the selection, or above it when there is no room.
    - `Fixed at screen edge`: centered at the bottom edge of the screen, or at the top edge when the selection's center is in the lower half (or when only the top edge keeps the toolbar clear of the selection and its handles). When the selection fills the screen, the toolbar is pinned as described in the features above, in both modes.
  - `Button density`: size and spacing of the toolbar buttons.
    - `Compact`: smaller, tighter buttons, so the toolbar covers less of the page.
    - `Normal` (default): the standard button size and spacing.
    - `Comfortable`: taller, more spaced buttons, easier to tap.

    If the enabled actions do not fit across the screen at the chosen density, the buttons (and, if needed, the icons) are narrowed so the toolbar always stays on screen.
  - `Icon size`: `Small`, `Normal` (default) or `Large` icons, independently of the button density. An icon never grows beyond its button.
  - `Show toolbar shadow`: shows or removes the dithered shadow along the right and bottom edges. The shadow follows the toolbar's rounded corners.
- `Selection marks`: controls the handles and the line marker.
  - `Show selection handles`: shows the draggable start/end handles (touch devices only).
  - `Handle style`: how the handles are drawn.
    - `Lollipop` (default): a bar at the selection edge with a round knob above the start and below the end.
    - `Teardrop`: a drop below the line, pointing at the selection edge, as on Android.
    - `Brackets`: a `[` at the start and a `]` at the end. The most discreet style.
    - `Flag tabs`: a pole at the selection edge with a trapezoid grab tab pointing outwards, above the start and below the end. Only the tab's side facing the text is slanted, so it narrows toward the text instead of covering it.
    - `High-contrast outline`: draws lollipops, teardrops and flag tabs as a black outline over white, readable over dark or highlighted text. Not available for brackets, whose strokes are too thin to outline. A `High-contrast wireframe` style saved by v1.3.0 is read as a lollipop with this outline.

    All styles share the same touch area around the handle, so the style changes only the look, not how easy the handles are to grab.
  - `Show line marker`: shows the vertical line beside the selected lines.
  - `Line marker in right margin`: draws the line marker in the right margin instead of the left one (mirrored for right-to-left interface languages).
- `Visible actions`: lets you choose which actions appear in the toolbar.
  - `Show all actions`: restores all actions.
  - Other items: enable/disable each toolbar action individually.
- `Version: vX.Y.Z`: shows the installed plugin version.

## Icons

Icons are stored in:

`selectiontoolbar.koplugin/icons/`

The current version loads icons directly from the plugin's own folder. There is no need to copy SVGs to internal KOReader directories or to KOReader's data directory.

Internally, the plugin applies a lightweight patch to `IconWidget` so it can accept direct `.svg`/`.png` file paths passed through the `icon` field. This patch only uses values explicitly defined in the widget, avoiding conflicts with other plugins that also use `IconWidget` or load icons through `file`.

## How it works

The plugin includes a few internal adjustments to reduce repeated work when opening the toolbar:

- icon path caching;
- caching of the `ui/widget/qrmessage` module after the first check;
- cached dithered shadows, shared between toolbar openings of the same size;
- single read of the visible actions when building the toolbar;
- page offset calculation only once before iterating over the selection boxes;
- button metrics (width, height, icon size and side padding) computed once per density and icon size combination.
- the settings preview is built by the same function as the real toolbar, so both always look the same; it is a toast widget, so it never takes the menu's taps.
- the preview keeps its sample text and title between changes, and only rebuilds the toolbar when a setting changes; the sample text is just long enough to fill its lines;
- the preview's shadow is computed once per opening (and screen width or night mode), and changing a setting only refreshes the preview area, repainting the page under it only when the preview changes height.

Selection handles and line marker:

- the marks are painted by a `ReaderView` view module, on the page itself, only while the toolbar opened for a live selection is shown. They are computed on every repaint from the selection's xpointers (`getScreenBoxesFromPositions`), so they follow the selection after a drag or a page scroll.
- while the toolbar is open it is the top widget and receives every gesture, so the handle gestures (`hold`, `pan`, `hold_pan`, `swipe`, `multiswipe`) are registered on the toolbar dialog itself. During a drag only `pan` and `hold_pan` keep it going; any other gesture ends it (the lift may arrive as `pan_release`, `hold_release`, `swipe` or `multiswipe` depending on timing and path), so the toolbar is never left hidden. Only gestures that start on a handle are consumed, and they are handled before the toolbar's own children, so dragging a handle across the toolbar never moves the toolbar. Toolbar buttons keep priority where the toolbar is shown, and the toolbar is placed clear of the handles' touch areas. A tap on a handle does not close the toolbar.
- dragging a handle sets KOReader's hold position to the opposite end of the selection and drives `ReaderHighlight:onHoldPan()`, the same path used by long-press selection and by keyboard selection. Word snapping, page-corner scrolling and selection rendering are therefore KOReader's own.
- the toolbar is hidden while a handle is dragged and re-anchored to the selection on release. Pan events are rate-limited with KOReader's `hold_pan_rate` setting.

Screen refresh and battery:

- while a handle is dragged, only the band of lines between the moving end's old and new position is refreshed, instead of the full-screen refresh KOReader's own selection uses on each change. The old end's position is taken from the selection boxes in the current view (KOReader does not recompute them after a page-corner scroll). The full screen is still refreshed when the view scrolls during a move and in two-page mode.
- finger moves smaller than a few pixels are not sent to crengine while dragging, since word-snapped selection would rarely change. The position where the finger is lifted is always applied.
- releasing a handle does not flash the hidden toolbar's area, and does not refresh the handles and line marker again, as they are already up to date on screen.
- the line marker and handles are refreshed as separate small areas rather than as their bounding box, which for long selections covered most of the screen.
- the selection boxes are only requested again from crengine when the selection or the view changed, not on every reader repaint while the toolbar is open; icon file checks are cached per path.

When the plugin is closed, the patch applied to the highlight menu and to `IconWidget` is restored when it is still the active Selection Toolbar patch.

## Known limitations

- EPUB only. The plugin is inactive in PDF, DjVu and other paged documents.
- Handles are not shown for saved highlights opened from the page (KOReader's own highlight dialog already offers start/end adjustment for those), only for a new selection.
- A handle whose end of the selection is off-screen (after scrolling across pages) is not drawn until that end is visible again; the visible handle can still be dragged.
- Right-to-left and vertical text are not specifically handled: the handles follow the first and last selection boxes.
- Cross-page dragging in two-page mode is limited to the adjacent page, as in KOReader's native selection.

- `View HTML` only appears when the original action exists for the current document, following KOReader's own rule.
- On very narrow screens, the toolbar remains compact, but it may take up a large portion of the available width if all 10 actions are enabled.
- The plugin is reversible: when disabling the `Use compact selection toolbar` option, the original menu is used again.

## Uninstalling

Remove the folder:

```text
koreader/plugins/selectiontoolbar.koplugin/
```

Then restart KOReader.

Settings saved in KOReader may remain until manually removed from KOReader's settings storage, but they will not have any effect once the plugin is removed.

## Screenshots

![selection_toolbar](assets/screenshots/selectiontoolbar.koplugin/selection_toolbar.png)
![selection_toolbar_actions](assets/screenshots/selectiontoolbar.koplugin/selection_toolbar_actions.png)
![config_menu](assets/screenshots/selectiontoolbar.koplugin/config_menu.png)
