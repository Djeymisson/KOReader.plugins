# Dictionary Explorer tools

Tests, performance budgets and benchmarks for
[`dictionaryexplorer.koplugin`](../../dictionaryexplorer.koplugin.md). They run
inside a real KOReader (MuPDF, the real widgets, real gestures), without a
window, in a temporary profile: your KOReader settings, history and dictionaries
are not touched.

```sh
tools/dictionaryexplorer/run.sh check          # everything that passes or fails
tools/dictionaryexplorer/run.sh benchmark      # what each operation costs
tools/dictionaryexplorer/run.sh --help
```

The exit status is 0 when everything passed, 1 when a check failed or a suite
did not finish, so it can gate a commit or a CI job.

## What you need

- A KOReader install, **v2026.07 or newer** (the plugin needs its dictionary
  button API): `/usr/lib/koreader` by default, or `--koreader DIR` /
  `KOREADER_DIR`. It must be able to run on this machine: a Linux desktop
  build, or on macOS the `Contents/koreader` folder of `KOReader.app` (GNU
  `timeout`, from Homebrew's coreutils, is used when it is there).
- Nothing else. Every run makes a set of synthetic dictionaries
  (`fixtures/make.lua`, see below), so all the suites have something to run on.
- Optionally, your StarDict dictionaries: `~/.config/koreader/data/dict` by
  default, or `--dicts DIR` / `DICT_DIR`. The suites look for the author's six
  by a part of their name (Priberam Portuguese, Priberam English–Portuguese,
  Oxford English Dictionary 2nd Ed., Dicionário Aberto, Portuguese–English
  dictionary, WikDict English–Portuguese); what is missing is reported as
  `SKIP`, and the run says how many checks were skipped. Where one of them is
  needed for a whole part of a suite (paging, walking and selection need the
  Portuguese one), the fixture of the same shape is used instead. Any other
  dictionary the plugin can open is covered by the contract and budget suites
  under general limits.

## The suites

Pass or fail (`check` runs all of them):

| Suite | What it checks |
|---|---|
| `unit` | Plain Lua, no KOReader needed. `fitmodel_test`: the fit model (`modules/fitmodel.lua`) on synthetic data: it converges from a bad start, stays finite on degenerate data, ignores nonsense. `text_test`: the text preparation (`modules/text.lua`): type `m` gives exactly the HTML it always did (checked against a reference on real entries and 500 random mixes), and type `x` is tidied as intended. |
| `integrity` | Files that are not what they should be, on fixtures only it sees: an `.idx` cut short (with and without `idxfilesize`), a `wordcount` that does not match, a `.dict` or `.dict.dz` cut short, a `.dict.dz` shorter than the `.idx` needs though its last chunk has room, a `.dict.dz` with a malformed chunk table. Each is refused with its reason and without an error, no cache is written, and the plugin stops offering it; a read past the end gives nil, not fewer bytes. A dictionary indexed while whole whose definitions are then cut is refused when its cache is loaded. A damaged `.syn` (cut, wrong `synwordcount`, leading past the last entry) is left aside with its reason, also from the cache, and the dictionary still opens; a `.syn` changed after indexing makes the cache be rebuilt. Also the index cache: two dictionaries with the same file name, size and date get a cache each, a cache that does not add up or was cut short is rebuilt, writing one leaves no temporary file, and the file of older versions goes. |
| `contract` | The interface a dictionary object must honour for the viewer to work with it (entries with a word and a size known without reading, exact `locate`, `readDefinition` returning `size` bytes, nesting reading sessions, safe `releaseCaches`), on every dictionary found. **This is what a new dictionary format has to pass.** |
| `regression` | The viewer's behaviour with real gestures: opening centred and highlighted, paging by swipe / key / tap, contiguity in both directions, the breadcrumb (going back by tapping its words) and a footer with no arrows, the selection dock with Go to word and Copy, the dictzip and plain formats, the three text types (`m`, `h`, `x`), the Dispatcher action, and the caches being released. |
| `budgets` | 150 page turns per dictionary against limits on counts that do not depend on the machine: layouts per turn, files opened, definitions read, how full pages are, and no entry skipped or repeated. See below. |
| `lookup` | Finding the entry for a word, on Fixture Text (and the Portuguese dictionary when installed): keys in another case, for any letter (`ÁRVORE` → `árvore`, `óbidos` → `Óbidos`, `onu` → `ONU`), the text as given winning when it is a key; words of the `.syn` leading to their entries (inflected forms, accentless spellings, other cases, every generated word across the pages of the fixture's `.syn`, and `abomining` → `abomine` in the Oxford dictionary when installed), a headword winning over the same word in the `.syn`, the trail keeping the word asked for; words typed without their accents (`acao` → `ação`, `obidos` → `Óbidos`, in StarDict and in byte order, and `coracao` → `coração` in the Portuguese dictionary when installed), a headword or a word of the `.syn` winning over them; the suggestions (accented spellings first, at most ten), opened by tapping the notice, shown six a page with ‹ › ✕ at their foot (turning a page keeps the list's size, ✕ closes without a choice), choosing one taking the missed word's place in the trail, closing the list leaving the page as it was; and a word with no entry: the closest entry, with a line on the page saying so (no notification on top), gone with the next page, word or crumb, also when opening from the menu or another plugin. |
| `resume` | Continuing an exploration, through the plugin, on the fixtures: each page keeps where it is without writing a file or saving the settings to disk; continuing (from the menu, the word dialog's Continue button, the Dispatcher action) reopens the dictionary it was left in on the same page, highlighted entry, trail and current word; there is one exploration, the last one; the latest 50 words of the trail are kept; an exploration saved from another version of the dictionary reopens at its word, and a damaged one is not a crash. With nothing explored yet, continuing says so. |
| `switching` | All the dictionaries as one, through the plugin, on the fixtures (and the author's dictionaries when installed): the short names (made from the names, a user's one winning); the priority of a word (exact here, exact elsewhere, accented here, accented elsewhere, closest here); Go to word, the menu and the popup going to the dictionary that has the word and saying so, the dock with no button of its own for it; the header's "· ‹ 1/3 ›" and tapping the right or left half of the name's line to go round the dictionaries that have the word, forward or back (taking the same place in the trail), the rest of the header listing them; the breadcrumb naming each word's dictionary; Search and the suggestions one row per word with its dictionaries; a dictionary never prepared not asked by a word, listed as such, and prepared by the menu; continuing across dictionaries, and what v1.4.0 saved taken over. With the author's dictionaries, `casa` from English–Portuguese going to the Portuguese one. |
| `refresh` | Screen refreshes per action, with the mode and area of each: one for a page turn, Go to word (also with no entry, said on the page) or scrolling the breadcrumb; the suggestions refreshing only their own area, also when turning their pages, and choosing one redrawing the page once; continuing an exploration costing what opening does, and keeping where it is nothing; the list of other dictionaries refreshing only its own area, and going to a word in one redrawing the page once; a word found in another dictionary said on the page at no cost; a search listing its results without redrawing the page; the next or previous dictionary from the header costing a page; and none for an action that changes nothing (swiping or scrolling past either end of the dictionary). On e-ink that is what costs the most battery. Notifications from every source are shown while it measures, so that one an action asks for is counted (KOReader's defaults would hide it). Whether partial refreshes leave ghosting can only be judged on a device. |

Diagnostics (they measure and explain, and never fail):

| Suite | What it shows |
|---|---|
| `benchmark` | CPU, memory and what the plugin did for: opening, a page turn (with and without the trail), loading the modules, the index cache and its rebuild, the first popup, and the selection dock. |
| `profile_turn` | Where a page turn spends its time, function by function. `DE_DICT=Oxford` picks the dictionary, `DE_TRAIL=1` shows the breadcrumb. |
| `profile_open` | The same for opening the viewer at a word, warm. |
| `fitlog` | Every layout attempt of the first turns with what the model predicted, and its two numbers after each turn: use it when a dictionary needs more layouts than it should. |

Run one with `run.sh NAME`; several at once with `run.sh NAME NAME`.

## The budgets

The point of `budgets` is to make it hard to lose the performance work by
accident, for example when adding a dictionary format or touching the layout.
It only limits counts, never times, because times depend on the machine:

| Per turn | Portuguese | English–Portuguese | Oxford | Any other |
|---|---|---|---|---|
| layouts (MuPDF) | 2.2 | 2.0 | 1.6 | 2.5 |
| files opened | 3 | 3 | 2.5 | 3 |
| definitions read | 30 | 14 | 4 | 60 |
| fill of the pages | ≥ 85% | ≥ 90% | ≥ 55% | ≥ 50% |

They were set with room above what each measured (1.6 / 1.3 / 18 / 90% for the
Portuguese one). Undoing the read cache makes them fail, which is how they were
checked. If you improve something for real, lower the limits in
`suites/budgets.lua`; if a limit has to go up, say why in the commit.

CPU time is printed but never checked. To compare times, run `benchmark` on the
same machine before and after a change: a desktop core is many times faster than
an e-reader's, so the figures are for comparison, not for predicting the device.

## How it works

`run.sh` makes a temporary KOReader profile, links the plugin and the
dictionaries into it, and installs a one-file plugin (`lib/launcher.lua`) that
waits for the test book to be ready and hands `lib/harness.lua` to the suite.
Suites run as a sequence of steps on KOReader's event loop (`H.step`), because
some things, like a `Button` running its callback, only happen on the next tick.
The profile is deleted at the end; `--keep` leaves it, with KOReader's log, for
debugging.

```
tools/dictionaryexplorer/
  run.sh              runs suites in an isolated profile; exit status 0 / 1
  lib/
    launcher.lua      the throwaway plugin: starts the suite once the book is ready
    harness.lua       reporting, stepping, gestures, dictionaries, measuring
  fixtures/
    make.lua          writes the synthetic dictionaries (run.sh calls it)
  suites/             one file per suite (see above)
  unit/
    fitmodel_test.lua tests that need no KOReader
    text_test.lua
```

## Adding to it

- **A suite**: add `suites/NAME.lua` returning `function(H, ui)`; use `H.check` /
  `H.skip`, schedule the work with `H.step`, and end with `H.finish()`. Look at
  `regression.lua` for the gestures and `budgets.lua` for measuring.
- **A dictionary format**: implement the object the `contract` suite describes,
  make `H.dictionaries()` in `lib/harness.lua` find it, and run
  `run.sh check`. If `contract` and `budgets` pass, the viewer and its
  performance work will do the rest. Fixtures for the dictionaries the suites
  look for by name are in `H.profiles`.

## The fixtures

`fixtures/make.lua` writes them into each run's temporary profile; nothing is
kept in the repository. It is plain Lua 5.1 (it runs on KOReader's luajit) and
deterministic, so every run sees the same files.

| Fixture | Shape | What it is for |
|---|---|---|
| Fixture Text | `m`, `.dict`, StarDict order, `.syn` (about 400 words, several pages) | stands in for the Portuguese dictionary: the words the suites walk through, homographs (`banco`), words that differ only in case, also with accented capitals (`árvore` / `Árvore`, `ética` / `Ética`), keys only in capitals (`Óbidos`, `ONU`), and entries longer than a screen |
| Fixture HTML | `h`, `.dict.dz` | the dictzip path (small 2 KB chunks, so entries span chunks) and links between entries; `sofa`, which Fixture Text has as `sofá`, for a word typed without its accents |
| Fixture XDXF | `x`, `.dict` | the XDXF-lite text of the Dicionário Aberto |
| Fixture Bytes | `m`, `.dict`, byte order | capitalized words before all the lowercase ones, like Priberam's, and accented words (`maçã`, `Évora`) for the accent search in that order |

The integrity suite's files (the broken dictionaries and the two twins) go
outside the dictionary folder, so no other suite and not the plugin's own
dictionary list ever sees them. To add a case, add it to `make.lua` and check
it in the suite that needs it. The dictzip chunks are stored (uncompressed)
deflate blocks and the gzip CRC is zero: the plugin reads the first like any
other and never checks the second.

## Things to know

- The harness wraps some of the plugin's private functions to count what it
  does (`Viewer._buildHtmlWidget`, `StarDict.readDefinition`, `Inflate.raw`,
  `Viewer._fitPage` ...). If one is renamed, update the wrapper in
  `lib/harness.lua`; a failing `budgets` run that reports zero layouts is the
  sign.
- The `contract` suite checks the field `_dict_file` to see that no file is left
  open. A format that holds a file should use the same name (or the check should
  be adapted).
- Screens are drawn (there is a real framebuffer behind a dummy SDL driver), so
  screenshots can be taken from a suite with `Screen:shot(path)`; use `--keep` to
  find them.
