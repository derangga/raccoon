# §2 A — Docs

A Request's notes, written as markdown in a Docs section before Params, drawn with its marks
hidden, like Notion. Decided 2026-11-12.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

```
-> select the Docs section                       the leftmost segment of the Section bar
  -> the Docs pane shows definition.docs         a Request still opens on Params; Docs is
                                                 never selected by itself
```

```
-> type in the Docs editor                       main, per edit
  -> TabModel.edit { $0.docs = text }            the same path as every other field: one undo
                                                 step per typing run, Dirty when it differs
                                                 from the baseline, SessionWriter.schedule()
  -> DocsStyle.ranges(text)                      pure        R: none   E: none, total
                                                 markdown -> [DocsStyleRange]: headings,
                                                 emphasis, strikethrough, inline code, code
                                                 blocks, lists, quotes, links, and the marks
  -> the editor applies them                     R: ThemeEnvironment. Styled text; a `.mark`
                                                 range is hidden (no glyphs), the characters
                                                 stay in the storage
```

```
-> a format command                              ⌘B, ⌘I, ⇧⌘X, ⌘E, ⌘K, ⌥⌘0-3, ⇧⌘7, ⇧⌘8, ⇧⌘9,
                                                 ⌥⌘C, a Docs toolbar button, Return, Delete
  -> DocsEdit.apply(command, text, selection)    pure        R: none   E: none, total
                                                 -> (text, selection)?: adds or removes the
                                                 markdown marks; nil when the command does not
                                                 apply, and the editor does what it does
                                                 by itself (Return inserts a line break)
  -> the editor replaces its text                through shouldChangeText, as typing does: one
                                                 undo step per command, named after it ("Undo
                                                 Bold"); onChange carries it to TabModel.edit
```

```
-> focus the Docs editor (click, Tab)            the Docs toolbar shows at the top of the pane
-> Esc, or focus leaves the editor               the editor resigns; the toolbar hides
```

```
-> ⌘S                                            Save, unchanged (collections.md)
  -> RequestFile.encode                          `docs` is one optional key of the definition,
                                                 omitted when empty (boundary.md)
```

```
-> Postman Import                                postman.md
  -> PostmanMapping: an item's request `description` -> definition.docs
                                                 a string or `{content, type}` object, kept as
                                                 written. No note: nothing is lost. A Folder's
                                                 or the Collection's description is still
                                                 dropped and counted (.descriptionsDropped)
-> Postman Export                                postman-export.md
  -> PostmanExporter: definition.docs -> the item request's `description` (a string),
                                                 written only when not empty
```

**Docs is part of the definition.** It is what the Tab edits, so Dirty, ⌘S, Undo, Duplicate
Tab, the Session and Changed on Disk cover it with no new path. It is never sent: the resolver
does not read it, `ResolvedRequest` drops it, and Copy as Curl and `CredentialScan` never see
it.

**The text is markdown; the editor hides the marks.** What the file holds is markdown,
character for character as the editor's storage holds it. The editor draws it like Notion: a
`.mark` range (`#`, `**`, `*`, `~~`, a backtick, `[` and `](url)`, `> `) gets no glyphs, so
`## Title` shows as a heading with no `##`. Nothing converts markdown to rich text or back:
hiding is a layout decision on the same storage, so nothing is lost on save (decided
2026-11-12, reversing "marks dimmed, never removed"). Typing the marks is the shortcut:
`## ` turns its line into Heading 2 the moment the space is typed, `**b**` turns bold when the
closing `**` is typed. A mark that does not match yet (`**b` alone) shows as text.

**The caret never stops inside a hidden mark.** A selection change that lands inside one moves
to its edge in the direction of travel; at the end of `**bold**` the caret is after the closing
mark, so typing there is plain. Each end of a selection settles the same way. A line's own mark
(`# `, `> `) is never typed before: a caret at its start or inside it rests after it, and Left
from there goes to the end of the line above. After a restyle (an undo, a reload) the caret
settles once the same way. Copy gives the markdown of the selection, marks included.

**Delete never removes a hidden character on its own.** Right after a hidden closing mark,
Delete removes the visible character before it (a whole emoji, not half), and the span's
opening and closing marks too when that empties it. Each span is judged by its own marks, never
by a neighbour's that happens to touch it. While the text and its styling disagree (between an
edit and its restyle, and during input-method composition) nothing is hidden.

**Format commands edit the markdown, through DocsEdit.** Each is one undo step. With a
selection, an inline style (Bold, Italic, Strikethrough, Inline code) wraps it, or unwraps it
when it is already that style; with none, it wraps the word at the caret, and with no word it
inserts the empty pair with the caret between (shown as text until something is typed). A block
style (Normal text, Heading 1-3, Bulleted list, Numbered list, Quote, Code block) sets the
caret's lines: it replaces their line mark, or removes it when they already have that style.
Link asks for the URL in a popover under the selection ("https://", Return applies, Esc
cancels): it wraps the selection as `[text](url)`, or edits the URL when the caret is in a
link, and an empty URL removes the link and keeps its text.

**Return and Delete follow the list.** Return in a list item starts the next one (`- `, or the
next number); Return in an empty item removes its marker and ends the list. Delete at the start
of a heading, list item or quote removes its line mark, so the line becomes Normal text.

**`{{name}}` in Docs is plain text.** It is not highlighted, not counted as an Undefined
Variable, and not shown in the Variables pane: a note may well describe a Variable by name.

**A curl paste keeps Docs.** Curl Import replaces the rest of the definition and leaves `docs`
as the Tab had it (curl.md).

**No images, tables or video.** Links show their text in `accent`, the URL as its tooltip, and
⌘-click opens it in the browser: the editor hit-tests the click, reads the `.link` attribute
the pane sets only where DocsStyle gives an `http`/`https` URL, and opens it. A plain click only
places the caret. Image markdown is its text.
