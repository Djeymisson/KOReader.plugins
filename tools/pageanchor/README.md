# Page Anchor tools

A behaviour simulation for [`pageanchor.koplugin`](../../pageanchor.koplugin.md).
It loads the plugin's real `main.lua` and `modules/history.lua`, swaps the
KOReader modules they use for small stand-ins, and runs scenarios against the
plugin's logic. It needs no KOReader install, no window and no device.

```sh
lua tools/pageanchor/sim.lua
```

It prints one `ok` or `FAIL` line per check, then `ALL PASSED` or the number of
failures. The exit status is 0 when everything passed and 1 otherwise, so it can
gate a commit or a CI job. Any Lua 5.1+ interpreter works (`lua`, `luajit`).

## What it covers

Behaviour, not looks. The scenarios check what the plugin decides and
remembers:

- when an anchor is armed (announced jumps of any distance, unannounced ones
  past the re-reading tolerance), resolved, or left alone (page turns,
  repagination after a font or orientation change, two-page mode);
- the return point, its directional dismissal, and the wider tolerance that
  protects it right after returning;
- hiding, the minimized tab, the hidden-buttons expiry and showing again;
- discarding, the undo notice and restoring, including after moving;
- pinned anchors and their icons;
- the trail: what joins it, picking an entry, keeping it across returns,
  clearing and restoring it, opening it with the buttons hidden;
- exact-line markers for links and scroll mode;
- fixed-layout (PDF) view state, pan and zoom included;
- percentages, button position, touch zone registration, gesture actions,
  and that thumbnails are painted without the buttons.

## What it doesn't

The widgets are fakes, so it can't tell whether an icon renders well, how the
pill or the tab look, or whether a tap lands where it should on a real screen.
Those still need a device (or the desktop KOReader).

## How it models KOReader

The stand-ins follow KOReader's own behaviour where the plugin depends on it,
as read in KOReader's source. The ones that matter most:

- `ReaderLink:getCurrentLocation()` lags one move behind during
  `PageUpdate`/`PosUpdate` (ReaderRolling updates its xpointer only after
  sending them), while the document itself is already at the new position;
- `RestoreBookLocation` moves synchronously and sends its own `PageUpdate`;
- every standard navigation tool calls `addCurrentLocationToStack` before
  jumping; links pass their exact origin as `{ xpointer, marker_xpointer }`.

A reflowable book is a character offset turned into a page number
(`offset / chars per page`), so changing the characters per page simulates a
repagination. A PDF is a page plus a pan position and a zoom.

## Adding a scenario

Scenarios are plain Lua at the end of `sim.lua`, before the final summary:

```lua
reset(100)          -- start on page 100 with nothing pending
jumpTo(50)          -- an announced jump (like Go to page)
goPage(51)          -- a plain page turn
pa:activate("back") -- tap the arrow
check("description", condition)
```

`followLink(from_offset, to_offset)` follows an internal link with exact
positions; `pg(location)` gives a location's page. When a reported bug can be
reproduced here, add its scenario before fixing it, check that it fails, and
keep it.
