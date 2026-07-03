# Plain UI Custom

**Plain UI Custom** is a plugin for [KOReader](https://github.com/koreader/koreader) that modifies the file manager screen to provide a more library-oriented navigation experience, with tabs for **Files**, **Series**, **Authors**, and **Tags**, as well as filters, per-view sorting, and visual annotations on covers/list entries.

The plugin works as a customization layer on top of KOReader's File Manager. It creates virtual views from book metadata and adapts the interface to make it easier to browse by author, series, and tag without moving or renaming files in storage.

## Features

- Adds navigation tabs to the file manager:
  - **Files**
  - **Series**
  - **Authors**
  - **Tags**
- Creates virtual paths for browsing by metadata.
- Allows listing books by:
  - author;
  - series;
  - tag/keyword.
- Supports reading status filters:
  - all;
  - unread;
  - reading;
  - finished.
- Adds filter and sort menus for each tab.
- Allows refining the current view by multiple metadata dimensions using a facet menu.
- Keeps navigation based on the real library directory while adding a virtual organization layer.
- Customizes the File Manager header and footer.
- Displays status information in the header/footer, such as Wi-Fi, battery, and time, depending on the module configuration.
- Integrates visual annotations on covers/list entries, such as reading percentage and a finished-book indicator, when the corresponding modules are present.

## Recommended structure

The plugin folder should look like this:

```text
plainui-custom.koplugin/
├── _meta.lua
├── main.lua
└── modules/
    ├── author_series.lua
    ├── metadata_tabs.lua
    ├── metadata_facet_dropdown.lua
    ├── metadata_source.lua
    ├── metadata_sort.lua
    ├── filter_state.lua
    ├── virtual_path.lua
    ├── virtual_leaf.lua
    ├── tab_option_dialog.lua
    ├── tab_option_presenter.lua
    ├── tab_view_options.lua
    ├── status_indicators.lua
    ├── cover_badge.lua
    ├── cover_overlay.lua
    ├── finished_badge.lua
    └── reading_percentage.lua
```

Some of these modules are internal dependencies used by the main files. If any required module is missing, KOReader may fail to load the plugin during startup.

## Installation

1. Download or clone this repository.
2. Copy the plugin folder to KOReader's `plugins` folder.

Example:

```text
koreader/plugins/plainui-custom.koplugin/
```

On Kindle devices, the structure usually looks something like this:

```text
/KOReader/plugins/plainui-custom.koplugin/
```

3. Restart KOReader.
4. Open the file manager.

The plugin is loaded automatically when KOReader starts. It is not limited to the document reader, since it mainly acts on the File Manager.

## How to use

After installing and restarting KOReader, open the file manager. The interface will show navigation tabs for accessing books by files, series, authors, and tags.

### Main tabs

- **Files** shows the traditional folder and file navigation.
- **Series** groups books by series.
- **Authors** groups books by author.
- **Tags** groups books by tags/keyword metadata.

Tapping a tab that is not currently selected switches the view. Tapping the selected tab again opens the options menu for that view.

### Filters and sorting

Each tab can have its own filter and sorting options. The options menu allows switching between different reading status filters and sorting modes.

Examples of filters:

```text
All
Unread
Reading
Finished
```

Depending on the tab, sorting can be based on name, title, author, series, progress, or recent access.

### Metadata navigation

When entering a view by author, series, or tag, the plugin creates a virtual list of metadata values. Selecting a value makes the File Manager show the matching books.

These paths are virtual: they only exist for navigation inside KOReader and do not represent real folders in the filesystem.

### Facet refinement

When you are inside a metadata group, the plugin can display a facet menu to refine the current list. This makes it possible to combine filters, for example:

```text
Author → Series
Tag → Author
Series → Reading status
```

The menu also shows counts when available, helping you understand how many books remain under each option.

## How it works internally

The plugin is composed of modules that apply patches to parts of KOReader.

### `_meta.lua`

Defines the plugin metadata:

```lua
name = "plainui-custom"
fullname = "Plain UI Custom"
version = "1.2-custom"
```

KOReader uses this information to identify the plugin.

### `main.lua`

This is the plugin entry point. It applies the patches once and loads the main modules:

```lua
modules.author_series
modules.metadata_tabs
modules.finished_badge
modules.reading_percentage
```

### `modules/author_series.lua`

Adds virtual metadata navigation to the File Manager. This module modifies parts of `FileManager` and `FileChooser` to recognize virtual paths, generate author/series/tag lists, and display the matching books.

It also registers actions such as:

```text
Browse by author
Browse by series
Browse by tag
```

### `modules/metadata_tabs.lua`

Modifies the File Manager interface. This module adds the tab bar, adapts the header/footer, updates the visual state of the selected tab, and integrates the filter and sort menus.

It also manages contextual information such as:

- current folder;
- current view;
- applied filter;
- opened metadata group;
- status indicators.

### `modules/metadata_facet_dropdown.lua`

Displays facet refinement menus. It allows navigating between metadata dimensions and choosing additional filters without leaving the current view.

### `modules/metadata_source.lua`

Centralizes access to book metadata. This module queries KOReader's book information database, filters valid files, calculates counts, and maintains caches to improve performance in large libraries.

It treats files with extensions such as the following as books:

```text
azw, cbr, cbt, cbz, djvu, epub, fb2, mobi, pdf, rtf
```

## Customization

Some visual adjustments can be made directly in the modules.

In `modules/metadata_tabs.lua`, look for constants such as:

```lua
local PLAINUI_TABS_AT_BOTTOM = true
local PLAINUI_BOTTOM_FONT_SIZE = 22
local PLAINUI_HEADER_FOLDER_FONT_SIZE = 22
local PLAINUI_SIDE_MARGIN = Screen:scaleBySize(14)
```

These options control, for example:

- whether the tabs are placed in the footer;
- footer font size;
- header context font size;
- interface side margin.

After changing these values, restart KOReader to apply the changes.

## Important notes

- The plugin modifies the internal behavior of the File Manager through patches. Future KOReader changes may require plugin adjustments.
- Metadata navigation depends on the metadata known by KOReader. Books that have not been indexed yet or do not have metadata may appear incompletely.
- The first navigation in large libraries may be slower because the plugin needs to build lists and caches.
- Virtual paths are only a representation inside KOReader. No files are moved, renamed, or reorganized in storage.
- If the listing appears outdated, use KOReader's refresh/reload folder option to invalidate caches and rebuild the view.
- The `finished_badge.lua` and `reading_percentage.lua` modules must be present for cover/list visual annotations to be applied.

## Compatibility

This plugin is intended for recent KOReader versions with support for the `.koplugin` plugin system and the standard File Manager. Since it applies patches to internal classes, it is recommended to test it after major KOReader updates.

## Credits

Based on the work of **Anh Do** and on ideas/adaptations related to the Browse by Metadata patch, inspired by previous contributions from the KOReader community.

## License

MIT, as indicated in the module headers.
