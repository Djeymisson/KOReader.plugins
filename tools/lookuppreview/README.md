# Lookup Preview tools

Tests for [`lookuppreview.koplugin`](../../lookuppreview.koplugin.md). They run
inside a real KOReader (crengine, the real widgets, real gestures, the real
`sdcv` dictionary lookup), without a window, in a temporary profile: your
KOReader settings, history and dictionaries are not touched.

```sh
tools/lookuppreview/run.sh check          # every suite
tools/lookuppreview/run.sh entry scroll   # some of them
tools/lookuppreview/run.sh --help
```

The exit status is 0 when everything passed, 1 when a check failed or a suite
did not finish, so it can gate a commit or a CI job.

## What you need

- A KOReader install that can run on this machine: `/usr/lib/koreader` by
  default, or `--koreader DIR` / `KOREADER_DIR`. On macOS, use the
  `Contents/koreader` folder of `KOReader.app` (GNU `timeout`, from Homebrew's
  coreutils, is used when it is there).
- Nothing else. Every run makes the synthetic StarDict dictionaries of
  [`tools/dictionaryexplorer/fixtures/make.lua`](../dictionaryexplorer/fixtures/make.lua)
  and a small book with words they have (`livro`, `casa`, `house`) and one
  none of them has (`qqqzzzz`). The translation service and Wikipedia are
  replaced by stand-ins (`H.stubOnline`), so no suite needs the network: the
  query a plugin runs in a subprocess under Trapper runs in KOReader's process
  here, so the stand-ins can count the queries.

## The suites

| Suite | What it checks |
|---|---|
| `entry` | How a lookup reaches the carousel, with real gestures on the book: the plugin replaces `ReaderDictionary.showDict` and ReaderHighlight's `lookupDict`, `translate` and `lookupWikipedia`; a long press on a word opens the carousel on the Dictionary card with its entry and no dictionary window; Translate and Wikipedia on a selection open it on their card with one query for the selected text, and nothing else is queried; a tap outside closes it and forgets the lookup; with the preview off, KOReader's own window opens; destroying the plugin puts KOReader's functions back. |
| `dictionary` | The Dictionary card of a carousel opened from Translate or Wikipedia: idle until it is shown, then looked up through KOReader's own lookup (real `sdcv` on the fixtures), with no dictionary window and no "No results" dialog, and without querying Translate again; its button opening KOReader's window on the same word; a word in no dictionary saying so, also with fuzzy search off; closing the carousel while looking up opening nothing when the results arrive; results arriving after swiping away filling the side card; an interrupted lookup offering Retry, which looks up again. |
| `scroll` | Each card keeping where it was scrolled to (with real swipes) while the lookup is open: after going to another card and back; on the side card, in proportion; per dictionary result and per translation language (a new one starting at the top); across a change of appearance (tabs) or dictionary HTML; and a new lookup, even of the same word, starting at the top. |
| `online` | Translate and Wikipedia: queries run under `Trapper:wrap`, as KOReader's own, so a tap can cancel them; the same text looked up again, in a new carousel, answered from the cache with no query, per target language and per Wikipedia language, "nothing found" included; Retry querying again even when cached; a failed query not cached; a cancelled Wikipedia search saying so, with Retry; on "Manual only", a cached answer shown at once and anything else waiting for Load. |
| `vocabulary` | The Dictionary card's Add to vocabulary builder button, on the Vocabulary builder's real database: adding the word, the notification and the button turning into a check mark; a word already there shown in the Vocabulary builder's own dialog and not added twice; no button with the setting off, when the Vocabulary builder adds every word by itself, or when nothing was found. |
| `navigation` | Lookups made inside the carousel, with real gestures: tapping a link of an HTML definition looks its word up only in that dictionary, with no dictionary window, and adds a back button; back showing the previous lookup on the same result and at the same scroll position, without looking it up again; Search acting on the book's selection, and no Note or vocabulary builder button, in a nested lookup; holding a word of the card looking it up (in the dictionary from the Translate card); the edit button asking for another text and looking it up on the same card; two lookups started before the first answers each getting their own results, one after the other, with nothing else opening; closing from a nested lookup closing it all. |
| `reading` | Reading comfort: a real spread expanding the cards and a pinch compacting them, keeping the same proportion of the content in view and inside the screen; the Card height setting, also applied to an open carousel; a larger text size laying the content on more pages; switching to tabs with the carousel open keeping it inside the screen; the source language offered first in the card's language menu and used for the lookup, without changing KOReader's setting; translating the sentence around the selection and going back to the selection from the cache; no sentence in a nested lookup; a hidden card left out of the carousel and its action left to KOReader; hiding the card shown showing the next one, loaded; the card's title being its name with ▾, the word moving to the subtitle, tapping the title opening the list of cards below it, no title with one card shown or with tabs; the chosen card order in the carousel and the card menu; opening on the last card used; Left/Right changing cards and page turn buttons scrolling. |
| `l10n` | The plugin in Brazilian Portuguese (run.sh starts this suite with KOReader in pt_BR): every text the plugin passes to `_()` or `C_()` translated, by `lookuppreview_l10n.lua` or KOReader's catalog, keeping its `%s`/`%d`; the menu, the card's title and the buttons' hints in Portuguese; KOReader's `pt_br` target language shown by its name. |

Run one with `run.sh NAME`; several at once with `run.sh NAME NAME`;
`--keep` keeps the temporary profile (it is printed) to read KOReader's log;
`LP_LANGUAGE=pt_BR` runs the suites with KOReader in that language.

## Adding a check

Suites are plain Lua in `suites/`, run on KOReader's event loop one step after
another (`H.step(delay, fn)`, so the UI gets to run in between). The helpers
are in [`lib/harness.lua`](./lib/harness.lua): `H.lookUpWord(word)` and
`H.holdWord(word)` press on a word of the book, `H.popup()` is the carousel,
`H.status(page)` the load status of a card, `H.activePage()` the page of its
content shown, `H.tapButton(hint)` taps a card's button by the hint it shows
when held. When a reported bug can be reproduced here, add its check before
fixing it, see it fail, and keep it.
