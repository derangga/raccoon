# §2 A — The Gutter and folding

Line numbers beside a body, and folding a Pretty Response the way Postman does.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

```
-> present(response)                             off the main actor, once per Response
  -> ResponseBody.presentation(response)         pure        (sending.md)
  -> LineIndex(text)                             pure        R: none   E: none, total
                                                 of the shown text, and of the bytes as
                                                 text for Raw while Pretty exists
  -> FoldRegion.find(text, lines)                pure, .pretty only    E: none: a body
                                                 that does not nest has no Fold Regions
  -> Highlighter.ranges(text, kind)              pure        (sending.md)
  -> cancel                                      -> propagate: a newer send drops it
```

```
-> draw the body                                 main, when Presented lands or the mode changes
  -> a new NSTextStorage swapped in              FoldSet starts empty
  -> Gutter(lines, regions, folds)               R: ThemeEnvironment
```

```
-> fold or unfold                                a chevron, the … marker, ⌥⌘[ / ⌥⌘],
                                                 Fold All / Unfold All in the context menu
  -> FoldSet.toggle(region) / .innermost(at:)    pure
  -> FoldedText(regions, folds)                  pure: the outermost folded regions, and
                                                 offsets mapped both ways between the
                                                 body and what is shown
  -> the shown text built from the coloured body boundary AppKit
                                                 E: a cut past the body -> DIE
  -> a new NSTextStorage swapped in              the folded line keeps its place on screen
  -> the Gutter redraws
-> Copy                                          ⌘C, or Copy in the context menu
  -> FoldedText.sourceRange(selection)           pure: a selection across a … copies the
                                                 folded lines too
  -> the body's text written to the pasteboard   R: NSPasteboard.general
```

```
-> edit the request body
  -> LineIndex(text)                             pure, main, per edit
  -> Gutter(lines, regions: [], folds: [])       R: ThemeEnvironment
```

**Fold Regions come from indentation, not a parser.** A line opens a Fold Region when the
next line is indented deeper, and the region closes on the first later line indented no
deeper than it. That is only sound because Pretty text is `BodyFormatter`'s output: two
spaces a level, one token per line. Raw is never folded.

**Folding swaps in the shown text; it does not hide text in the layout.** Each Folded
region is cut out of the coloured body and replaced by " … ", and the result is swapped in
as a new storage, as Pretty and Raw are (environment-facts.md, "Folding a large body":
hiding in the layout leaves a 5 MB body a million points tall, or costs seconds). The whole
body stays with the viewer, and `FoldedText` maps offsets between the two, so Copy gives the
body's text, folded lines included, and the Gutter's numbers skip the folded ones (1, 8, 12).

**Fold state is view state.** It belongs to the viewer, not the Tab: every send and every
switch between Pretty and Raw starts with every Fold Region unfolded, and nothing is saved.
