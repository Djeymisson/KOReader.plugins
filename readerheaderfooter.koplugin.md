# Reader Header Footer ![Version](https://img.shields.io/badge/version-v1.0.10-blue)

Plugin for [KOReader](https://koreader.rocks/) that adds discreet header and footer information while reading.

It displays indicators directly in the document margins, without opening extra bars or changing the reader's main interface.

## Features

The plugin adds four information areas to the reading screen:

- **Top left**: chapter title or author + book title.
- **Top right**: Wi-Fi indicator, time, and battery.
- **Bottom left**: pages left in the current chapter or in the book.
- **Bottom right**: document reading percentage.

The goal is to keep useful information always visible while remaining lightweight and unobtrusive.

## Installation

Copy the plugin folder to KOReader's `plugins` directory:

```text
readerheaderfooter.koplugin/
├── _meta.lua
├── main.lua
└── readerheaderfooter_l10n.lua
```

The final path should look like this:

```text
koreader/plugins/readerheaderfooter.koplugin/
```

On Kindle devices, it is usually located at:

```text
/mnt/us/koreader/plugins/readerheaderfooter.koplugin/
```

Then restart KOReader, open a book, and access the reader menu to configure the plugin.

## Displayed information

### Top right

Shows:

```text
Wi-Fi • HH:MM • Battery
```

Example:

```text
 • 14:32 •  87%
```

If the device does not have a battery, or if battery information is unavailable, the battery indicator is omitted.

### Top left

Shows contextual book information:

- on even-numbered pages: `Author • Title`;
- on odd-numbered pages: current chapter title;
- at the beginning of a chapter: the top-left area stays empty to avoid unnecessary repetition.

### Bottom left

Can display one of two pieces of information:

```text
10 pages left in chapter
```

or:

```text
120 pages left in book
```

This behavior can be configured from the plugin menu.

### Bottom right

Shows the percentage of the document that has been read:

```text
42%
```

## Configuration

The plugin adds an item to the reader's main menu:

```text
Header/footer indicators
```

The settings follow the same grouped layout as the other plugins in this repository:

- `Show header/footer`: turns every indicator on or off without removing the plugin.
- `Appearance`: chooses which indicators are shown, what the bottom-left counter tracks, and the indicator font size and margins.
  - `Displayed items`: shows or hides each indicator independently — `Wi-Fi status`, `Clock`, `Battery status`, `Battery percentage` (only while battery status is shown), `Bottom-left pages left`, and `Reading percentage`.
  - `Bottom-left info`: selects whether the bottom-left counter tracks `Pages left in chapter` or `Pages left in book`. Disabled while the bottom-left indicator itself is hidden.
  - `Font`:
    - `Font size`: opens a spinner for the indicator font size (minimum `10`, default `16`, maximum `28`).
    - `Reset font size`: restores the default size.
  - `Margins`:
    - `Follow document margins`: aligns the indicators with the document's real margins (enabled by default).
    - `Custom side margins`, `Custom left margin`, `Custom right margin`: manual margins in points (minimum `0`, maximum `300`), used only while document margins are not followed.
- `Version: vX.Y.Z`: shows the installed plugin version.

## How it works

The plugin is loaded as a KOReader reader module and draws text directly over the top and bottom regions of the page.

It avoids full-screen redraws whenever possible. Instead, it invalidates only the small areas where the indicators are displayed. This reduces flickering and avoids heavy full-page refreshes.

It also includes protection for menus and dialogs: if a KOReader menu is open, indicator updates are deferred until the reader becomes the active window again.

The plugin automatically updates the indicators on the following events:

- page change;
- reading position update;
- Wi-Fi state change;
- battery charging state change;
- device resume after suspension;
- minute change, to update the clock.

The battery is checked periodically every 5 minutes.

## Code organization

```text
readerheaderfooter.koplugin/
├── _meta.lua                     # metadata displayed by KOReader
├── main.lua                      # main plugin implementation
└── readerheaderfooter_l10n.lua   # locale-aware translations, with KOReader gettext fallback
```

## Saved settings

Preferences are stored in KOReader's settings using the following keys:

| Setting key | Purpose |
|---|---|
| `reader_header_footer_enabled` | Enables or disables the indicators |
| `reader_header_footer_font_size` | Indicator font size |
| `reader_header_footer_follow_document_margins` | Aligns indicators with the document's real margins |
| `reader_header_footer_custom_left_margin` | Manual left margin, used only while document margins are not followed |
| `reader_header_footer_custom_right_margin` | Manual right margin, used only while document margins are not followed |
| `reader_header_footer_custom_horizontal_margin` | Manual side margin shortcut, used only while document margins are not followed |
| `reader_header_footer_left_footer_mode` | Selects whether the bottom-left counter tracks pages left in chapter or in book |

## Advanced customization

Some values can be adjusted directly at the beginning of `main.lua`.

### Font size

```lua
local FONT = {
    name = "NotoSans-Regular.ttf",
    default_size = 16,
    min_size = 10,
    max_size = 28,
}
```

### Spacing and positioning

```lua
local LAYOUT = {
    padding = 10,
    top_padding = 2,
    bottom_padding = 10,
    text_clear_extra = 6,
    line_extra_for_region = 8,
    line_extra_for_paint = 4,
    left_right_gap = 16,
}
```

### Default margins

```lua
local INDICATOR_MARGINS = {
    default_follow_document = true,
    default_left = 20,
    default_right = 20,
    min = 0,
    max = 300,
}
```

## Performance

The plugin was designed to be lightweight. Some important decisions:

- uses regional updates instead of full refreshes;
- avoids redrawing while menus or dialogs are open;
- updates the clock only when the minute changes;
- checks the battery periodically, not continuously;
- reuses the current page state, page count, and visible reader area;
- trims overflowing header/footer text using glyph-aware measurement, so a multi-byte character (accents, the Wi-Fi symbol) is never split in half at the cut-off point.

## Localization

Reader Header/Footer follows KOReader's active interface language. Plugin-specific messages — the settings menu, the bottom-left "pages left" indicator (with correct singular/plural forms), and the version dialog — are translated into Brazilian and European Portuguese; in other interface languages, plugin-specific messages fall back to English. Document content such as the chapter title and author/title metadata always comes from the book itself and is never translated.

## Known limitations

- The plugin depends on metadata and table-of-contents information provided by KOReader.
- In documents without a table of contents, the pages-left-in-chapter count may fall back to the pages-left-in-book count.
- The chapter title may be empty if the document does not provide a reliable TOC structure.
- In very unusual layouts, automatic margins may not exactly match the visual text area. In those cases, use manual margins.

## Uninstalling

Remove the folder:

```text
koreader/plugins/readerheaderfooter.koplugin/
```

Then restart KOReader.

Settings saved in KOReader may remain until manually removed from KOReader's settings storage, but they will not have any effect once the plugin is removed.

## Screenshots

![settings-menu](assets/screenshots/readerheaderfooter.koplugin/settings-menu.png)
![author-booktitle](assets/screenshots/readerheaderfooter.koplugin/author-booktitle.png)
![chapter-title](assets/screenshots/readerheaderfooter.koplugin/chapter-title.png)
![empty-corner](assets/screenshots/readerheaderfooter.koplugin/empty-corner.png)

## Credits

Custom plugin for KOReader.
