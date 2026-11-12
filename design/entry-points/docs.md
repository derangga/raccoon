# §2 A — Docs

A Request's notes, written as markdown in a Docs section before Params, styled as they are
typed. Decided 2026-11-12.

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
                                                 emphasis, inline code, code blocks, lists,
                                                 quotes, links, and the marks themselves
  -> the editor applies them                     R: ThemeEnvironment. Styled text, marks in
                                                 `textTertiary`; the characters never change
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

**The text is markdown and it is never rewritten.** What the user typed is what the file holds,
character for character: styling is attributes on the text storage, never a conversion. That
is why the editor is live-styled and not WYSIWYG: hiding the marks would need markdown ↔
attributed-string conversion both ways, and that conversion is where formatting gets lost. The
marks stay on screen in a quieter colour.

**`{{name}}` in Docs is plain text.** It is not highlighted, not counted as an Undefined
Variable, and not shown in the Variables pane: a note may well describe a Variable by name.

**No preview, no links opened, no images.** Links are styled and ⌘-click opens them in the
browser (NSTextView's own link handling, on a `.link` attribute DocsStyle sets only for
`http`/`https`). Images are their markdown text.
