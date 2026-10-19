# Raccoon design system

The visual source of truth for the implementation milestones. Vocabulary is
[CONTEXT.md](../../CONTEXT.md); the surface graph, void states and motion decisions are
[surfaces.md](./surfaces.md); the Theme file is [themes/catppuccin.json](./themes/catppuccin.json);
the mockups are [mockups/](./mockups/) (also on the Claude Design canvas "Raccoon UI").

```
design/ui/
  surfaces.md              surfaces, flow, void states, needs, motion, attention
  design-system.md         this file
  themes/build.py          palette + mapping -> catppuccin.json, and the contrast test
  themes/catppuccin.json   generated; the file the app loads
  mockups/src/*.dc.html    canvas sources (Claude Design artboards) + raccoon.css
  mockups/build.py         src -> self-contained mockups/*.html, Latte and Mocha side by side
```

`python3 -I design/ui/themes/build.py --table` regenerates the JSON and prints the contrast
table below; it exits 1 if any pair fails, so it is the check. `python3 -I
design/ui/mockups/build.py` regenerates the mockups after a source edit.

## 1. The split: native chrome, themed content

| Area | Colors from | Why |
|---|---|---|
| Window, toolbar, sidebar, menus, sheets, alerts, Settings | the system: `NSColor` semantic colors and `NSVisualEffectView` materials. The sidebar is the opaque `windowBackgroundColor`, not a material (decided 2026-10-16): a vibrant material is translucent in a focused window and showed the wallpaper | HIG; follows light/dark and accent by itself. The mockups draw these with `--sys-*` stand-ins, which are not Theme tokens |
| Tab strip, banners in the content area, URL bar, message line, request editor, response viewer, the Variable tooltip | the Theme's tokens | the content areas named in theme.md |
| Inspector (Variables, Curl) | the Theme's tokens, on `backgroundRecessed` like the Response pane | it shows request data: Variable names and values, a curl command with `{{name}}` highlighting |
| Sidebar filter field, the toolbar toggles | the system: `NSSearchField`, toolbar buttons | native controls |
| Method badges in the sidebar | Theme tokens (`method*`) on the opaque sidebar | the badge is content, drawn straight on the sidebar with no chip; contrast measured against the sidebar, see Q3 (decided) |

Both Flavors switch with the system appearance, so chrome and content always agree on light
or dark (theme.md).

## 2. Color tokens

A view asks for a token, never a hex value and never a palette name. The mapping is defined
once by Catppuccin palette name in `themes/build.py` (`MAPPING`) and holds across all four
Flavors, with the exceptions below. The resolved hex of every token in every Flavor, and the
raw palette, are in [themes/catppuccin.md](./themes/catppuccin.md), generated with the JSON.

### Mapping

| Token | Palette name | Drawn as |
|---|---|---|
| `background` | base | the editor, the selected Tab |
| `backgroundElevated` | surface0 (Latte: base) | URL field, method pop-up, banners, popovers, tooltip, segmented controls |
| `backgroundRecessed` | mantle | tab strip, inactive Tabs, Response pane, table header row |
| `border` | surface1 | dividers, field outlines, table rules. Decorative: never the only boundary of a control, which also has a fill |
| `selection` | surface1 (Latte: surface0) | text selection; the selected segment; hover fill of a Tab's close button |
| `rowHover` | surface0 (Latte: mantle) | table row hover, Tab hover |
| `text` | text | body text, values, names |
| `textSecondary` | subtext1 | inactive Tab names, labels, meta (time, size), banner detail, the Ignored note |
| `textTertiary` | subtext0 | placeholders ("Name", "Value"), column headers, counts, line numbers, void-state body text |
| `textDisabled` | overlay2 | Disabled Row name and value, disabled segments ("Pretty" above 5 MB) |
| `textOnAccent` | base | the Send label, primary banner buttons, the checked checkbox's mark |
| `accent` | blue | Send, primary buttons, selected-Tab top rule, active section underline, checked checkbox |
| `focusRing` | blue | the 3 px focus ring on content-area fields (native controls keep the system ring) |
| `methodGet` | green | |
| `methodPost` | peach | |
| `methodPut` | blue | |
| `methodPatch` | mauve | |
| `methodDelete` | red | |
| `methodHead` | teal | |
| `methodOptions` | pink | |
| `methodOther` | subtext0 | any other method (PURGE, PROPFIND): methods are free text (shapes.md) |
| `status1xx` | sky | the status code and reason in the status line |
| `status2xx` | green | |
| `status3xx` | sapphire | |
| `status4xx` | peach | |
| `status5xx` | red | |
| `statusFailed` | red | "Failed" / "Not sent" in the status line, and the error title in the Response pane |
| `jsonKey` | blue | |
| `jsonString` | green | |
| `jsonNumber` | peach | |
| `jsonBoolean` | mauve | |
| `jsonNull` | maroon | |
| `jsonPunctuation` | overlay2 | braces, brackets, colons, commas, and `=` between XML attributes |
| `xmlTag` | blue | `<tag>`, `</tag>`, `<`, `>` |
| `xmlAttribute` | yellow | |
| `xmlValue` | green | attribute values |
| `variableDefined` | blue | `{{name}}` that resolves; no underline |
| `variableSecret` | mauve | `{{name}}` that resolves to a Secret Variable; plus a dotted underline |
| `variableUndefined` | red | `{{name}}` that does not resolve; plus a wavy underline |
| `dirtyDot` | peach | the 8 px dot in a Tab's close slot |
| `warning` | yellow | Changed on Disk / Deleted on disk glyph, the unreadable-row glyph |
| `error` | red | error message lines, error banner glyph, missing-file chip, invalid URL outline |
| `success` | green | **no v1 surface uses it** (Q6, decided) |

`methodPut`, `jsonKey`, `xmlTag`, `variableDefined`, `accent` and `focusRing` share blue, and
the greens are shared too. They never sit side by side in a way that needs them told apart:
a key and a Variable never share a field, and a defined Variable is told from an undefined
one by its underline as well as by hue.

### Flavor exceptions

| Flavor | Token | Mapping instead | Why |
|---|---|---|---|
| Latte | `backgroundElevated` | base | Latte has nothing lighter than base, so an elevated surface cannot be lighter than the editor. It stays base and is lifted by `border` plus a 0.5 px + 1 px shadow (`--elevatedShadow` in the mockups) |
| Latte | `rowHover` | mantle | surface0 is darker than the selected-segment fill and read as selection |
| Latte | `selection` | surface0 | surface1 on base drops `text` to 3.9:1 |

### The adjustment rule

Many Catppuccin accents are pastel, by design, and fail 4.5:1 as small text, most of all in
Latte. When a token fails on any background it is drawn on, `build.py` moves its HLS
lightness away from the background in 2 % steps (darker in Latte, lighter in the dark
Flavors) until every pair passes. Hue and saturation stay Catppuccin's. Every moved token is
listed in the table as `L-n%` / `L+n%`, so nothing is chosen silently. The JSON holds the
adjusted hex; the mapping above still names the palette color it came from.

`accent` is the one token adjusted for a foreground: it darkens until `textOnAccent` passes
on it, and `focusRing` takes the same value.

`selection` is checked only against `text`: NSTextView draws selected text in `text` through
`selectedTextAttributes`, so syntax and Variable colors never sit on `selection`. The
implementation must set that attribute or this result does not hold.

### Contrast results

Minimum ratio per token across every background it is drawn on, per Flavor, with the worst
background named. 4.5 for text (including 11 pt bold method badges, which are not "large"),
3.0 for UI glyphs (`accent` fill, `focusRing`, `dirtyDot`). `sidebar` is the estimated native
material (Q3); the measured sidebar passes too (Q3, decided). Every pair passes in all four Flavors.

| Token | Palette | Min | Latte | Frappé | Macchiato | Mocha |
|---|---|---|---|---|---|---|
| `text` | text | 4.5 | 5.17 on selection | 4.68 on selection | 5.59 on selection | 6.31 on selection |
| `textSecondary` | subtext1 | 4.5 | 5.14 on backgroundRecessed | 5.19 on backgroundElevated | 6.22 on backgroundElevated | 7.10 on backgroundElevated |
| `textTertiary` | subtext0 | 4.5 | 4.65 on backgroundRecessed, L-4% | 4.56 on backgroundElevated, L+2% | 5.03 on backgroundElevated | 5.65 on backgroundElevated |
| `textDisabled` | overlay2 | 4.5 | 4.66 on backgroundRecessed, L-10% | 4.54 on backgroundElevated, L+8% | 4.59 on backgroundElevated, L+4% | 4.78 on backgroundElevated, L+2% |
| `textOnAccent` | base | 4.5 | 4.66 on accent | 5.34 on accent | 6.57 on accent | 7.79 on accent |
| `accent` | blue | 3.0 | 4.66 on background, L-2% | 4.10 on backgroundElevated | 4.99 on backgroundElevated | 5.97 on backgroundElevated |
| `focusRing` | blue | 3.0 | 4.33 on backgroundRecessed | 4.10 on backgroundElevated | 4.99 on backgroundElevated | 5.97 on backgroundElevated |
| `methodGet` | green | 4.5 | 4.98 on sidebar, L-12% | 5.45 on backgroundElevated | 6.98 on backgroundElevated | 8.46 on backgroundElevated |
| `methodPost` | peach | 4.5 | 4.92 on sidebar, L-18% | 4.68 on backgroundElevated, L+2% | 5.79 on backgroundElevated | 7.10 on backgroundElevated |
| `methodPut` | blue | 4.5 | 4.58 on sidebar, L-4% | 4.73 on backgroundElevated, L+4% | 4.99 on backgroundElevated | 5.97 on backgroundElevated |
| `methodPatch` | mauve | 4.5 | 4.76 on sidebar, L-2% | 4.61 on backgroundElevated, L+2% | 5.21 on backgroundElevated | 6.19 on backgroundElevated |
| `methodDelete` | red | 4.5 | 4.80 on sidebar, L-2% | 4.73 on backgroundElevated, L+8% | 4.54 on backgroundElevated | 5.43 on backgroundElevated |
| `methodHead` | teal | 4.5 | 4.76 on sidebar, L-8% | 4.93 on backgroundElevated | 6.65 on backgroundElevated | 8.44 on backgroundElevated |
| `methodOptions` | pink | 4.5 | 4.53 on sidebar, L-26% | 5.78 on backgroundElevated | 7.10 on backgroundElevated | 8.23 on backgroundElevated |
| `methodOther` | subtext0 | 4.5 | 4.62 on sidebar, L-4% | 4.56 on backgroundElevated, L+2% | 5.03 on backgroundElevated | 5.65 on backgroundElevated |
| `status1xx` | sky | 4.5 | 4.88 on backgroundRecessed, L-16% | 7.33 on background | 9.14 on background | 10.54 on background |
| `status2xx` | green | 4.5 | 4.50 on backgroundRecessed, L-10% | 7.10 on background | 9.17 on background | 11.03 on background |
| `status3xx` | sapphire | 4.5 | 4.65 on backgroundRecessed, L-12% | 6.25 on background | 7.63 on background | 8.69 on background |
| `status4xx` | peach | 4.5 | 4.52 on backgroundRecessed, L-16% | 5.80 on background | 7.62 on background | 9.27 on background |
| `status5xx` | red | 4.5 | 4.83 on backgroundRecessed, L-2% | 4.65 on background | 5.96 on background | 7.08 on background |
| `statusFailed` | red | 4.5 | 4.83 on backgroundRecessed, L-2% | 4.65 on background | 5.96 on background | 7.08 on background |
| `jsonKey` | blue | 4.5 | 4.61 on backgroundRecessed, L-4% | 5.34 on background | 6.57 on background | 7.79 on background |
| `jsonString` | green | 4.5 | 4.50 on backgroundRecessed, L-10% | 7.10 on background | 9.17 on background | 11.03 on background |
| `jsonNumber` | peach | 4.5 | 4.52 on backgroundRecessed, L-16% | 5.80 on background | 7.62 on background | 9.27 on background |
| `jsonBoolean` | mauve | 4.5 | 4.79 on backgroundRecessed, L-2% | 5.60 on background | 6.84 on background | 8.07 on background |
| `jsonNull` | maroon | 4.5 | 4.70 on backgroundRecessed, L-14% | 5.59 on background | 6.80 on background | 7.93 on background |
| `jsonPunctuation` | overlay2 | 4.5 | 4.66 on backgroundRecessed, L-10% | 4.53 on background | 5.29 on background | 5.81 on background |
| `xmlTag` | blue | 4.5 | 4.61 on backgroundRecessed, L-4% | 5.34 on background | 6.57 on background | 7.79 on background |
| `xmlAttribute` | yellow | 4.5 | 4.77 on backgroundRecessed, L-18% | 7.62 on background | 10.20 on background | 12.91 on background |
| `xmlValue` | green | 4.5 | 4.50 on backgroundRecessed, L-10% | 7.10 on background | 9.17 on background | 11.03 on background |
| `variableDefined` | blue | 4.5 | 4.61 on rowHover, L-4% | 4.73 on backgroundElevated, L+4% | 4.99 on backgroundElevated | 5.97 on backgroundElevated |
| `variableSecret` | mauve | 4.5 | 4.79 on rowHover, L-2% | 4.61 on backgroundElevated, L+2% | 5.21 on backgroundElevated | 6.19 on backgroundElevated |
| `variableUndefined` | red | 4.5 | 4.83 on rowHover, L-2% | 4.73 on backgroundElevated, L+8% | 4.54 on backgroundElevated | 5.43 on backgroundElevated |
| `dirtyDot` | peach | 3.0 | 3.23 on backgroundRecessed, L-8% | 4.45 on rowHover | 5.79 on rowHover | 7.10 on rowHover |
| `warning` | yellow | 4.5 | 4.77 on backgroundRecessed, L-18% | 5.85 on backgroundElevated | 7.76 on backgroundElevated | 9.89 on backgroundElevated |
| `error` | red | 4.5 | 4.83 on backgroundRecessed, L-2% | 4.73 on backgroundElevated, L+8% | 4.54 on backgroundElevated | 5.43 on backgroundElevated |
| `success` | green | 4.5 | 4.50 on backgroundRecessed, L-10% | 5.45 on backgroundElevated | 6.98 on backgroundElevated | 8.46 on backgroundElevated |

Two consequences worth knowing:

- **Latte's text ramp is compressed.** `textTertiary` (#63667a) and `textDisabled` (#636679)
  come out equal, and `textSecondary` is close to both, because subtext0 and overlay2 must
  darken to pass on mantle. Disabled Rows still differ from normal rows by being unchecked
  (and from `text`), which is the cue that matters. Placeholders and Disabled Rows never share
  a row with different meanings, so the equality is accepted.
- **Latte `methodOptions` moved 26 %**, the largest shift, because pink is the lightest
  accent and the sidebar estimate is darker than base.

## 3. Typography

| Role | Font | Size / weight | Where |
|---|---|---|---|
| Body | SF Pro (system) | 13 pt regular | labels, Tab names, banners, sheets, menus |
| Secondary | SF Pro | 11 pt regular | message line, column headers, hints, sidebar sub-rows |
| Section labels | SF Pro | 11 pt semibold | "Collections", card labels |
| Emphasis | SF Pro | 13 pt semibold | active section name, banner lead ("Changed on Disk."), void-state titles |
| Code | SF Mono | 12 pt regular | URL field, table cells, bodies, responses, headers |
| Method badge | SF Mono | 10 pt (Tab), 9.5 pt (sidebar), 12 pt (URL bar), bold, +0.02 em | |
| Status code | SF Mono | 12 pt bold, tabular figures | status line |
| Meta numbers | SF Pro | 12 pt, tabular figures | time, size, counts: they update and must not jitter |

Text never moves its baseline between states: italic for a Draft, weight for the active
section, never a size change. Leading is the system default for 13 pt (≈ 18 px) and 18 px for
SF Mono 12 pt in the code views.

## 4. Spacing and sizing

A 4 pt base. Sizes used: 2, 4, 6, 8, 10, 12, 16, 24.

| Element | Size |
|---|---|
| Toolbar (unified title bar) | 52 pt |
| Sidebar width | 232 pt default, 180 min, 360 max (NSSplitView) |
| Sidebar filter field | 24 pt, 6 pt radius, full sidebar width minus 20 pt |
| Inspector width | 280 pt default, 240 min, 400 max; closed by default |
| Inspector rows | 24 pt min, name column 46 %; group title 11 pt semibold |
| Sidebar row | 24 pt, 6 pt radius selection, 16 pt indent per level |
| Tab strip | 34 pt |
| Tab | 104 pt min, 196 pt preferred, selected 168 pt min; 10 pt leading, 6 pt trailing |
| URL bar row | 30 pt controls, 10 pt top / 6 pt bottom, 8 pt gaps, 12 pt sides |
| Method pop-up | 84–128 pt wide |
| Send button | 76 pt min |
| Message line | 16 pt line height, indented to the URL field's leading edge (104 pt) |
| Section bar | 28 pt, 2 pt accent underline |
| Key/value row | 28 pt; header 24 pt; columns 30 pt / 36 % / rest / 30 pt |
| Status line | 34 pt |
| Banner | 36 pt min, grows to two lines |
| Split handle | 6 pt hit area, 32 × 3 pt grip |
| Radii | 4 pt small controls and chips, 6 pt fields and buttons, 8 pt cards and menus, 10 pt window |

## 5. Motion

Decided per motion in [surfaces.md §7](./surfaces.md#7-behavior-motion-decisions-from-animate):
Tabs and the Pretty/Raw switch do not animate; the spinner is the system one after 150 ms;
banners use a 200 ms ease-out `NSAnimationContext` group (150 ms out), reduced to an opacity
cross-fade under Reduce Motion. Nothing else in v1 moves. Hover and press states change on
the same frame, with no transition, because they are seen tens of times a minute.

## 6. Components

Tokens in `code`. "Seen on" names the mockup.

### Tab

Anatomy: `[state glyph or Draft dot] [method badge] name [slot]`, slot 16 × 16 at the trailing edge.

| State | Treatment |
|---|---|
| rest | `backgroundRecessed`, name `textSecondary`, 1 pt `border` on the right |
| hover | `rowHover`; the slot shows the close button (✕ on `selection`) |
| selected | `background`, name `text`, 2 pt `accent` rule on top, joins the editor (no bottom border) |
| Dirty | the slot shows an 8 pt `dirtyDot`; hover swaps it for ✕ (the macOS document convention) |
| Draft | a 6 pt `accent` dot before the method badge, and the name in **italic**: the empty Draft reads "Draft", otherwise its URL path. The dot is the cue in scripts without a true italic (CJK), see Q4 |
| sending | the method badge is replaced by the 12 pt system spinner after 150 ms. The method is still in the URL bar of the selected Tab |
| Changed on Disk | a 12 pt `warning` triangle before the badge, and the Dirty dot (it is always Dirty) |
| close | ✕ 16 pt, `textSecondary`; ⌘W |
| 30 Tabs | Tabs keep 104 pt; the strip scrolls horizontally with 24 pt fade masks at each edge; the selected Tab is scrolled into view on select |

Accessibility: each Tab is an `NSAccessibility` tab with title "<method> <name>", value
"Edited", "Draft", "Sending", "Changed on Disk" as applicable. Seen on: 05, 10.

### URL bar

Anatomy: `[method pop-up] [URL field] [Send]`, then the message line.

- **Method pop-up**: `backgroundElevated`, `border`, the method in its `method*` token, SF Mono
  12 bold. The menu lists GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS and nothing
  else. A method that arrived from a curl import or a Postman file is shown as it is and
  stays until another is picked.
- **URL field**: `backgroundElevated`, `border`, SF Mono 12, one line, scrolls horizontally;
  32 pt fade at the trailing edge when it overflows. Focus: `focusRing` border + 3 pt ring at
  35 %. Invalid after an `invalidURL` send: `error` border until the next edit. The query part
  is rendered from Params; `?`, `=`, `&` in `textSecondary`.
- **`{{name}}` highlighting** in the URL field, table cells, body text and Auth fields:
  defined `variableDefined`; secret `variableSecret` + dotted underline; undefined
  `variableUndefined` + 1 pt wavy underline. Hover shows the Variable tooltip. Inside a
  Disabled Row all three are drawn in `textDisabled` (the row is not sent, so it is not
  resolved).
- **Send**: `accent` fill, `textOnAccent` label, 76 pt min. While sending it becomes
  **Cancel**: `backgroundElevated`, `border`, `text`. ⌘↩ sends, ⌘. cancels. A second ⌘↩
  while sending does nothing (behavior.md).
- **Message line**: 11 pt, a 12 pt glyph, indented to the URL field. Error (`error`, ⓘ-in-a-
  circle-with-bang): Curl Import `unterminatedQuote` with the character position, `noURL`,
  and "Not sent. `a` and `b` are not defined in <Environment> or in Globals." Note
  (`textSecondary`, ⓘ): "Ignored: `--retry`, `-s`", "2 more commands", unreadable or binary
  `@file`. The note has a ✕ and goes away on the next URL edit; errors go away on the next
  paste or send.

Seen on: 01, 03, 04, 09, 10.

### Section bar

Params · Headers · Body · Auth · Cookies · Settings over the RequestEditor's pane, 28 pt each,
13 pt `textSecondary`, 10 pt padding, 2 pt apart, over a 1 pt `border` rule. Selected: `text`
semibold with a 2 pt `accent` underline over the rule. Params, Headers and Cookies carry their
row count in tabular `textTertiary` ("Params 3", Disabled Rows included); a section with no rows
shows no count. Auth shows its scheme ("Auth Bearer"). Body shows nothing more: the Body Type
pop-ups in its pane already name it.
Seen on: 01, 02, 05.

### Key/value table

Shared by Params, Headers, Cookies, form-urlencoded and multipart.

Anatomy: header row (24 pt, `backgroundRecessed`, `textTertiary` 11 semibold "Name" "Value"),
then 28 pt rows: `[checkbox 30] [name 36 %] [value] [delete 30]`, 1 pt `border` between rows,
one vertical rule between Name and Value, 6 pt radius outer border.

| State | Treatment |
|---|---|
| rest | cells SF Mono 12 `text`, single line, end-truncated with the full value in the field editor and a tooltip |
| hover | `rowHover`; the delete button (⊖, `textTertiary`) appears |
| selected | `selection` fill, not the system accent; name and value keep their own colors. An automatic row is never selected |
| editing | the cell becomes a field editor with a 2 pt `focusRing` outline on `background` |
| Disabled Row | checkbox **unchecked** and name/value in `textDisabled`. Both cues, never one |
| trailing empty row | always present, last; "Name" / "Value" placeholders in `textTertiary` at 60 % opacity, SF Pro 13 (at full strength Latte's `textTertiary` reads as a value); typing in it creates a row and a new trailing row |
| 60 rows | the table scrolls inside the pane; the header row stays put; an overlay scroller |
| automatic row | Headers only, above the user's rows (the trailing empty row is always last): the headers sent that no row sets (`AutomaticHeaders`), name and value in `textTertiary`, a checked checkbox that is disabled (sent whatever the user does, so it cannot be unticked; tooltip "Always sent. Add a row with the same name to replace it."), no delete, not editable, not selectable. A value computed at send reads "calculated when sent". Typing a row with the same name replaces it; the section count leaves them out. Not drawn on a board yet |

The section label carries the count of rows ("Headers 60"), `textTertiary`, tabular. A count
holding an Undefined Variable is drawn in `variableUndefined` semibold, so the reason a send
is blocked is visible from another section. Seen on: 02, 04, 05, 10.

### Body editor

- **Body Type** pop-up: none · raw · form-urlencoded · multipart. When raw, a second pop-up:
  JSON · text · XML. Switching follows editing.md's conversion table; the Content-Type row it
  writes appears in Headers like any other row.
- **none**: "This request has no body." in `textTertiary`, centred.
- **raw**: an NSTextView in SF Mono 12, `background`, `border`, line numbers in
  `textTertiary`, syntax colors for JSON and XML (the same tokens as the response viewer),
  `{{name}}` highlighting on top.
- **Format** (raw JSON and XML only; hidden for text, none, form and multipart): a bordered
  button with a list glyph at the trailing end of the Body Type row, tooltip "Format JSON
  (⇧⌥F)". It re-indents with 2 spaces in one undo step, keeps key order, number spelling and
  every `{{name}}` as typed (editing.md). If the body does not parse, the text is left alone
  and one 11 pt `error` line under the editor says where: "Couldn't format: not valid JSON
  at line 3, column 14." The line goes away on the next edit. Seen on: 03.
- **form-urlencoded**: the key/value table.
- **multipart**: the key/value table, where a value is text or a **file chip**: 20 pt,
  `backgroundRecessed`, `border`, a document glyph and the file name (full path in the
  tooltip). A file that is missing at send: chip in `error` border and text with a warning
  glyph, and the message line "Not sent. `<path>` is missing." The Value placeholder reads
  "Value or file"; dropping a file onto a row or choosing "Choose File…" from the row's menu
  makes it a file part.

Seen on: 03, 05, 09.

### Auth section

A three-segment control: None · Basic · Bearer.

- None: "No Authorization header is added." `textTertiary`.
- Basic: Username and Password fields (Password is a secure field showing its `{{name}}` if it
  holds one, otherwise bullets).
- Bearer: one Token field, SF Mono.

Fields are 26 pt, `backgroundElevated`, `border`, labels right-aligned `textSecondary`. The
section label carries the scheme: "Auth Bearer". Seen on: 03 (label), 09.

### Request Settings

Two checkboxes, each with a one-line hint in `textTertiary`:
"Allow insecure TLS" (hint: "Accept certificates the system does not trust, for this Request
only.") and "Follow redirects". There is no compression checkbox: URLSession always asks for
and decodes gzip (environment-facts.md, Open UI question 10). Seen on: 06.

### Response viewer

Anatomy: status line (34 pt) over the body area, on `backgroundRecessed`.

- **Status line**: status code + reason in `status1xx`…`status5xx`, SF Mono 12 bold, single
  line, the reason end-truncates first (the code never does); then elapsed time and size in
  `textSecondary` with tabular figures, separated by a `textTertiary` middle dot. Trailing:
  Pretty | Raw, then Body | Headers N.
- **idle**: "Send a request to see the Response here." `textTertiary`, with a ⌘↩ key cap.
- **sending**: spinner + "Sending… 1.4 s", the time live; body: "Waiting for the server. ⌘.
  cancels."
- **received**: Pretty (parsed JSON/XML, syntax tokens) or Raw (no colors). Raw shows first
  while Pretty is computed off the main thread (behavior.md). Above 5 MB Pretty is disabled
  (`textDisabled`) with "Pretty is off above 5 MB" beside it.
- **Gutter**: left of the body text in Pretty and Raw, drawn on the body's own background
  with no fill and no divider; 50 pt, wider when the last line number needs it (a 5 MB body
  passes 200,000 lines). Line numbers SF Mono 12, `textTertiary`, right-aligned; then a
  16 pt fold column; then the text. In Pretty JSON and XML the fold column holds a 9 pt
  chevron in `textTertiary` beside every line that opens a Fold Region, pointing down when
  unfolded, right when folded. Unfolded chevrons show only while the pointer is over the
  Gutter; folded ones always show. Clicking a line's number or chevron folds or unfolds.
  The request body has the same Gutter, numbers only. The Gutter is empty until the
  off-main presentation lands.
- **Indent guides**: in Pretty, a 1 pt vertical line in `border` for every unfolded Fold
  Region, at the column where its opening line's text starts, from the line under the
  opening line down to the closing line.
- **Folded**: the opening line ends in a " … " marker, the `…` in `textSecondary` on
  `selection`, then the closing token on the same line: `"rating": { … },`. Clicking the
  marker unfolds. Numbers skip the hidden lines (1, 8, 12). Context menu: Fold ⌥⌘[, Unfold
  ⌥⌘] (the Fold Region at the caret), Fold All, Unfold All. Every send starts unfolded. Copy gives the
  body's text: a selection across a marker copies the folded lines.
- **failed**: status line "Failed" + "after N ms" in `statusFailed`; body: an error glyph, a
  title in `statusFailed` 13 semibold, one sentence of detail in `textTertiary`, and the
  single fix as a button when one exists. Titles: "Untrusted certificate" (names the host;
  button "Allow insecure TLS for this request", which flips the Request Setting and does not
  send), "No response after 60 s", URLError's description plus the code and host for
  transport errors, "Invalid URL" quoting the URL after substitution (status line "Not sent").
- **binary**: "Binary body", then "48.2 KB that is not UTF-8 text. Raccoon shows text bodies
  only."
- **empty body** (0 B): "Empty body." Status line unchanged.
- **Headers**: two columns, name `textSecondary`, value `text`, SF Mono 12, end-truncated
  with the full value in a tooltip. Wire order and duplicates are gone before Raccoon sees
  them (environment-facts.md), so rows are sorted by name (as the transport returns them), and two
  Set-Cookie headers are one row with the values joined by `, `. Under the last row, always:
  "macOS merges repeated headers and doesn't keep their order." in `textTertiary`, 11 pt.

Seen on: 01, 02, 04, 06, 09, 10.

### Sidebar rows (native)

NSOutlineView, source-list style, on the sidebar material. 24 pt rows, `sys` label colors.

- **Collection**: disclosure, a stacked-layers glyph, the name.
- **Folder**: disclosure, folder glyph, name. 16 pt indent per level.
- **Request**: the method badge (52 pt, right-aligned, end-truncated: `PROPFIND` fits,
  longer methods get an ellipsis) then the name, end-truncated.
- **Unreadable**: a `warning` triangle, the **file name** (not a Request name: there isn't
  one), in secondary label color, and an icon-only Reveal in Finder button (20 × 18,
  `aria-label`/tooltip "Reveal in Finder"). Beneath, an 11 pt line with the reason: "Not
  valid JSON at line 14. Raccoon won't change this file.", "Unknown file version 3.", "Same id
  as List refunds.json." Selecting it shows nothing in the editor; double-click reveals.
- **Empty**: "No Collections yet. Create one, or save a Draft into one with ⌘S." plus the Data
  Folder path in SF Mono 11.

Seen on: 01, 02, 09, 10.

### Banners

In the content area, under the tab strip and above the URL bar, so they belong to the Tab
whose state they describe. 36 pt min, `backgroundElevated`, `border` bottom, a 16 pt glyph,
a bold lead sentence and detail in `textSecondary`, buttons trailing.

| Banner | Glyph | Text | Buttons |
|---|---|---|---|
| Changed on Disk | `warning` | "**Changed on Disk.** <file> was changed outside Raccoon. Your edits are kept until you choose." | Keep Mine · **Reload** (primary) |
| Deleted on disk | `warning` | "**Deleted on disk.** <file> is gone. This Tab is now a Draft with your content, and ⌘S saves it again." | Dismiss |
| Not saved (write failed) | `error` | "**Not saved.** Couldn't write <file>: <reason>. The Tab keeps your edits." | Dismiss |
| Data Folder not writable | `error` | "**Raccoon can't write to the Data Folder.** <path> is read-only. Collections are unavailable; Drafts and sending still work." | **Choose Folder…** |

The Data Folder banner is the one global surface: it spans the whole window under the
toolbar, above sidebar and content, because it is the only failure with no smaller place
(e-where-it-breaks.md). Seen on: 05, 09.

### Environment picker

A native pop-up button in the toolbar, labelled "Environment", showing the Active Environment
or "No Environment". Menu: No Environment, a separator, each Environment by name with a check
on the active one, a separator, "Edit Environments…" (⌃E opens the menu; ⌥⌃E opens the sheet,
Q5). Long names end-truncate at 200 pt; the menu shows them in full. Seen on: every screen.

### Environments sheet (native)

680 × 430 sheet. Left: a source list with Globals, an "Environments" header and each
Environment; the active one has a check; + and − under it. Right: the selected set's name and
a table `[enabled] [Name] [Value] [Secret]`, SF Mono 12, with the trailing empty row and
Disabled Rows (unchecked, secondary label color).

- **Secret toggle**: a lock button per row. Off: open lock, secondary color. On: closed lock,
  pressed fill, the value becomes a secure field showing bullets. Turning it on writes the
  Keychain first, then rewrites the file without the value (variables.md order).
- **Keychain write fails**: the row stays as it was, and an 11 pt system-red line beneath it
  reads "Not saved. The Keychain refused the write (OSStatus −25308, …)." The file is not
  touched.
- **Keychain unreadable** for a secret: the value field reads "Not in the Keychain", and the
  Variable resolves as undefined everywhere else (one path, §4).
- Footer hint: "<Env> overrides Globals while it is the Active Environment. Secret values are
  kept in the Keychain; only their names are written to the Data Folder." Done closes.

Seen on: 07, 09.

### Save Draft sheet (native)

"Save Request", Name field (focused, prefilled with nothing), Location pop-up listing
Collections and Folders as a path ("Payments API ▸ Webhooks", default: the last one used), and
Cancel · **Save**. With no Collections the pop-up offers "New Collection…". Seen on: 09.

### Close confirmation (native)

An `NSAlert` sheet on the window (Open UI Q8), shown when closing a Tab with losable content
(a Dirty Tab or a non-empty Draft). Message: "Close “<name>” without saving?", where the name
is the one the Tab shows. Informative text: for a Draft "This Draft hasn't been saved. Its
request will be lost."; for a Dirty Tab "Your edits to this Request haven't been saved and
will be lost." Buttons: Don't Save (destructive, red, ⌘D), then Cancel (Esc). Return does
nothing, so no key a hand rests on discards work. There is no Save button until the
Collections epic writes Requests; it then adds Save, which saves and closes. Cancel and Esc
keep the Tab and give focus back to where it was. The alert shows the app icon once Raccoon
has one. Not drawn.

### Postman Import sheet (native)

Opened by File ▸ Import from Postman… (⇧⌘I) or Import from Postman… in the sidebar's +
menu, after an open panel that takes one or many `.json` files. 620 pt wide. Behaviour and
the full mapping: [design/entry-points/postman.md](../entry-points/postman.md).

- **One row per file**, 38 pt: a checkbox, a kind glyph (Collection, Environment, Globals),
  the name in semibold, and under it what it holds ("Collection · 48 Requests in 6 Folders",
  "Environment · 12 Variables, 2 secrets", "Globals · 4 new · 1 kept as it is in Raccoon").
  The source file name is trailing, in secondary label color. A taken name reads
  "Prod → Prod 2" with "'Prod' already exists". A file Raccoon can't read is a disabled row:
  "Not a Postman export Raccoon reads".
- **What won't come across**: one line per ImportNote, with a count and, under it, the
  Requests it applies to (11 pt, at most one line, then "and 12 more"). Warnings (orange
  triangle) for losses: scripts, unsupported Auth, binary bodies, dynamic variables, file
  parts with only a name. Info (ⓘ) for changes that keep meaning: inherited Auth copied,
  Collection variables added to Globals, path variables written into the URL.
- **Footer**: "Imports into ~/Raccoon. Secrets go to the Keychain." and Cancel · **Import**.
  Import is disabled when nothing is ticked or the Data Folder is not writable (the footer
  then says why).
- **Result** (the same sheet, replaced): "Imported 2 of 3", a check per landed item, and per
  failure a red line saying what was not written and that nothing of it was left behind; a
  Keychain refusal is an orange line. Done closes it and reveals the first imported
  Collection, selected, in the sidebar. If everything landed, the sheet closes straight away
  instead.

Seen on: 12.

### Variable hover tooltip

A small popover on `backgroundElevated` with `border`, 11 pt, appearing after the system
tooltip delay and instantly for the next token while one is open:
- defined: **name** · <Environment or Globals>, then the value in SF Mono, wrapping anywhere;
- secret: **name** · <source>, then "Secret". The value is never shown;
- undefined: **name**, then "Not defined in <Environment> or Globals" in `variableUndefined`.

Seen on: 02, 09.

### Toolbar toggles

The sidebar toggle sits at the leading edge of the toolbar and the inspector toggle at the
trailing edge, as in Finder and Xcode: native toolbar buttons with SF Symbols
`sidebar.left` and `sidebar.right`, pressed (filled background) while their pane is open.
Both have View-menu items, "Show Sidebar" / "Show Inspector" (shortcuts: Q12). Seen on: every
screen; pressed on 04 and 11.

### Sidebar filter (native)

An `NSSearchField` at the top of the sidebar, above "Collections", placeholder "Filter
Collections". Hidden while there are no Collections (screen 1).

- Filters as you type, no debounce, over Request, Folder and Collection names, case- and
  diacritic-insensitive. A node stays if it or an ancestor matches; ancestors open.
  Unreadable rows match by file name.
- The match is highlighted with the system find-highlight color **and** set semibold, so it
  is not shown by color alone.
- Under the field, an 11 pt count in secondary label color: "4 matches in 1 Collection".
- No matches: "No Requests, Folders or Collections match “refnd”. Esc clears the filter."
- The clear button (ⓧ) and Esc restore the tree and the expansion state from before.
- Clicking a match opens it; the filter stays until cleared.

Seen on: every screen with Collections; active on 11.

### Inspector

A right-hand pane, `NSSplitViewItem(inspectorWithViewController:)`, themed:
`backgroundRecessed`, 1 pt `border` on its leading edge, closed by default. A 34 pt header
(aligned with the tab strip) holds the pane's name on the left (12 pt semibold `text`) and,
on the right, a two-segment icon control: `curlybraces` for Variables and `terminal` for
Curl (SF Symbols), 30 × 22 pt each, the selected one on `selection`. Each segment has a
tooltip and an accessibility label with the pane's name. The last choice is remembered
(Q14).

**Variables pane** (read-only; seen on 04, 11):
- Group titles 11 pt semibold `textTertiary`; rows 24 pt, name SF Mono 12 `text`, value SF
  Mono 12 `textSecondary`, end-truncated with the full value in a tooltip.
- Order: **Not defined** first, only when the Tab uses a name nothing defines: a
  `variableUndefined` title with an error glyph, each name in `variableUndefined` with its
  wavy underline and where the Tab uses it ("URL", "Headers", "Body", "Auth"). Then the
  **Active Environment** ("Staging · Active Environment"), names this Tab uses first. Then
  **Globals**, where an entry the Environment overrides is struck out in `textDisabled`.
- A Secret Variable's value is a lock glyph and "Secret" in `variableSecret`.
- No Environment: the group reads "No Environment · pick one in the toolbar"; Globals follow.
- Footer: **Edit Environments…** opens the Environments sheet on the active set.

**Curl pane** (seen on 11):
- The curl command for the selected Tab, as Copy as Curl renders it, in SF Mono 11 / 17 on
  `background` inside a 6 pt-radius `border` box. Flags in `textSecondary`, values in `text`,
  a Secret Variable as `{{name}}` in `variableSecret` with its dotted underline. Wraps
  anywhere and scrolls; it never truncates, because Copy must match what is shown.
- Under it, 11 pt `textTertiary`: "Resolved with Dev. Disabled Rows are left out."
- Footer: an **Include secrets** checkbox (off by default, not remembered) and **Copy**
  (primary). Include secrets fills secrets in the copied text only; the preview never shows
  them.
- Undefined Variables: an error glyph, "No curl command yet" in `statusFailed`, and the
  sentence naming every missing Variable; Copy disabled.
- An empty Draft: "Type a URL to see the curl command." in `textTertiary`.

### View ▸ Theme menu (native)

A submenu: a "Theme" header and the Themes (Catppuccin, checked); a "Light Appearance"
header and the light Flavors (Latte); a "Dark Appearance" header and the dark Flavors (Frappé,
Macchiato, Mocha). One check per section. Picking applies immediately. Seen on: 08.

## 7. Every error and state, and its place

Every entry of [e-where-it-breaks.md](../e-where-it-breaks.md) with a visible place:

| §4 entry | Place | Component |
|---|---|---|
| send: any SendError | Response pane | Response viewer, failed |
| cancelled | Response pane returns to idle | Response viewer, idle |
| timedOut | Response pane: "No response after 60 s" | failed |
| untrustedCertificate | Response pane, host named, "Allow insecure TLS for this request" | failed |
| invalidURL | URL field outlined in `error`; Response pane quotes the substituted URL | URL bar, failed |
| fileMissing(path) | the multipart chip marked; message line names the path | Body editor |
| transport(code) | Response pane: description plus the code and host | failed |
| resolve: undefined(names) | red underlines already on screen; message line names every one; no spinner | URL bar, key/value table |
| Keychain unreadable | becomes undefined; the Environments sheet row says "Not in the Keychain" | Environments sheet |
| body not UTF-8 | Response pane: binary | Response viewer |
| JSON did not parse | Raw, no message | Response viewer |
| unterminatedQuote | message line with the position; Tab unchanged | URL bar |
| noURL | message line: "No URL in this curl command." | URL bar |
| unknown flag | the Ignored note | URL bar |
| @file unreadable / not UTF-8 | the Ignored note names the file; a multipart part keeps its path | URL bar, Body editor |
| two commands pasted | the Ignored note: "2 more commands" | URL bar |
| Data Folder root not writable | window banner with Choose Folder…; sidebar empty | Banners, Sidebar |
| file undecodable | unreadable sidebar row with reason and Reveal in Finder | Sidebar rows |
| duplicate RequestID | the second is an unreadable row: "Same id as …" | Sidebar rows |
| write failed | Tab banner "Not saved", Tab stays Dirty | Banners |
| file deleted under a Tab | Tab banner "Deleted on disk", the Tab becomes a Draft (italic) | Banners, Tab |
| Session undecodable | one empty Draft Tab (screen 1). The renamed file is not surfaced (Q7) | Tab |
| Session unwritable on quit | logged only; no visible place, by decision | — |
| snapshot Request gone | restored as a Draft | Tab |
| Active Environment file gone | the picker shows "No Environment" | Environment picker |
| SecretStore.set fails | the row in the sheet, with the OSStatus | Environments sheet |
| Environment renamed | not an error; nothing shown | — |
| bundled theme undecodable | DIE: a test, not a UI | — |
| unknown stored Theme | falls back to Latte / Mocha; the menu shows those checked | Theme menu |
| invariants | DIE / impossible: no UI | — |
| Postman Import: not a Postman export / unreadable | that file's row, disabled, with the reason | Postman Import sheet |
| Postman Import: something Raccoon cannot represent | "What won't come across", before Import | Postman Import sheet |
| Postman Import: Data Folder not writable | Import disabled, reason in the footer | Postman Import sheet |
| Postman Import: a Collection fails to write | the result names it; nothing partial is left | Postman Import sheet |
| Postman Import: Keychain refuses an imported secret | the result: imported with no value | Postman Import sheet |

## 8. Worst case (break-ui)

Run on every screen with the data in board 10 (and board 09 for 0 B, binary and missing
files): 30 Tabs, Japanese and emoji names, PROPFIND, a 2,048-character URL, 60 headers, a
1.2 KB JWT with no spaces, a 20.4 MB body, an unreadable file with a long name. Checked
visually by rendering the local mockups in headless Chrome at 2120 px.

### What broke, and the fix (all applied)

| # | Severity | Field | Worst-case value | What happened | Fix |
|---|---|---|---|---|---|
| 1 | Broken | sidebar unreadable row | `Create charge (conflicted copy 2026-10-14).json` | the Reveal in Finder text button took the row; the name showed as "Creat…" | icon-only Reveal button (20 × 18) with label and tooltip; the reason moves to its own line |
| 2 | Broken | status line | `511 Network Authentication Required`, `20.4 MB` | code, time, size and the Pretty note each wrapped onto two lines | `nowrap` on every status-line item; only the reason truncates (`min-width: 0`), never the code, time or size |
| 3 | Ugly | Tab | 6 Tabs in a 768 pt content area | a later `min-width: 0` overrode the 104 pt minimum; every Tab shrank to "List c…" including the selected one | removed the override; the selected Tab keeps 168 pt |
| 4 | Ugly | sidebar method badge | `PROPFIND`, `OPTIONS` | the 38 pt badge cut them to "PROPFI…" | 52 pt badge, end-truncated beyond 8 characters |
| 5 | Ugly | URL bar method | `PROPFIND` | fixed 84 pt pop-up truncated it | 84–128 pt, sized to the label |
| 6 | Broken | multipart file chip | `~/Documents/receipt-1042.pdf` | the `direction: rtl` truncation trick reordered the path to `Documents/receipt-1042.pdf/~` | show the file name only, full path in the tooltip and in the missing-file message |
| 7 | Fragile | 30 Tabs | 30 | nothing marks hidden Tabs | 24 pt fade masks at both edges of the scrolling strip; selected Tab scrolled into view |
| 8 | Fragile | URL field | 2,048 characters | the URL ended at the field edge with no sign it continued | 32 pt trailing fade when it overflows |

### Decisions taken

- **URL**: one line, scrolls, never wraps. It is edited as one string, and wrapping would push
  the editor down on every keystroke.
- **Header values**: end-truncate in the cell; the full value is in the field editor and the
  tooltip. A JWT differs at its end, but the cell is not where it is compared.
- **Request and Collection names**: end-truncate in Tabs and the sidebar; full name in the
  tooltip and in the window title.
- **Numbers** (status code, time, size, counts) never truncate.

### What held up

Japanese and emoji in Tabs, the sidebar and the body; a one-letter Request name ("x"); an
empty header value; three Variable kinds in one cell; a long Environment name in the toolbar
pop-up; 60 rows (the table scrolls, the pane does not grow); Raw for a 20 MB body (no
wrapping, clipped lines); counts that need no plural ("Headers 1", "Headers 60").

## 9. Open UI questions

1. **Closing the last Tab.** tabs.md selects "the neighbour", and there is none. Decided
   2026-10-19: closing the last Tab opens an empty Draft, so the editor always has a Tab
   (surfaces.md §4/§5 assume this).
2. **Window minimum size** and narrow layouts. Decided 2026-10-16: 760 × 480 minimum, the
   Sidebar collapsing to an overlay below 960 pt, each Split pane keeping 160 pt. With the
   inspector open the editor needs 480 pt, so below about 1,000 pt of content the inspector
   overlays the content edge instead of narrowing it.
3. **Sidebar contrast.** Method badges are Theme colors on the sidebar; contrast was checked
   against estimates (#e8e8ea light, #2a2a2e dark). The sidebar is the opaque
   `windowBackgroundColor` (decided 2026-10-16), so neither focus nor the desktop picture shifts
   it. Measured on macOS 27 from a window capture: dark #2c2c2c, light #f0f0f0. Decided
   2026-10-19: badges sit straight on the sidebar, with no chip. Every method token passes in
   its own appearance. Latte on #f0f0f0, worst first: OPTIONS 4.87, PUT 4.91, OTHER 4.96,
   PATCH 5.11, HEAD 5.11, DELETE 5.16, POST 5.28, GET 5.34. Mocha on #2c2c2c: DELETE 6.03,
   OTHER 6.27, PUT 6.63, PATCH 6.87, POST 7.89, OPTIONS 9.15, HEAD 9.38, GET 9.39. `build.py`
   keeps the estimates, which are darker than the measured light value and so stricter. A dark
   Flavor on the light sidebar fails (Mocha GET on #f0f0f0 is 1.30), so the Theme menu must
   not put a dark Flavor in the light slot or a light one in the dark slot.
4. **Draft in scripts without italics.** CJK fonts have no true italic, so a Draft named in
   Japanese is told apart only by its tooltip. Alternative: a leading "Draft" label in
   `textTertiary`, at the cost of ~36 pt. Decided 2026-10-19: italic only. Revised the same
   day after the first run: italic plus a 6 pt `accent` dot before the method badge, which
   reads in every script and costs 12 pt. A Draft has no file, so the dot never meets the
   Changed on Disk glyph that takes the same place.
5. **Shortcut to open the Environments sheet.** variables.md gives ⌃E to the picker. ⌥⌃E is
   proposed for the sheet; not decided anywhere.
6. **`success` has no surface.** The prompt requires the token and the JSON carries it, but
   v1 has no success message: a save clears the dot, a Curl Import fills the Tab. Candidates:
   a "Copied" confirmation for Copy as Curl, or a short "Imported from curl" note when nothing
   was ignored. Decided 2026-10-19: neither. v1 shows no success message, and the token stays
   in the Theme unused.
7. **Corrupt Session.** §4 renames the file to `session.corrupt-<date>.json` and starts
   empty. Should the empty window say so (a one-time banner with Reveal in Finder), or stay
   silent? Decided 2026-10-19: silent. The file is renamed and logged, and the window opens
   with one empty Draft, as on first launch.
8. **Close confirmation** (Save · Don't Save · Cancel) is a native alert and is not drawn;
   confirm that a sheet-style alert attached to the window is wanted over an app-modal one.
   Decided 2026-10-19: a sheet attached to the window (`NSAlert.beginSheetModal(for:)`).
9. **Headers merged by the system.** There is no ordered-headers API (measured, see
   environment-facts.md). Decided 2026-10-16: a footer under the last header row, always
   shown, reading "macOS merges repeated headers and doesn't keep their order." (§6 Response
   viewer). Rows are sorted by name.
10. **`requestsCompression`** changes nothing under URLSession, which always asks for and
    decodes gzip (measured, see environment-facts.md). Decided 2026-10-16: removed. Request
    Settings has two rows, and `--compressed` is an ignored flag in Curl Import.
11. **Request body syntax colors.** The raw body editor is specified with JSON/XML colors,
    which sending.md only requires for the response. Decided 2026-10-16: it highlights, with
    the same `Highlighter.ranges` and tokens as the Response viewer, and `{{name}}`
    highlighting on top (§6 Body editor).
12. **Shortcuts for the new panes.** Proposed ⌥⌘F to focus the sidebar filter (⌘F stays
    find-in-body) and ⌥⌘I for the inspector, ⌃⌘S for the sidebar (the system default).
    None is decided in design/.
13. **What the filter matches.** Decided 2026-10-19: names only, as drawn. Collection,
    Folder and Request names, and an unreadable row's file name. Matching the method and URL
    too ("POST /refunds") was declined: it would find Requests named badly, at the cost of
    noisier results.
14. **Inspector state across relaunch.** Whether it is open, its width and Variables vs Curl
    could be part of the Session or of UserDefaults; the Session is for Tabs, so
    UserDefaults is proposed.
15. **Format on paste or on save.** Decided 2026-10-16: Format is manual only, from the
    Format button or ⇧⌥F. Formatting on save would rewrite what the user typed into the file
    in git, and formatting on paste would change text the user did not ask to change.
16. **Re-importing a newer Postman export.** Import never overwrites, so a second import makes
    "Payments API 2". A merge (match by Postman item id, update changed Requests, keep
    Raccoon-side edits) is the obvious next step for people who keep using Postman in
    parallel; it needs its own design.
17. **Postman's data-dump zip.** Settings ▸ Export Data gives a zip of every Collection and
    Environment. v1 asks the user to unzip it and pick the files; reading the zip directly is
    a small addition at the boundary.
18. **Drag and drop.** Dropping Postman `.json` files onto the sidebar could open the same
    sheet. Not drawn.

