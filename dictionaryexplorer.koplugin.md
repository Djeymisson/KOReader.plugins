# KOReader Dictionary Explorer ![Version](https://img.shields.io/badge/version-v0.1.0-blue)

**Dictionary Explorer** adds a **Go to dictionary** button to KOReader's dictionary popup. It opens the dictionary at the word you looked up, in a full-screen viewer where you can keep paging through the neighbouring entries like a book, similar to the Kindle's "go to dictionary".

The viewer is a plain widget, not a document. Nothing is loaded through the reader, so the dictionary never shows up in **History**, never replaces your "last book" or "Continue reading", and leaves no `.sdr` sidecar folder or reading statistics behind. Closing it puts you right back where you were in your book.

## Requirements

- KOReader **v2026.07 or newer**. The button is added through the dictionary button API introduced in that release ([koreader#15184](https://github.com/koreader/koreader/pull/15184)), which older versions don't have. There, the plugin loads, logs a warning and adds nothing.
- StarDict dictionaries with 32-bit offsets and a `sametypesequence` of `m` (plain text), `h` (HTML) or `x` (XDXF-lite text, as in the Dicionário Aberto), stored as `.dict` or dictzip `.dict.dz`. Other dictionaries simply don't get the button.

## Usage

1. Look up a word in a book as usual.
2. In the dictionary popup, tap **Go to dictionary**. It is added as its own row at the bottom, and you can move or hide it in **Customize buttons** in KOReader's dictionary settings. If you use **Dictionary Preview**, the button is in the full popup that its details button opens, not in the compact preview.
3. The viewer opens on a page with that word's entry in the middle of the screen, highlighted (grey block with a heavy bar on its left), with the entries before and after it around it. A page holds as many consecutive entries as fit on the screen, so you read on through the dictionary rather than one word at a time. **Go to word** and links inside entries centre and highlight their target the same way. To move around:
   - swipe left / right, tap the left or right side of the text, or use the page-turn keys, for the previous / next page (there are no page buttons);
   - scroll the entry with taps on the left / right side of the text, swipes up / down, or the page-turn keys. Reaching the end of a page carries on into the next one, and the start of a page back into the previous one;
   - **Go to word** jumps to any headword (case is ignored; if there is no exact entry, the closest one is shown);
   - **long-press a word** (or drag from the first to the last word of a phrase) to select it. A small dock appears next to the selection: it offers **Go to word**, which jumps to that word's entry (centred and highlighted like any other jump), and **Copy**, which copies the selected text to the clipboard, for a single word as well as for a phrase. For a single word there is a third button, an icon on the left of the other two, that adds the word to KOReader's vocabulary builder (see below); the order is then icon, **Copy**, **Go to word**. The dock sits centred below the selection, or above it when there is no room below inside the text, and disappears when you tap anywhere else (the selection is cleared too). Punctuation around the selection is ignored, and if a multi-word selection is not an entry by itself, **Go to word** uses its first word;
   - tapping a link inside an entry (`bword://…`) jumps to that word;
   - tap the **✕** in the row of buttons at the bottom, or press the Back key, to return to your book.

The header shows, in large bold type, the first and last headword of the page, then the entry numbers ("Entries 14390–14396 of 45866") and, in italics on a line of its own, the name of the dictionary.

### Several entries per page

- When a page has more than one entry, each is introduced by its headword in bold, unless the dictionary already starts its definitions with it (Priberam Portuguese and the Oxford dictionary do).
- Consecutive entries with identical text (Priberam Portuguese stores every inflected form as its own entry, for example `cartadazona`, `cartadazonas`, `cartadinha`) are shown once under a shared heading.
- If keeping the entry centred would leave a lot of the screen empty (the entry on one side is too big to fit), entries are added on the other side instead until the page is full, so the entry may end up nearer the top or bottom.
- The entry is centred as well as the whole entries around it allow: entries are never cut, so a very large neighbour can leave it a little above or below the middle, and near the start or end of a dictionary there is nothing to put above or below it.
- An entry that is longer than the screen on its own (for example `casa` in Priberam Portuguese) takes the whole page, so it can't be centred, and it isn't highlighted since nothing else is on the page; the title names it.
- Very long entries, such as the Oxford entry for `house`, get a page to themselves and scroll.
- How many entries a page holds is measured, not guessed: the page is laid out, and if there is room left, more entries are added, or entries are dropped again if it spills onto a second screen, until it is about 90% full or more. A small model of how tall entries are (fitted by least squares to the heights that were measured, and started from a sample of the dictionary's own text) predicts how many will fit, so that usually a single layout is needed (about 1.5 per page).
- An entry is never split across pages, and a page with several entries never scrolls: only an entry that is longer than the screen on its own gets a scrolling page to itself. When the next entry doesn't fit in what is left, the page simply ends there, so it can have some blank space at the bottom.
- Paging backwards builds the page that ends right before the current one, so pages always follow each other with no entry skipped or repeated. Going back does not necessarily land on the same page boundaries you came forward through.

### Margins

The left and right margins of the book you were reading are applied to the dictionary text, so it lines up with your book. Only EPUB, TXT, HTML and other documents that KOReader lays out itself (crengine) have such margins. For PDF, CBZ and other fixed-layout documents, or when the dictionary is opened from the file browser, a small default margin is used. The title bar and buttons always use the full screen width.

### The buttons at the bottom

One row: **Go to word**, the only bold label, which takes all the width the other buttons leave, and a narrow **✕** that closes the viewer. Once you start walking through words, **‹** (back) and **›** (forward) join it on either side of **Go to word**, giving `‹ | Go to word | › | ✕` (see the breadcrumb below). There are no page buttons: pages turn by swiping left / right on the text, by tapping its left or right side (reaching the end of a page carries on into the next one), or with the page-turn keys.

### The breadcrumb

Once you start walking through the dictionary with **Go to word** (typed, from the selection dock, or by tapping a link inside an entry), a breadcrumb appears at the top of the viewer, right under the header and above the first entry, showing the words you went through, oldest first, with the word you are on in bold (the latest one, until you tap an earlier one):

`… › responsabilidade › gato › mesa › **extraordinariamente**`

- It uses the whole width of the page, with a rule above it that separates it from the entries and one below it that separates it from the buttons. Words that don't fit are replaced by `…`, and the latest word is always shown.
- **Swipe right** on it to see the earlier words (swipe left to come back towards the latest). One word stays in view across each swipe, and tapping a `…` does the same. When a swipe reaches the first word of the trail, the rest of the line is filled with the words that come after it (`responder › aperto › socorro › arroba › pedaço › laranja › …`), so there is never room wasted before the closing `…`.
- **Tap a word** to go to it. It becomes the bold one, and nothing else changes: the same words stay on screen, in the same order, so you can hop back and forth along your path. Which words fit is worked out with the bold width of every word, so bolding a different word never pushes another out of view.
- The buttons **‹** and **›** of the bottom row are Back and Forward. They appear at the same moment as the breadcrumb. **‹** goes to the word before the one you are on, and **›**, after going back, to the word after it: one word at a time, without changing the breadcrumb, where only the bold word moves. If that word would leave the part of the breadcrumb on screen, the breadcrumb slides to keep it in view. **‹** is dimmed on the first word of the trail and **›** on the last.
- Going to a *new* word after stepping back replaces whatever came after the word you were on, like a browser's history: with `casa › livro › amor` and you on `livro`, looking up `zebra` gives `casa › livro › zebra`.
- Paging with the arrows, swiping or scrolling does not change it. The first word is the one the viewer opened on, and the breadcrumb only appears once there are two words. While it is shown, pages have one line less of room for entries.

### The selection dock

The dock is drawn like the toolbar of the Selection Toolbar plugin, so both look alike: the same rounded frame and uniform border, buttons of the same height separated by a light grey rule, and the same dithered shadow along the right and bottom edges. Its text buttons have more room on the sides than that toolbar's icon buttons.

**Add to vocabulary builder.** When KOReader's *Vocabulary builder* plugin is enabled, a selection of a single word also offers an icon button, the first of the dock, that adds it to the builder, the same as the "Add to vocabulary builder" button of the dictionary popup (the word is stored with the title of the book you came from). The icon says what the button will do: `icons/add_word.svg` when the word is not in the builder yet, `icons/remove_word.svg` when it is, in which case tapping it asks for confirmation and removes the word. It is an icon because the full name does not fit next to the other two buttons, especially in Portuguese; **hold it** to see what it does. Adding shows a brief "Added to vocabulary builder." note. With no vocabulary builder, or with a phrase selected, the dock has only Copy and Go to word. The builder's option to store the context of a word is not used here: the viewer has no book sentence to give it.

## Opening from a starting word

You don't need to look a word up in a book first: the dictionary can be opened straight at a word you type.

- From the menu: **Tools > Dictionary Explorer > Open dictionary at a word…** asks for the word (the dictionary it will use is shown under the title) and opens the viewer there, centred and highlighted. If the dictionary has no entry for it, the closest one is shown. It works in the file browser as well, with no book open.
- As a gesture, profile action or Quick Dock button: the same action is registered with KOReader's Dispatcher as **Dictionary Explorer: open at a word**, under **General** in the action lists. Assign it in **Settings > Taps and gestures > Gesture manager** (or in a profile), or pick it in Quick Dock's action picker, like any other KOReader action. Quick Dock shows a two-letter abbreviation for it unless you give it a custom icon in Quick Dock's settings.
- Which dictionary opens is set in **Tools > Dictionary Explorer > Starting dictionary**: **Automatic**, the default, uses the first dictionary that can be opened in KOReader's own dictionary order (the order and the enabled state you set in KOReader's dictionary settings), or you can pick one of the dictionaries that can be opened. A dictionary that is no longer installed falls back to Automatic.

## Settings

Open the top menu and go to **Tools > Dictionary Explorer**:

- **Open dictionary at a word…**: see above.
- **Starting dictionary**: which dictionary that action opens.
- **Show dock shadow**: shows or hides the dithered shadow of the selection dock. It is on by default, and is independent of the Selection Toolbar's own shadow setting.
- **Version**: shows the installed plugin version.

## How it works

`sdcv`, which KOReader uses for lookups, can only answer "what does this word mean?", not "what is the entry after this one?". Dictionary Explorer therefore reads the dictionary's `.idx` itself.

- The first time a dictionary is opened, the `.idx` is scanned once (a notice is shown) and the offset and key of every 64th entry are cached in `cache/dictionaryexplorer/` inside KOReader's data folder. Only those keys and a handful of recently read pages are kept in memory, so dictionaries with hundreds of thousands of entries are fine. The cache is rebuilt automatically if the `.idx` changes.
- Lookups binary-search those keys and read a single 64-entry page. Some dictionaries are not sorted the way the StarDict specification says (the Priberam Portuguese one is in plain byte order), so both orders are tried.
- Definitions are read straight from `.dict`, or from `.dict.dz` by decompressing only the chunks an entry spans.
- Some dictionaries index inflected forms under their own key (Priberam Portuguese has an entry `livro` whose text is the entry for `livrar`). The viewer shows the dictionary's real order, so the title is the index key and the text is whatever the dictionary stores for it.
- Entries are rendered with the dictionary's own `.css` and `.lua` HTML fix, like KOReader's popup. For plain-text dictionaries the basic inline tags (`<b>`, `<i>`, `<big>`, `<small>`…) are kept instead of stripped.

## Performance and battery

- **Nothing runs in the background.** The plugin has no timers, polling or listeners beyond KOReader's own events; when the viewer is closed it costs nothing but the memory of what was loaded (about 60 KB of code and, per dictionary opened, the index below).
- **First use of a dictionary** scans its `.idx` once and caches a compact index (`cache/dictionaryexplorer/`). On a desktop that takes about 70 ms for a dictionary with 860 thousand entries (the time on an e-reader is dominated by reading the file); afterwards loading the cache takes a few milliseconds.
- **Opening the viewer or going to a word** costs a few milliseconds of CPU on a desktop, and a page turn about 2 to 3. The exception is a very long entry (the Oxford entry for `house` has 186 KB of HTML), which takes the layout engine a fraction of a second: the whole entry is laid out.
- **The screen is refreshed once per action** (page turn, Go to word, scrolling the breadcrumb, with no repeated refreshes), which is what an e-ink display costs the most battery for. Closing the viewer does one full refresh, as KOReader does when closing a document.
- While a page is being built, the definitions file is opened once and each entry's HTML is read once, however many layouts are tried; the file and the inflated chunks of compressed dictionaries are released when the viewer closes.

## Known limitations

- The plugin is tested with the dictionaries the author uses (Priberam Portuguese and English–Portuguese, the Oxford English Dictionary 2nd Ed., Dicionário Aberto, a Portuguese–English dictionary and a WikDict English–Portuguese); other StarDict dictionaries of the same shape should work but are untested.
- Type `x` is read as the simple XDXF that StarDict dictionaries use (`<k>` headword, `<b>`, `<i>` ...): the headword is shown in bold and the indentation and blank lines are tidied. Structured XDXF (`<def>`, `<gr>` ... ) is not converted: its tags are dropped and its text is kept.
- Synonym files (`.syn`) are not read: the viewer pages through headwords only.

## Installation

Copy the `dictionaryexplorer.koplugin` folder to KOReader's `plugins` directory and restart KOReader.
