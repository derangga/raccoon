# Raccoon design system

The visual source of truth for the implementation milestones. Vocabulary is
[CONTEXT.md](../../CONTEXT.md); the surface graph, void states and motion decisions are
[surfaces.md](./surfaces.md); the Theme file is [themes/catppuccin.json](./themes/catppuccin.json).

```
design/ui/
  surfaces.md              surfaces, flow, void states, needs, motion, attention
  design-system.md         this file
  themes/build.py          palette + mapping -> catppuccin.json, and the contrast test
  themes/catppuccin.json   generated; the file the app loads
```

`python3 -I design/ui/themes/build.py --table` regenerates the JSON and prints the contrast
table below; it exits 1 if any pair fails, so it is the check.

## 1. The split: native chrome, themed content

| Area | Colors from | Why |
|---|---|---|
| Window, toolbar, sidebar, menus, sheets, alerts, Settings | the system: `NSColor` semantic colors and `NSVisualEffectView` materials. The sidebar is the opaque `windowBackgroundColor`, not a material (decided 2026-10-16): a vibrant material is translucent in a focused window and showed the wallpaper | HIG; follows light/dark and accent by itself. |
| Tab strip, Breadcrumb, banners in the content area, URL bar, message line, request editor, response viewer, the Variable popover | the Theme's tokens | the content areas named in theme.md |
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
| `rowHover` | surface0 (Latte: mantle) | table row hover, Tab hover, Breadcrumb segment hover |
| `text` | text | body text, values, names |
| `textSecondary` | subtext1 | inactive Tab names, Breadcrumb ancestors, labels, meta (time, size), banner detail, the Ignored note |
| `textTertiary` | subtext0 | placeholders ("Name", "Value"), column headers, counts, line numbers, void-state body text, Breadcrumb chevrons |
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
| `curlFlag` | maroon | `curl` and its flags in the Curl pane. Catppuccin's color for parameters; nothing else in that pane is maroon. The rest of the command reuses `method*`, `text`, `jsonKey`, `jsonString` and `jsonPunctuation` (curl.md) |
| `variableDefined` | blue | `{{name}}` that resolves; no underline |
| `variableSecret` | mauve | `{{name}}` that resolves to a Secret Variable; plus a dotted underline |
| `variableUndefined` | red | `{{name}}` that does not resolve; plus a wavy underline |
| `dirtyDot` | peach | the 8 px dot in a Tab's close slot |
| `findMatch` | yellow mixed over `background` (The adjustment rule) | a Find match's background |
| `findMatchCurrent` | peach mixed over `background` (The adjustment rule) | the current Find match's background |
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
| Latte | `backgroundElevated` | base | Latte has nothing lighter than base, so an elevated surface cannot be lighter than the editor. It stays base and is lifted by `border` plus a 0.5 px + 1 px shadow |
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

`findMatch` and `findMatchCurrent` are the one pair that is not a palette colour: yellow and
peach mixed over `background`. The background moves, never the text: the mix starts at 30 %
and 55 % and steps down 2 % until `text` and every JSON and XML colour keep **3:1** over it.
That is WCAG's floor for large text and UI, not the 4.5:1 body text gets, because
`jsonPunctuation` already sits at 4.5:1 on `background` and any visible tint drops it below.
A highlight lasts only while the Find panel is open, and the current match also carries an
`accent` underline, so colour is never its only signal.

| Highlight | Mix | Latte | Frappé | Macchiato | Mocha |
|---|---|---|---|---|---|
| `findMatch` | yellow over background | 3.78 (jsonString), 30% | 3.13 (jsonPunctuation), 16% | 3.15 (jsonPunctuation), 20% | 3.13 (jsonPunctuation), 22% |
| `findMatchCurrent` | peach over background | 3.04 (jsonString), 45% | 3.08 (jsonPunctuation), 21% | 3.09 (jsonPunctuation), 25% | 3.11 (jsonPunctuation), 27% |

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
| `curlFlag` | maroon | 4.5 | 4.70 on backgroundRecessed, L-14% | 5.59 on background | 6.80 on background | 7.93 on background |
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
| Body | SF Pro (system) | 13 pt regular | labels, Tab names, Breadcrumb ancestors, banners, sheets, menus |
| Secondary | SF Pro | 11 pt regular | message line, column headers, hints, sidebar sub-rows |
| Section labels | SF Pro | 11 pt semibold | "Collections", card labels |
| Emphasis | SF Pro | 13 pt semibold | active section name, the Breadcrumb's last segment, banner lead ("Changed on Disk."), void-state titles |
| Code | SF Mono | 12 pt regular | URL field, table cells, bodies, responses, headers |
| Method badge | SF Mono | 10 pt (Tab), 9.5 pt (sidebar), 12 pt (URL bar), bold, +0.02 em | method colour; in the sidebar, selected-text colour on an emphasized selection (§6 Sidebar rows) |
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
| Toolbar Environment control | "Environment" 11 pt, 8 pt gap, Dropdown 28 pt high (12 pt text), 200 pt max; 12 pt clear before the inspector toggle (§6 Environment picker) |
| Sidebar width | 232 pt default, 180 min, 360 max (NSSplitView) |
| Sidebar filter field | 24 pt, 6 pt radius, full sidebar width minus 20 pt |
| Inspector width | 280 pt default, 240 min, 400 max; closed by default |
| Inspector rows | 24 pt min, name column 46 %; group title 11 pt semibold |
| Sidebar row | 24 pt, 6 pt radius selection, 16 pt indent per level, the same for every row kind (§6 Sidebar rows) |
| Sidebar method badge | its own text width (max 56 pt), left-aligned, 4 pt before the name (§6 Sidebar rows) |
| Tab strip | 34 pt |
| Breadcrumb | 28 pt, 12 pt sides; segments 22 pt high, 6 pt side padding, 4 pt radius, 2 pt apart; chevron 8 pt |
| Tab | 104 pt min, 196 pt preferred, selected 168 pt min; 10 pt leading, 6 pt trailing |
| URL bar row | 30 pt controls, 10 pt top / 6 pt bottom, 8 pt gaps, 12 pt sides |
| Method pop-up | 96–128 pt wide; the method left-aligned with a 10 pt inset, a 9 pt `chevron.down` 10 pt from the trailing edge |
| Send button | 76 pt min |
| Message line | 16 pt line height, indented to the URL field's leading edge (104 pt) |
| Section bar | 28 pt, 2 pt accent underline |
| Auth pane | 16 pt padding; left column 240 pt, 1 pt rule, 16 pt gaps; "Auth type" 16 pt line, pop-up 28 pt; heading 22 pt line; None's empty state 8 pt between symbol, title and message; label column 80 pt; fields 26 pt, 320 pt max, rows 36 pt apart; stacks below 600 pt of pane width |
| Key/value row | 28 pt; header 24 pt; columns 30 pt / 36 % / rest / 30 pt |
| Status line | 44 pt; the Body toolbar under it 38 pt |
| Banner | 36 pt min, grows to two lines |
| Split handle | 6 pt hit area, 32 × 3 pt grip |
| Radii | 4 pt small controls and chips, 6 pt fields and buttons, 8 pt cards and menus, 10 pt window |

## 5. Motion

Decided per motion in [surfaces.md §7](./surfaces.md#7-behavior-motion-decisions-from-animate):
Tabs do not animate; the segmented controls' thumb and underline slide on a spring, and what
they switch swaps at once; the spinner is the system one after 150 ms;
banners use a 200 ms ease-out `NSAnimationContext` group (150 ms out), reduced to an opacity
cross-fade under Reduce Motion. The Collection Export sheet's step checks fade in, 150 ms
ease-out, opacity only, 60 ms apart (§6 Collection Export sheet). Nothing else in v1 moves. Hover and press states change on
the same frame, with no transition, because they are seen tens of times a minute.

## 6. Components

Tokens in `code`.

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
| menu | right-click, or a double-click, opens a native menu on that Tab (below) |
| 30 Tabs | Tabs keep 104 pt; the strip scrolls horizontally with 24 pt fade masks at each edge; the selected Tab is scrolled into view on select |

Accessibility: each Tab is an `NSAccessibility` tab with title "<method> <name>", value
"Edited", "Draft", "Sending", "Changed on Disk" as applicable.

**Tab menu** (decided 2026-10-28, after Postman's): a native menu, system colors, no Theme
token. The items act on the Tab the menu opened on, which need not be the selected one, and
the menu opens without selecting it.

```
New Tab                  ⌘T     as File ▸ New Tab
Duplicate Tab
────────────────────────
Close Tab                ⌘W
Force Close Tab          ⌥⌘W
Close Other Tabs                disabled while it is the only Tab
Close All Tabs
Force Close All Tabs
```

Duplicate Tab opens a Draft with the same definition right after the Tab, and selects it. It
is a Draft even from a Request Tab, because a Request is open in at most one Tab. Force
closes discard without the Close sheet. Force Close All Tabs first asks once, in the Force
close confirmation below, when a Tab would lose something, and skips it while File ▸ Always
Discard Unsaved Changes is on; Force Close Tab (⌥⌘W) never asks.
Close Other Tabs and Close All Tabs go one Tab at a time, left to right, asking for each one
with something to lose; Cancel, or a Save that did not land, stops there and the rest stay
open. File ▸ Force Close Tab (⌥⌘W) is the shortcut the menu shows.

### Breadcrumb

Anatomy: `[Collection] › [Folder] › … › [Request name]`, a row 28 pt high directly under the
tab strip, on `background`, so the selected Tab runs into it. It has no rule of its own. A
banner, when there is one, goes under it, then the URL bar.

| Part | Treatment |
|---|---|
| ancestor segment | a button: 13 pt `textSecondary`, 22 pt high, 6 pt side padding, 4 pt radius, transparent |
| last segment | 13 pt semibold `text`. A button too: it selects the Request's own row |
| hover | `rowHover` fill, label `text`, on the same frame. No pressed state |
| chevron | an 8 pt right-pointing chevron, `textTertiary`, 2 pt either side of it |
| `…` | `textSecondary`, not a button, no hover; tooltip is the full path, names joined by " › " |
| Draft | one segment, the Tab's title, as the last segment, not a button, not italic |

Names are shown as they are: the Collection's and Folders' names, and the Request's name from
inside its file, never the file name. Overflow, as the content area narrows: the segments
between the first and the last collapse into one `…`, nearest the first, until the rest fit; if
the first, `…` and last still do not fit, the last end-truncates, then the first. A truncated
segment gets a tooltip with its full name. A name is never wrapped.

Clicking a segment, the last included, shows the sidebar (docked, or the overlay when narrow),
expands every ancestor of that location, clears a filter that would hide it, and selects it and
scrolls it into view. It opens no Tab, toggles nothing, and keyboard focus stays in the Tab.
Segments are not in the key-view loop and show no focus ring, so a click cannot take focus.
No new token: `textSecondary` and `textTertiary` are measured on `backgroundRecessed` and
`backgroundElevated`, both darker than `background`, so they pass there too, and the hover fill
is `rowHover`, which they are already checked on.

Accessibility: the row is a group labelled "Location"; each segment is a button labelled with
its name, the last one `selected`; `…` is static text labelled with the hidden names; a Draft's
title is static text.

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
  `variableUndefined` + 1 pt wavy underline. Hover shows the Variable popover; typing `{{`
  opens the Variable suggestions. Inside a
  Disabled Row all three are drawn in `textDisabled` (the row is not sent, so it is not
  resolved).
- **`:name` token** (a Path Variable, editing.md): the range from the `:` to the end of the
  name is drawn as a rounded token, 4 pt radius, filled `backgroundRecessed`, outlined 0.5 pt
  `border`, the glyph bounds outset 1 pt, with the text in `textSecondary`: the colour of the
  Name cell in the Path Variables table, so the token and its row read as one thing. No new
  Theme token: `textSecondary` already passes 4.5 on `backgroundRecessed` and
  `backgroundElevated` in all four Flavors (Contrast results), so the Theme file and that table
  do not change. In Latte `backgroundRecessed` against `backgroundElevated` (mantle on base) is
  a faint step, which is why the hairline outline is there. Paint only: the text stays as typed
  and the caret and selection are unaffected. Not drawn in a Disabled part, because the URL has
  none.
- **Send**: `accent` fill, `textOnAccent` label, 76 pt min. While sending it becomes
  **Cancel**: `backgroundElevated`, `border`, `text`. ⌘↩ sends, ⌘. cancels. A second ⌘↩
  while sending does nothing (behavior.md).
- **Message line**: 11 pt, a 12 pt glyph, indented to the URL field. Error (`error`, ⓘ-in-a-
  circle-with-bang): Curl Import `unterminatedQuote` with the character position, `noURL`,
  and "Not sent. `a` and `b` are not defined in <Environment> or in Globals." Note
  (`textSecondary`, ⓘ): "Ignored: `--retry`, `-s`", "2 more commands", unreadable or binary
  `@file`. The note has a ✕ and goes away on the next URL edit; errors go away on the next
  paste or send.

### Section bar

Docs · Params · Headers · Body · Auth · Cookies · Settings over the RequestEditor's pane, 28 pt each,
13 pt `textSecondary`, 10 pt padding, 2 pt apart, over a 1 pt `border` rule. Selected: `text`
semibold with a 2 pt `accent` underline over the rule. Params, Headers and Cookies carry their
row count in tabular `textTertiary` ("Params 3", Disabled Rows included; Params counts Query
Params only, never Path Variables); a section with no rows
shows no count. Docs carries a 5 pt `textTertiary` dot after its title when the Request has
notes, and nothing otherwise; a Request opens on Params, never on Docs. Auth reads "Auth" whatever the scheme (the pop-up in its pane names it, and
the section button's accessibility label is "Auth"). Body shows nothing more: the Body Type
pop-ups in its pane already name it.

### Key/value table

Shared by Params, Headers, Cookies, form-urlencoded and multipart.

Anatomy: header row (24 pt, `backgroundRecessed`, `textTertiary` 11 semibold "Name" "Value"),
then 28 pt rows: `[checkbox 30] [name 36 %] [value] [delete 30]`, 1 pt `border` between rows,
one vertical rule between Name and Value, 6 pt radius outer border.

| State | Treatment |
|---|---|
| rest | cells SF Mono 12 `text`, single line, end-truncated with the full value in the field editor and a tooltip |
| hover | `rowHover`; the delete button (⊖, `textTertiary`) appears and stays while the pointer is anywhere in the row, over a cell's field included |
| selected | `selection` fill, not the system accent; name and value keep their own colors. An automatic row is never selected |
| editing | the whole cell, edge to edge, becomes the input as in Postman: a square 2 pt `focusRing` outline drawn inside the cell's bounds, on `background`. The text does not move between rest and editing. A click anywhere in the cell edits it, not only on the text. One click, in any row, selected or not (the row is selected as the cell takes focus, where rows can be selected); at most one cell shows the outline. This holds for every table with editable cells (key/value, Path Variables, the Environments sheet's Variables) |
| Disabled Row | checkbox **unchecked** and name/value in `textDisabled`. Both cues, never one |
| trailing empty row | always present, last; "Name" / "Value" placeholders in `textTertiary` at 60 % opacity, SF Pro 13 (at full strength Latte's `textTertiary` reads as a value); typing in it creates a row and a new trailing row |
| 60 rows | the table scrolls inside the pane; the header row stays put; an overlay scroller |
| automatic row | Headers only, above the user's rows (the trailing empty row is always last): the headers sent that no row sets (`AutomaticHeaders`), name and value in `textTertiary`, a checked checkbox that is disabled (sent whatever the user does, so it cannot be unticked; tooltip "Always sent. Add a row with the same name to replace it."), no delete, not editable, not selectable. A value computed at send reads "calculated when sent". Typing a row with the same name replaces it; the section count leaves them out. |

The section label carries the count of rows ("Headers 60"), `textTertiary`, tabular. A count
holding an Undefined Variable is drawn in `variableUndefined` semibold, so the reason a send
is blocked is visible from another section.

### Params pane and the Path Variables table

The Params pane is two labelled tables in one scroll view.

- **Labels.** "Query Params" always, over the Params table, which keeps its rows, trailing
  empty row and behaviour as above. "Path Variables" appears over a second table only while the
  URL has at least one Path Variable (editing.md). With none there is no label, no table and no
  empty box. Labels are 24 pt rows, 12 pt SF Pro semibold `textSecondary`, with 12 pt above the
  second one. "Variables" is never the label: a Variable is `{{name}}`, and the two must not be
  confused (CONTEXT.md).
- **Scrolling.** The pane scrolls as one: a single scroll view holds both labels and tables, and
  neither table scrolls on its own or pins its header row. (This replaces the "60 rows" row
  above for the Params pane only; Headers, Cookies and the body tables are unchanged.)
- **The Path Variables table** has the key/value table's chrome (6 pt radius border, 24 pt
  `backgroundRecessed` header row "Name" · "Value" in `textTertiary`, 28 pt rows, 1 pt `border`
  rules, one vertical rule at 36 %) and these differences: **no checkbox, no delete, no
  trailing empty row, no row hover fill.** A row exists because its name is in the URL and
  goes when it leaves.
- **Name cell:** SF Mono 12, `textSecondary`, the name without its `:`. Read-only: a click does
  nothing, it is never selected, and it has no field editor.
- **Value cell:** edits like any cell in the key/value table (the `focusRing` outline, a click
  anywhere in it). It takes `{{name}}`: highlighted and suggested as everywhere, and a Variable
  inside it that is undefined is `variableUndefined` with the wavy underline. The placeholder
  "Value" is `textTertiary` at 60 %, SF Pro 13, as for the trailing empty row. An empty value is
  empty, not an error, and is sent as `:id` (sending.md).
- **When the URL changes** a row appears or goes in place. A cell being edited keeps its field
  editor and caret when a row above or below it comes or goes. A row whose name stays keeps its
  value and, if it is being edited, its focus.
- **The Params count** in the Section bar counts Query Params only, Disabled Rows included.
  Path Variables are not in it: they are drawn in the URL right above. A Path Variable value
  that holds an Undefined Variable does colour the count `variableUndefined`, as one in a Param
  does, so the reason a send is blocked is visible from another section. With no Query Params
  row there is no count to colour (a section with no rows shows none), so the label "Params"
  itself is drawn in `variableUndefined` instead, semibold, until the Variable is defined or
  removed. This case exists only here: for every other section a Variable lives in a row, so
  the row is counted.

### Body editor

- **Body Type** pop-up: none · raw · form-urlencoded · multipart · GraphQL. When raw, a second pop-up:
  JSON · text · XML. Switching follows editing.md's conversion table; the Content-Type row it
  writes appears in Headers like any other row.
- **none**: "This request has no body." in `textTertiary`, centred.
- **raw**: an NSTextView in SF Mono 12, `background`, `border`, line numbers in
  `textTertiary`, syntax colors for JSON and XML (the same tokens as the response viewer),
  `{{name}}` highlighting on top. ⌘F opens the system find bar (Edit ▸ Find ▸ Find…).
- **Format** (raw JSON and XML only; hidden for text, none, form and multipart): a bordered
  button with a list glyph at the trailing end of the Body Type row, tooltip "Format JSON
  (⇧⌥F)". It re-indents with 2 spaces in one undo step, keeps key order, number spelling and
  every `{{name}}` as typed (editing.md). If the body does not parse, the text is left alone
  and one 11 pt `error` line under the editor says where: "Couldn't format: not valid JSON
  at line 3, column 14." The line goes away on the next edit.
- **GraphQL**: an "Operation Name" text field (placeholder "Optional") on the Body Type row,
  then the Query editor over the Variables editor, split 2 : 1 by a draggable 1 pt `border`
  divider, each with an 11 pt `textTertiary` caption ("Query", "Variables"). Both are the raw
  editor above: SF Mono 12, line numbers, `{{name}}` highlighting. The Query is coloured by the
  GraphQL tokens, reusing the JSON ones: keywords (`query`, `mutation`, `subscription`,
  `fragment`, `on`) as `jsonBoolean`, field and argument names as `jsonKey`, `$variables` as
  `jsonNull` (never a `variable*` token: those mean `{{name}}`), strings and
  block strings as `jsonString`, numbers as `jsonNumber`, punctuation as `jsonPunctuation`, `#`
  comments as `textTertiary`; the Variables as JSON. Format acts on Variables only, and is enabled only
  while Variables has focus.
- **form-urlencoded**: the key/value table.
- **multipart**: the key/value table, where a value is text or a **file chip**: 20 pt,
  `backgroundRecessed`, `border`, a document glyph and the file name (full path in the
  tooltip). A file that is missing at send: chip in `error` border and text with a warning
  glyph, and the message line "Not sent. `<path>` is missing." The Value placeholder reads
  "Value or file"; dropping a file onto a row or choosing "Choose File…" from the row's menu
  makes it a file part.

### Auth section

Two columns inside the pane, split by a 1 pt `border` rule, on a 16 pt padding. The rule runs
the pane's full height, top edge to bottom edge, whatever the columns hold.

**Left column**, 240 pt fixed:
- "Auth type": 12 pt semibold `textSecondary`, with nothing at its trailing end.
- A pull-down pop-up, 28 pt, `backgroundElevated`, `border`, 6 pt radius, 13 pt `text`, the
  system pull-down chevron, no glyph. Items "None", "Basic Auth", "Bearer Token"; the title is
  the chosen item. It replaces the segmented control. A pick is one undo step, named "Auth
  Type", so ⌘Z brings the old scheme back with what was typed in it.
- Under it, 6 pt apart, a paragraph: 12 pt `textSecondary`, wrapping at the column's width.
  It says what the send does, from `AuthNote.text(auth, headers)` (sending.md):
  - None: "No Authorization header is added."
  - Basic: "The Authorization header is generated from the username and password when you send
    the request."
  - Bearer: "The Authorization header is sent as Bearer followed by the token."
  - Basic or Bearer, and the Headers table holds an enabled `Authorization` row (any case,
    any value, empty too): the sentence above, then " An enabled Authorization row in Headers
    is sent instead." The resolver skips Auth's header when such a row exists (sending.md). The
    right column's fields stay editable and keep their normal look. The pane refreshes the
    paragraph whenever it is shown and on every Auth or Headers edit.
- There is no reset button: the pop-up's "None" does the same, and an
  `arrow.uturn.backward` glyph beside ⌘Z would look like Undo and not be.

**Right column**, the rest of the width, 16 pt from the rule:
- None: an empty state, centered both ways in the right area (the part right of the rule, 16 pt
  clear of it, to the pane's trailing edge and from its top to its bottom). Stacked below 600 pt,
  the area is the part under the horizontal rule. A column, 8 pt apart, centered on each other:
  the `lock.open` symbol (20 pt, `textTertiary`), the title "No Auth" (13 pt semibold,
  `textSecondary`), and the message "Pick Basic Auth or Bearer Token under Auth type to add one."
  (12 pt `textTertiary`, centered, wrapping at 260 pt). It is the void-state look of the Curl
  pane. Picking Basic or Bearer removes it and shows that scheme's heading and fields.
- Basic: heading "Basic Auth" (17 pt regular, `text`), 14 pt below it the rows "Username" and
  "Password", placeholders "Username" and "Password". Password is a secure field showing its
  `{{name}}` if it holds one, otherwise bullets.
- Bearer: heading "Bearer Token", one row "Token", placeholder "Token".
- A row is `[label][field]`: the label left-aligned, 13 pt `text`, in an 80 pt column, 12 pt
  before the field. Rows are 36 pt apart. The field is 26 pt, `backgroundElevated`, `border`,
  6 pt radius, SF Mono 12, 8 pt side padding, and takes the rest of the width up to **320 pt**
  (about a third of a 970 pt editor). Placeholders are `textTertiary`. The fields keep `{{name}}`
  highlighting, the `{{` suggestions and the Variable popover. There is no enabled flag, so no
  disabled styling.

**Narrow: the pane's own width below 600 pt.** Two columns need 16 + 240 + 16 + 1 + 16 on the
left and 80 + 12 + 200 + 16 on the right, 597 pt, so 600 pt is where the field would otherwise
shrink under 200 pt. Below it the left column (still 240 pt wide) stacks above the right one,
the rule becomes a horizontal 1 pt `border` rule 16 pt above and below, and the right column
fills the pane's width. The editor's minimum is 480 pt (the Inspector overlays below that), so
it always fits. The editor measures its own width, not the window's.

The domain Auth enum, its stored form, the header built at send and Curl Import's mapping of
an `Authorization` header to Auth are unchanged. Switching the pop-up drops what was typed for
the old scheme, as the domain Auth enum does: the pane keeps no values of its own, so another
Tab, or the same Tab after a switch, shows empty fields. ⌘Z brings the old scheme back with its
values.

### Request Settings

Six rows, each one label in `text` over a wrapping hint in `textTertiary`, with the row's
control right-aligned on the label's baseline and 16 pt between rows. A row grows to at most
600 pt, the measure the Auth pane stacks at, and the column stays on the leading edge: pinned
to the pane's own trailing edge instead, a control sits a window's width from its hint. The four switches are
`NSSwitch` at `.mini`; the two numbers are `NSTextField`s 64 pt wide with a number formatter,
right-aligned text. There is no compression row: URLSession always asks for and decodes gzip
(environment-facts.md, Open UI question 10).

| Label | Hint | Control |
|---|---|---|
| Allow insecure TLS | Accept certificates the system does not trust, for this Request only. | switch, off |
| Follow redirects | Send the request again to the Location a 3xx reply names. | switch, off |
| Follow original HTTP method | Redirect with the method that was sent, instead of switching to GET. | switch, off |
| Follow Authorization header | Keep the Authorization header when a redirect goes to another host. | switch, off |
| Maximum number of redirects | Between 0 and 20. The system stops at 20 whatever is set here. | field, 20 |
| Request timeout (seconds) | Time allowed to pass with no new bytes, not a cap on the whole send. Empty is 60. | field, empty |

The last three rows are `textDisabled` and their controls disabled while Follow redirects is
off, because nothing then follows a redirect for them to shape. Their values are kept, so
turning Follow redirects back on shows them again. A number typed outside its range is clamped
on commit and the field redraws with the clamped value; an empty timeout field is 60 and is not
drawn as `0`. Return and a click elsewhere commit; **Esc gives focus up and leaves the setting
as it was**, redrawing the field at the committed number, as a value field in the Inspector does.

### Response viewer

Anatomy: status line (44 pt), then the Body toolbar (38 pt, Body section only), over the body
area, all on `backgroundRecessed`.

- **Segmented control** (`SegmentedControl`), in three styles. Titles are 12 pt. A segment is
  as wide as its semibold title, so choosing one never moves its neighbours. A count, the 11
  of "Headers 11", is 11 pt regular with tabular figures, 5 pt after the title, in
  `textTertiary` (`textSecondary` while selected). A click moves the thumb or underline on a
  spring (§5, surfaces.md §7); titles recolour on the click's frame, and so does hover. A
  disabled segment's title is `textDisabled`.
  - *Track* (Body | Headers N | Timeline): 28 pt high, 8 pt radius, a `selection` fill at
    60 %, 2 pt padding. Segments are the title plus 12 pt each side. The selected segment is a
    6 pt radius thumb in `backgroundElevated` with a 0.5 pt `border` at 70 % and a 1 pt
    shadow, its title `text` semibold. An unselected title is `textSecondary`, and `text`
    under the pointer.
  - *Underline* (Pretty | Raw): as tall as its row, no fill, no border. Segments are the title
    plus 3 pt each side, 14 pt apart. The selected title is `text` semibold, with a 2 pt `text`
    underline along the bottom of the row, above its rule. Unselected and hover as in Track.
  - *Boxed* (the Inspector's pane switch, unchanged): 24 pt, 1 pt `border`, 6 pt radius,
    `backgroundElevated`, 22 pt segments split by 1 pt rules, the selected one `selection`.
- **Status line**: leading, Body | Headers N | Timeline (received only, the Track style), 12 pt in from the
  edge; it never truncates. Trailing, in every state so it never moves when a Response lands:
  the spinner, the status code + reason in `status1xx`…`status5xx` (SF Mono 12 bold), then
  elapsed time, size and "2 redirects" in `textSecondary` with tabular figures, separated by
  `textTertiary` middle dots, 12 pt in from the trailing edge. The reason end-truncates first,
  then the redirects count hides; the code, time and size never truncate.
- **Body toolbar**: 38 pt, 12 pt side padding, a 1 pt `border` rule under it. Leading: Pretty |
  Raw (the Underline style), then the note in `textDisabled` 11 pt ("Pretty is off above 5 MB", "Showing the first
  1 MB of 3.2 MB" with Save to File… beside it, or an image's "900 × 900 · image/webp"); the
  note truncates first. Trailing: Search (`magnifyingglass`, tooltip "Find (⌘F)") and Copy
  (`doc.on.doc`, tooltip "Copy Response Body"), then Save as Example (`square.and.arrow.down.on.square`,
  tooltip "Save as Example (⌥⌘E)"; disabled with tooltip "Save the Request first" on a Draft), 4 pt apart.
  A failed save shows its reason as the note, in `error`, until the next send. For an image both are disabled
  and Pretty | Raw is hidden; for the Hex view Pretty | Raw is hidden. Copy turns to
  `checkmark` (tooltip "Copied") for 1.5 s with the system symbol swap, no transition under
  Reduce Motion.
- **Icon button** (`IconButton`): 24 × 24 (20 × 20 inside the Find panel), 6 pt radius,
  borderless, the symbol 13 pt regular in `textSecondary`. Hover fills `rowHover` and the
  symbol turns `text`; pressed fills `selection`, on mouse-down. Disabled: the symbol in
  `textDisabled`, no hover. Every one has a tooltip and an accessibility label.
- **Find panel**: floats over the body, 8 pt below the body area's top and 8 pt left of the
  vertical scroller (16 pt from the trailing edge with none); the text under it never moves.
  320 × 32 pt, the Dropdown list's surface: `backgroundElevated`, 8 pt radius, 1 pt `border` at
  50 %, a soft shadow (black at 12 %, 12 pt blur, 4 pt down). Inside, 6 pt padding: a 13 pt
  `magnifyingglass` in `textTertiary`; a borderless field, SF Mono 12 `text`, placeholder
  "Find" in `textTertiary`, taking the free width; the count, 11 pt `textTertiary` with
  tabular figures ("2 of 7", "No results", "2 of 10,000+", empty for an empty field); then
  `chevron.up`, `chevron.down` and `xmark` icon buttons, tooltips "Previous (⇧⌘G)", "Next
  (⌘G)" and "Close (Esc)". While the field has focus the panel draws a 2 pt `focusRing`
  outline. It appears and goes with no animation. Matches are drawn with a `findMatch`
  background, the current one `findMatchCurrent` with a 1 pt `accent` underline. Return and
  ⇧Return step; Esc closes and leaves the current match selected in the body.
- **idle**: "Send a request to see the Response here." `textTertiary`, with a ⌘↩ key cap.
- **sending**: spinner + "Sending… 1.4 s", the time live; body: the Sending loader, then
  "Waiting for the server. ⌘. cancels." under it. Neither string changes.
  - *Loader*: the Lottie `design/ui/assets/loading/raccoon-rocket.json`, read-only and never
    redrawn. 240 × 240 pt (the art is about 195 pt of it), centred in the same centre-gravity
    area of the stack as the text, so the pair is centred in the body area, 8 pt above it. Its
    background is transparent. Motion and timing: surfaces.md §7.
  - *Fit*: the stack needs 16 + 240 + 8 + 16 (one text line, computed, not measured) + 16 =
    296 pt of body area, and the body area is the pane less the 45 pt status line. The Response
    pane may shrink to 160 pt (Open UI Q2), where the body area is 115 pt, so the loader is
    hidden and the text stays. It shows from a 341 pt pane up.
  - *Reduce Motion*: the still Fly pose, frame 72 (1.2 s), with no playback and no fade. The
    status row's spinner and the live time stay, because they are status.
  - *Accessibility*: decorative, hidden from VoiceOver. The status line's "Sending…" and the
    text already say the state.
  - *Asset failure*: if the file is missing or does not decode, the sending state is as it was
    before the loader existed: the status row's spinner and the text. No alert and no banner
    (e-where-it-breaks.md, Sending loader).
  - *Flavors*: the art is pale, drawn for a dark background. Against each Flavor's
    `backgroundRecessed`, the Response pane's fill (WCAG contrast of its 78 fills, measured
    2026-11-12):

    | Flavor | Response background | Fills under 1.5:1 | Reads? |
    |---|---|---|---|
    | Latte | `#e6e9ef` | 28 of 78; the rocket body `#E6EAFA` is 1.0:1 | **No** |
    | Frappé | `#292c3c` | 17, all the art's own navy shading; its pale parts are 12.8:1 or more | Yes |
    | Macchiato | `#1e2030` | 13, same | Yes |
    | Mocha | `#181825` | 13, same; the darkest fill is 1.09:1 | Yes |

    **No background (decided 2026-11-12):** the loader holds no tile, fill or backing in any
    Flavor; it is drawn straight on the Response pane. A backing tile for Latte was decided
    first and then removed. Known cost: in Latte the pale parts of the art are close to the
    pane's colour, so the loader reads faintly there.
- **received**: Pretty (parsed JSON/XML, syntax tokens) or Raw (no colors). Raw shows first
  while Pretty is computed off the main thread (behavior.md). Above 5 MB Pretty is disabled
  (`textDisabled`) with "Pretty is off above 5 MB" beside it. ⌘F opens the system find bar
  over the body, as in the body editor.
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
  send), "No response after 60 s" (or the Request Timeout the send used), "Too many
  redirects" naming how many were followed, URLError's description plus the code and host for
  transport errors, "Invalid URL" quoting the URL after substitution (status line "Not sent").
- **binary**: the Hex view, in the body's text view, SF Mono 12 `text`: the `hexdump -C`
  layout (`00000000  7b 22 69 64 …  |{"id…|`). No Gutter numbers (the offset column is the
  address), no Pretty | Raw, no folds. Above 1 MB the Body toolbar holds "Showing the first
  1 MB of 3.2 MB" where the Pretty note sits, `textDisabled` 11 pt, and a "Save to File…"
  button beside it styled as the failure fix button. Until the off-main presentation lands
  the body area is empty, not the bytes as text.
- **Save Response Body…**: File menu, no key equivalent, and the last item of the body's and
  the image's context menu. Disabled unless the Tab holds a received Response with a
  non-empty body. A failed write is an alert on the window: "Couldn't save the Response
  body." with the path as its informative text.
- **Timeline** (the third section, Body | Headers N | Timeline): one block per Redirect, then
  the Response, separated by a `border` rule, SF Mono 12. Line 1: "302 Found · GET ·
  https://a.example/login · 48 ms", the status in its `status3xx`…`status5xx` token. Under
  it the phases in `textSecondary`: "DNS 4 ms · Connect 12 ms · TLS 18 ms · Send 0 ms ·
  Waiting 10 ms · Download 1 ms", a phase that did not happen left out, and "Reused
  connection" in place of DNS, Connect and TLS. Then "h2 · 93.184.216.34:443 · TLS 1.3" in
  `textTertiary`. The Response's block then has "1.2 KB · 420 B on the wire" in
  `textSecondary` when the Wire Size differs. A Redirect's block ends with "Location
  https://a.example/home", then its headers as in Headers; the timing lines sit above them so
  a long header list never pushes them out of sight. With no Timing for the send, each
  block's phase line reads "Timing was not reported for this send." The status line adds "· 2 redirects" after the size when the send followed any.
- **Find**: the Find panel, above. A match inside a folded region unfolds that region and the
  folds around it, and no other.
- **image** (`Content-Type: image/*` other than `image/svg+xml`, and the bytes decode): the
  body area shows the picture centered on `backgroundRecessed`, scaled down to fit and never
  past its natural size, aspect ratio kept; no Gutter, no Pretty | Raw. The Body toolbar holds
  a caption where the Pretty note sits, `textDisabled` 11 pt like the Pretty note:
  "900 × 900 · image/webp" (pixels, then the media type). Bytes that do not decode show
  **binary**, above. The picture appears at once, decided by the header: no text is drawn
  first.
- **empty body** (0 B): "Empty body." Status line unchanged.
- **Headers**: two columns, name `textSecondary`, value `text`, SF Mono 12, end-truncated
  with the full value in a tooltip. Wire order and duplicates are gone before Raccoon sees
  them (environment-facts.md), so rows are sorted by name (as the transport returns them), and two
  Set-Cookie headers are one row with the values joined by `, `. Under the last row, always:
  "macOS merges repeated headers and doesn't keep their order." in `textTertiary`, 11 pt.

### Sidebar rows (native)

NSOutlineView, source-list style, on the sidebar material. 24 pt rows, `sys` label colors.

**One leading edge per level.** `indentationPerLevel` is 16 pt, and a row's leading edge is
`level × 16` further right than a level 0 row's, whatever the row is: Collection (level 0),
Folder, Request, Unreadable. AppKit places each cell there and keeps the disclosure slot even
for rows with no children, so a Request is not pushed in by the missing triangle. Whatever
the cell shows starts at that edge: a Folder's glyph, a Request's badge, an Unreadable row's
warning triangle. A Request's badge therefore starts where a Folder's glyph at the same
level would. Nothing inside a cell may add an offset of its own before the first element:
the 2 pt padding a label keeps each side is cancelled by placing the label 2 pt left of the
edge. The filter view keeps the rule: its rows have the same levels as in the unfiltered
tree (matches expand their ancestors, nothing is flattened).

**A click keeps focus in the outline.** Clicking a Request row opens or selects its Tab and
leaves keyboard focus in the outline, so the row keeps the system's emphasized selection
(accent fill, white text) after the button is released instead of flipping to the grey,
unemphasized one. ↑ ↓ keep moving the sidebar selection. A field being edited in the Tab, or
in the Inspector, still ends its edit and writes its text to the Tab it was typed in before the
new Tab shows. Return on a row, and Return in the filter, are the ways focus goes to the URL
field (surfaces.md §8). Selection is drawn as AppKit draws it, emphasized only while the
outline has focus: a Breadcrumb click, which leaves focus in the Tab, shows the unemphasized fill.

**Coloured text on a selected row.** Any coloured text or glyph in a row follows the row's
background style. On an emphasized selection (the outline has focus, the accent fill) it is
`NSColor.alternateSelectedControlTextColor`, the system's colour for text on that fill, never
a hard-coded white: the name, the method badge, a Collection's or Folder's glyph, an
Unreadable row's warning triangle and its reason line. On an unemphasized selection (grey,
the outline without focus) and on unselected rows, they keep their own colours (`method*`
and `warning` Theme tokens, secondary label). The cell reads `backgroundStyle == .emphasized`.

- **Collection**: disclosure, a stacked-layers glyph, the name.
- **Folder**: disclosure, folder glyph, name.
- **Request**: the method badge (its method colour, white on an emphasized selection), then the name, end-truncated. The name starts 4 pt
  after the badge's own text, so `GET` leaves no gap and `PROPFIND` (48.5 pt at SF Mono bold
  9.5 pt with +0.02 em) fits. The badge is capped at 56 pt: longer methods get an ellipsis.
  Names of Requests in one parent are not aligned when their methods differ in length. A
  fixed 52 pt column aligned them but left about 30 pt of empty space after `GET`.
- **Unreadable**: a `warning` triangle at the leading edge, the **file name** (not a Request name: there isn't
  one) 20 pt after it, in secondary label color, and an icon-only Reveal in Finder button (20 × 18,
  `aria-label`/tooltip "Reveal in Finder"). Beneath, an 11 pt line with the reason, starting under the name (20 pt after the leading edge): "Not
  valid JSON at line 14. Raccoon won't change this file.", "Unknown file version 3.", "Same id
  as List refunds.json.", and for JSON that is not a Request "Not a Raccoon Request: missing
  “name”. Raccoon won't change this file." Selecting it shows nothing in the editor; double-click reveals.
- **More actions**: a 16 × 16 borderless `ellipsis` button at the trailing edge, 6 pt in,
  tooltip and accessibility label "More actions". Shown while the pointer is over the row and
  on the selected row, hidden otherwise, so names truncate against it only then. A click opens
  the row's context menu under the button and does not change the selection. On an
  emphasized selection it takes `alternateSelectedControlTextColor`, as the row's text does.
- **Example** (a child of a Request row, one level deeper): the status code in SF Mono bold
  9.5 pt where a Request's method badge sits, coloured `status2xx` … `status5xx` by class, as the
  Response's status line, then the Example's name. A Request with Examples gets a
  disclosure triangle; collapsed by default, expanded when Save as Example adds one.
- **Mock indicator**: on a Collection row whose Mock Server runs, an 8 pt `success` dot before
  the More actions button, tooltip "Mock Server on http://127.0.0.1:<port>".
- **Empty**: "No Collections yet. Create one, or save a Draft into one with ⌘S." plus the Data
  Folder path in SF Mono 11.

### Workspace pop-up

A `Dropdown` (below) at the top of the sidebar, above the filter field, full sidebar width
minus 20 pt, 24 pt high. Its title is the open Workspace's title, end-truncated. Its rows:

- every Workspace by title (`localizedStandardCompare`), the open one checked. A title is
  the folder name; two Workspaces with the same folder name read "api — work" and
  "api — side", the parent folder added for those two only. Each row's detail line is the
  full path, abbreviated with `~`.
- a separator, then **New Workspace…**, **Open Workspace…** and **Manage Workspaces…**, which
  opens the Workspaces sheet below. Removing is not in this menu: a menu that switches and a
  menu that forgets side by side read as one thing.

New Workspace… is an `NSSavePanel` as a sheet: "Name" field, prompt "Create", default
directory `~`. A name that exists gets an alert: "A folder named “<name>” already exists. Use
Open Workspace… to add it." Open Workspace… is the open panel the banner uses.

### Workspaces sheet (native)

A 440 pt wide sheet opened by Manage Workspaces…, as tall as its content: 20 pt margins, the
heading "Workspaces" (15 pt semibold), under it the hint "Remove forgets a Workspace. Its folder
and secrets stay." (12 pt secondary), a 14 pt gap, the list, a 16 pt gap, **Done** (default,
Return) at the list's trailing edge. Done and Esc close; there is no Cancel, because nothing is
held back.

The list is a grouped box: 8 pt radius, a 1 pt `separatorColor` border, `controlBackgroundColor`
fill, 48 pt rows, a hairline between rows inset 14 pt from the leading edge and none under the
last. It shows six rows and scrolls past that; the sheet shrinks and grows with the row count,
anchored at its top edge. A row, 14 pt in from both sides:

- the title in 13 pt medium, end-truncated; beside it, pills (10 pt semibold secondary on a
  4 pt `quaternaryLabelColor` fill): "Default" on ~/Raccoon, "Open" on the open Workspace, both
  on a row that is both;
- under it the path in SF Mono 11 secondary, abbreviated with `~`, middle-truncated;
- trailing, a **Remove** text button in a 56 × 24 column, right-aligned so the column's edge is
  one line down the list. The default Workspace's row has none; its "Default" pill says why.
  The button is 12 pt `secondaryLabelColor`, `systemRed` under the pointer, 60 % while
  pressed, `tertiaryLabelColor` when disabled. A bordered button on every row would shout over
  the one thing the row is for, and would sit a bright control beside a destructive one.

- **Remove.** No prompt, as − in the Environments sheet: it forgets the Workspace and deletes
  its Session, and Open Workspace… brings it back with its secrets. The open one can be
  removed too: the window switches to the first other one by name. The default ~/Raccoon
  cannot be removed, open or not. The row fades and slides up and the sheet shrinks with it (an opacity fade only
  under Reduce Motion); the rows below keep the same order, and a title that lost its parent
  folder ("api — work" → "api") updates in place.
- **One Workspace.** Its Remove is disabled; the last one stays.
- **Focus.** Opens on the list; closing returns focus to the field that had it (surfaces.md §8).

### Banners

In the content area, under the Breadcrumb and above the URL bar, so they belong to the Tab
whose state they describe. 36 pt min, `backgroundElevated`, `border` bottom, a 16 pt glyph,
a bold lead sentence and detail in `textSecondary`, buttons trailing.

| Banner | Glyph | Text | Buttons |
|---|---|---|---|
| Changed on Disk | `warning` | "**Changed on Disk.** <file> was changed outside Raccoon. Your edits are kept until you choose." | Keep Mine · **Reload** (primary) |
| Deleted on disk | `warning` | "**Deleted on disk.** <file> is gone. This Tab is now a Draft with your content, and ⌘S saves it again." | Dismiss |
| Not saved (write failed) | `error` | "**Not saved.** Couldn't write <file>: <reason>. The Tab keeps your edits." | Dismiss |
| Data Folder not writable | `error` | "**Raccoon can't write to the Data Folder.** <path> is read-only. Collections are unavailable; Drafts and sending still work." | Remove from List · **Open Workspace…** |
| Data Folder not readable | `error` | "**Raccoon can't read the Data Folder.** <path> can't be read: <reason>. Collections are unavailable; Drafts and sending still work." | Remove from List · **Open Workspace…** |

<path> is abbreviated with `~` and set in SF Mono 12. Open Workspace… opens an open panel as a
sheet (folders only, New Folder allowed); Cancel changes nothing. Remove from List forgets
this Workspace and switches to the first other one by name; it is not shown when no other
Workspace is listed. The Data Folder banner is
the one global surface: it spans the whole window under the
toolbar, above sidebar and content, because it is the only failure with no smaller place
(e-where-it-breaks.md).

### Environment picker

A `Dropdown` (below) in the toolbar, labelled "Environment", showing the Active Environment
or "No Environment". Rows: No Environment, a separator, each Environment by name with a check
on the active one, a separator, "Edit Environments…", which opens the sheet and leaves the Active Environment showing. ⌃E
opens the list (View ▸ Choose Environment); ⌥⌃E opens the sheet (View ▸ Edit Environments…;
decided, Q5), so both are listed in the menu bar. Long names end-truncate at 200 pt; the list shows them in full.

Sizes: the label is 11 pt `secondaryLabelColor`, then an 8 pt gap, then the Dropdown at 28 pt
high. The item's own trailing inset is 12 pt, so at least 12 pt of toolbar stays clear between
the Dropdown and the inspector toggle's background whatever spacing the toolbar adds. The
Dropdown's width is the selected title's width plus its insets, to a 200 pt maximum; the
toolbar fixes the view's size once, so the picker resets the width each time the title changes.

### Dropdown

One control, `Dropdown`, for choosing one of a short list and for the actions that sit beside
the choice. It replaces the system pop-up button and its `NSMenu`, which the Theme cannot paint.

- **Trigger.** `backgroundElevated` fill, 1 pt `border`, 6 pt radius; `rowHover` fill under the
  pointer; a 2 pt `focusRing` outline while it has keyboard focus. The title is 12 pt `text`,
  8 pt from the leading edge, end-truncated; a 9 pt `chevron.down` in `textSecondary` sits 8 pt
  from the trailing edge. The title is the chosen option's; an action never changes it.
- **List.** A borderless panel under the trigger, 4 pt below its bottom edge with its left edge
  on the trigger's, a child of the window so focus stays on the trigger. It is at least as wide
  as the trigger and at most 320 pt, 8 pt radius, `backgroundElevated`, 1 pt `border` at 50 % opacity,
  a soft shadow (black at 12 %, 12 pt blur, 4 pt down) drawn on the list, not the system's
  window shadow, 4 pt padding. Separators are the same 50 % `border`. Where the screen ends below, it opens above the trigger; its
  left edge is clamped to the screen. Past 8 rows it scrolls.
- **Rows.** 28 pt (40 pt with a detail line), a 6 pt radius highlight in `rowHover` for the
  row under the pointer or the keyboard. The chosen option shows an 11 pt medium `checkmark`
  in `accent` in a 24 pt leading column that every row keeps, so titles align. Title 12 pt
  `text`; the detail line 11 pt `textTertiary`, end-truncated. An action row has the same
  look as an option row, without the check. A separator is a 1 pt `border` rule in a 9 pt row,
  inset 8 pt.
- **Keys.** Space, Return and ↓ on the focused trigger open the list, and ⌃E opens the
  Environment one. Open, the chosen option is highlighted (the first row when none is).
  ↑ and ↓ move the highlight over rows and skip separators, stopping at the ends; Return or
  Space picks it; Esc, Tab, a click outside, a scroll outside or a ⌘ key closes without picking.
- **Accessibility.** The trigger is a pop-up button with the control's label and the title as
  its value; the list is a menu whose rows are menu items, the chosen one marked selected.

### Environments sheet (native)

680 × 430 sheet. Left: a source list with Globals, an "Environments" header and each
Environment; the active one has a check; + and − under it in a 28 pt footer as System Settings
draws one: a hairline across the top, then + | − (borderless, 24 × 22, 13 pt medium symbols, a
16 pt separator between them). Right: the selected set's name and
a table `[enabled] [Name] [Value] [Secret]`, SF Mono 12, with the trailing empty row and
Disabled Rows (unchecked, secondary label color). It opens on the Active Environment, else on
Globals, and focus goes back to the field that had it (surfaces.md §8).

The Variables table is drawn as the key/value table is, in the Theme's tokens, so a Variable
looks the same here as in Headers: the 24 pt `backgroundRecessed` header row, 28 pt rows on
`background`, a 1 pt `border` between rows, the one vertical rule before Value, a 6 pt radius
outer border hugging the rows (scrolling once they reach the hint), `rowHover`, the `selection`
fill, Disabled Rows in `textDisabled`, the trailing row's placeholders in SF Pro 13
`textTertiary` at 60 %, and an edited cell outlined edge to edge in `focusRing` on
`background`. The Secret column's lock is `textTertiary` when open and `text` on a `selection`
pill when closed. The rest of the sheet (source list, name field, buttons) stays native. This
replaces a native table.

- **Writes.** Leaving a cell (Return, Tab, a click elsewhere) writes the whole file through the
  window; the enabled checkbox writes at once. Done only closes, and so does Esc; there is no
  Cancel, because nothing is held back to cancel.
- **Name field.** For an Environment it is an editable field above the table; for Globals a
  label. Leaving it renames the Environment: its secrets move first, then the file, and the
  Active Environment follows. A name another Environment has (ignoring case) is refused: the
  field reverts and an 11 pt system-red line under it reads "An Environment named “Prod”
  already exists."
- **+ and −.** + writes `environments/New Environment.json` (" 2", " 3"… when taken), selects
  it and focuses its name field. − trashes the selected Environment's file with no prompt and
  keeps its Keychain items; if it was active, No Environment is. − is off for Globals; with no
  Environments the list is Globals and +.
- **Import from Postman….** A third footer control at the list's trailing edge, away from + | −
  so those two stay together: borderless, 24 × 22, the `square.and.arrow.down` symbol, 13 pt
  medium, with the tooltip and accessibility label "Import from Postman…". It closes the sheet
  as Done does, focus going back to the field that had it, then runs what File ▸ Import from
  Postman… (⇧⌘I) runs: the open panel, then the Import sheet. Cancel in the open panel leaves no
  sheet open. The Environments sheet does not reopen afterwards (postman-export.md).
- **Export….** A context menu on an Environment's row in the source list, with that one item,
  "Export…". Globals and a row that does not decode (the warning-triangle ones) have no menu.
  It opens the Environment Export sheet below.
- **Name cell.** A name that is not a Variable name is refused, and so is one already in the
  set: the old name stays, nothing is written, and an 11 pt system-red line under the row reads
  "Names use letters, digits, _, - and . only." or "tenant is already in Staging." (".. in
  Globals."). The next edit clears it.
- **Deleting a row.** ⌫ on the selected row, or its context menu "Delete Variable": the file is
  rewritten without it; for a secret its Keychain item is then deleted.
- **A file that does not decode** (an Environment, or globals.json) is a read-only row with a
  warning triangle. Selecting it shows the reason ("Not valid JSON at line 3. Raccoon won't
  change this file.") in place of the table. It is never in the picker, never rewritten, and −
  still trashes it.
- **Secret column.** A closed lock for a Secret Variable, an open one for a plain one. A
  secret's value is a secure field showing 8 bullets whatever its length (a placeholder: the
  value is never read into the field); typing replaces the value in the Keychain on leaving
  the cell, and the file is not touched. The sheet reads each secret once as its rows load.
- **Secret toggle**: a lock button per row, 24 × 20. Off: open lock, secondary color. On:
  closed lock, pressed fill, the value is a secure field showing bullets. Turning it on writes
  the Keychain first, then rewrites the file without the value (variables.md order); turning
  it off rewrites the file with the value, then deletes the Keychain item. A row with no
  value can be locked: nothing goes to the Keychain until one is typed.
- **Keychain write fails**: the row stays as it was, and an 11 pt system-red line beneath it
  reads "Not saved. The Keychain refused the write (OSStatus −25308, …)." The file is not
  touched. With no readable raccoon.json it reads "Not saved. raccoon.json can't be read."
- **Keychain unreadable** for a secret: the value field reads "Not in the Keychain", and the
  Variable resolves as undefined everywhere else (one path, §4).
- Footer hint: "<Env> overrides Globals while it is the Active Environment. Secret values are
  kept in the Keychain; only their names are written to the Data Folder." For Globals the
  first sentence is "Globals apply whichever Environment is active." Done closes.

### Save Draft sheet (native)

"Save Request", Name field (focused, prefilled with nothing), Location pop-up listing
Collections and Folders as a path ("Payments API ▸ Webhooks", default: the last one used), and
Cancel · **Save**. With no Collections the pop-up offers "New Collection…", and the sheet adds
a "Collection" name field under it; Save creates that Collection, then the Request in it
(decided 2026-10-19, the smallest reading). Save is disabled until every field
shown has text. "The last one used" lasts while the app runs; it is not kept across relaunch.
Cancel, Esc and Save all give focus back to the Tab's URL field.

### Name sheet (native)

"New Collection", "New Folder" or "Rename", one Name field (focused, prefilled with the
current name for Rename), Cancel · **Rename**, or Cancel · **Create** for the two New
sheets. The button is disabled while the name is blank. A failed operation is an alert sheet:
"Couldn't rename “Refunds”: permission denied."

### Close confirmation (native)

A card sheet on the window (Open UI Q8), shown when closing a Tab with losable content (a
Dirty Tab or a non-empty Draft) while File ▸ Always Discard Unsaved Changes is off. It
replaces the `NSAlert` (decided 2026-10-28): an alert has no room for the checkbox and its (i).
The layout follows Postman's close card; the look is Raccoon's. §1 puts sheets in system
colors, so it is built like the Save Request and Name sheets: system label colors, native
buttons and checkbox, no Theme token and no accent of its own. These
sizes are the spec.

```
┌──────────────────────────────────────────────── 440 pt ─┐
│ Save changes?                                           │  16 pt top, 20 pt sides
│                                                          │  12 pt
│ **Create charge** has unsaved changes. Save these        │  13 pt, wraps, 400 pt
│ changes to avoid losing your work.                       │
│                                                          │  16 pt
│ ☐ Always discard unsaved changes when closing a Tab  ⓘ  │  checkbox, 4 pt, glyph
│                                                          │  20 pt
│ [Don't Save]                        [Cancel]  [ Save ]   │  8 pt between, 16 pt bottom
└──────────────────────────────────────────────────────────┘
```

- **Title**: "Save changes?", 13 pt semibold `labelColor`. There is no ✕ (removed
  2026-10-28): Cancel is already on the sheet.
- **Body**: 13 pt `labelColor`, wrapping at 400 pt. The name is the one the Tab shows
  (`WindowModel.name(of:)`), in semibold. A Request Tab: "<name> has unsaved changes. Save
  these changes to avoid losing your work." A Draft: "<name> hasn't been saved. Save it to a
  Collection to avoid losing your work."
- **Checkbox**: a native checkbox, "Always discard unsaved changes when closing a Tab", off
  each time the sheet opens. 4 pt after it, SF Symbol `info.circle` at 12 pt in
  `secondaryLabelColor`, whose tooltip reads "Closing a Tab with unsaved changes will not ask
  first. Quitting still keeps your Session." It is remembered only when Don't Save is pressed
  with it ticked; Save, Cancel and Esc forget it (tabs.md §close).
- **Buttons**: regular push buttons. Don't Save at the leading edge (destructive, ⌘D); Cancel
  (Esc) and **Save** (default, Return) at the trailing edge, 8 pt apart.

Save saves and then closes: a Request Tab through the window, a Draft through the Save
Request sheet; a failed write or Cancel in that sheet keeps the Tab open. Return saves, so no
key a hand rests on discards work (decided 2026-10-19). A second ⌘W while the sheet is up asks
nothing more. Cancel and Esc keep the Tab and give focus back to where it was.

### Force close confirmation (native)

A card sheet on the window, shown by Force Close All Tabs when at least one Tab is Dirty or a
non-empty Draft (decided 2026-10-28, after Postman's). Built like the Close confirmation: 440 pt
wide, 16 pt top and bottom, 20 pt sides, system label colors, native buttons. No ✕, no
checkbox.

```
┌──────────────────────────────────────────────── 440 pt ─┐
│ Confirm force close                                     │
│                                                          │
│ 2 Tabs have unsaved changes. Your changes will be lost   │
│ if you force close these Tabs. Are you sure you want to  │
│ force close?                                             │
│                                          [Cancel] [Force Close] │
└──────────────────────────────────────────────────────────┘
```

- **Body**: the count is Tabs with something to lose, not every Tab: "1 Tab has unsaved
  changes. Your changes will be lost if you force close it. …" for one.
- **Buttons**: Cancel (Esc) and Force Close, 8 pt apart at the trailing edge. Force Close is
  filled `systemRed` with white 13 pt text and 6 pt corners, drawn by the button itself: the
  system's destructive tint shows only on a default button, and Return is not this one.
  Return confirms nothing, so no key a hand rests on discards work (as the Close
  confirmation). Focus starts on Cancel and returns to where it was on Cancel.

### Leave confirmation (native)

A card sheet shown when switching Workspace (a row of the pop-up, Open Workspace…, New
Workspace…, or removing the open one) while at least one Tab is Dirty or a non-empty Draft
(decided 2026-11-05). Built like the Close confirmation: 440 pt wide, 16 pt top and bottom,
20 pt sides, system label colors, native buttons. No ✕, and no checkbox: File ▸ Always
Discard Unsaved Changes does not apply here. It is shown on the window's top sheet, so it
also works from the Workspaces sheet.

```
┌──────────────────────────────────────────────── 440 pt ─┐
│ Save changes?                                           │
│                                                          │
│ 2 Tabs have unsaved changes. Save them before switching  │
│ Workspaces, or they will be lost.                        │
│                                                          │
│ [Don't Save]                    [Cancel]  [ Save All ]   │
└──────────────────────────────────────────────────────────┘
```

- **Body**: the count is Tabs with something to lose, not every Tab. For one: "1 Tab has
  unsaved changes. Save it before switching Workspaces, or it will be lost." The button reads
  **Save** for one Tab and **Save All** for more.
- **Buttons**: Don't Save at the leading edge (destructive, ⌘D); Cancel (Esc) and **Save**
  or **Save All** (default, Return) at the trailing edge, 8 pt apart. Return saves, so no key
  a hand rests on discards work.

Save All saves each Tab in strip order: a Request through the window, a Draft through the Save
Request sheet. A failed write or Cancel in that sheet stops there and the switch does not
happen; Tabs saved so far stay saved. Cancel and Esc give focus back to where it was.

### Empty state

The content area when no Tab is open (§9 Q1, reversed 2026-10-28). The tab strip stays, with
only its + button and the strip's usual `backgroundRecessed` and bottom `border`. Below it there
is no Breadcrumb, banner or URL bar: one view on `background` fills the rest, holding a column
centered both ways (12 pt higher than true center, so it reads centered under the strip):

```
                     ┌──────────┐
                     │  (face)  │   160 × 160 pt mark
                     └──────────┘
                                         24 pt
       New Tab                         ⌘T         rows 32 pt high, 280 pt wide
       Import from Postman…           ⇧⌘I
       Edit Environments…             ⌥⌃E
```

- **The mark**: the raccoon face from the app icon, `design/ui/assets/empty/RaccoonFace@2x.png`
  (320 × 320 px, shown at 160 × 160 pt), built by `design/ui/assets/build.py`: the icon's
  luminance becomes alpha, so the navy background and the dark mask patches drop out and the
  white and gray fur stays, then it is written as black with that alpha. It is a template
  image (`isTemplate`) tinted `textTertiary` at 40 % alpha, so every Flavor draws it in its
  own gray and nothing ships pre-colored. Decorative: no accessibility label.
- **Rows**: one per command Raccoon has, titled as its menu item is: New Tab (⌘T), Import from
  Postman… (⇧⌘I), Edit Environments… (⌥⌃E). The name is SF Pro 15 pt `textSecondary` on the
  leading edge; the shortcut is on the trailing edge as keycaps: each key a 20 pt-high chip,
  6 pt side padding, 4 pt radius, `backgroundElevated` with a 1 pt `border`, its glyph SF Pro
  12 pt `textSecondary`, 4 pt between chips. Hover fills the row `rowHover` with a 6 pt radius,
  8 pt side padding; there is no pressed state. A click sends the menu item's action up the
  responder chain (`NSApp.sendAction`), so a row does exactly what its menu item does.
- **Nothing else**: no Ask AI, no find-in-workspace, no protocol row. Those features do not
  exist in Raccoon.

The rows reach the keyboard only through the menus they mirror: ⌘T and the others work as
anywhere. These sizes are the spec.

### App icon

`design/ui/assets/icon/AppIcon.png`: 1024 × 1024 on a transparent canvas, the source artwork
scaled into the 824 × 824 icon body with a 100 pt margin on each side, as every macOS app
icon has, and continuous corners (a superellipse of exponent 5, which reads like a 185 pt
radius at that size). No shadow is added: the Dock draws its own. `design/ui/assets/build.py`
writes it from `Raccoon App Icon.png`, whose pixels are never edited. `scripts/make-app.sh`
turns it into `AppIcon.icns`, named by Info.plist, so the Dock, ⌘Tab and every alert show it
without Raccoon holding it in memory (theme.md).

### Postman Import sheet (native)

Opened by File ▸ Import from Postman… (⇧⌘I) or Import from Postman… in the sidebar's +
menu, after an open panel that takes one or many `.json` files. 620 pt wide. Behaviour and
the full mapping: [design/entry-points/postman.md](../entry-points/postman.md).

- **One row per file**, 38 pt: a checkbox, a kind glyph (Collection, Environment, Globals),
  the name in semibold, and under it what it holds ("Collection · 48 Requests in 6 Folders",
  "Environment · 12 Variables, 2 secrets", "Globals · 4 new · 1 kept as it is in Raccoon").
  The source file name is trailing, in secondary label color. A taken name reads
  "Prod → Prod 2" with "“Prod” already exists". A file Raccoon can't read is a disabled row:
  "Not a Postman export Raccoon reads", or "Can't be read: permission denied" for a file the
  disk refused. An empty Postman name shows the name Import writes ("New Collection").
- **What won't come across**: one line per ImportNote, with a count and, under it, the
  Requests it applies to (11 pt, at most one line, then "and 12 more"). Warnings (orange
  triangle) for losses: scripts, unsupported Auth, binary bodies, dynamic variables, file
  parts with only a name. Info (ⓘ) for changes that keep meaning: inherited Auth copied,
  Collection variables added to Globals. Path variables are not a note: they come across whole
  (postman.md).
- **Footer**: "Imports into ~/Raccoon. Secrets go to the Keychain." and Cancel · **Import**.
  Import is disabled when nothing is ticked or the Data Folder is not writable (the footer
  then says why: "Can't import into ~/Raccoon. The folder is not writable."). One line; a long
  path is cut in the middle.
- A rename is on its row and Globals' kept names on the Globals row, so neither is a note.
  Collection variables Globals already has are an info note: "1 Collection variable is not
  added: Globals already has it." The body grows to 440 pt, then scrolls.
- **Result** (the same sheet, replaced): "Imported 2 of 3", a check per landed item, and per
  failure a red line saying what was not written and that nothing of it was left behind; a
  Keychain refusal is an orange line. Done closes it and reveals the first imported
  Collection, selected, in the sidebar. If everything landed, the sheet closes straight away
  instead.

### Collection Export sheet (native)

Opened by File ▸ Export Collection… (enabled when the sidebar selection is in a Collection; no
shortcut; the item follows Import from Postman… and is disabled while a sheet is up) or Export… in a
Collection row's context menu, on that Collection. 440 pt wide, as tall
as its content: 20 pt margins, the title, a 12 pt gap, the steps, a 12 pt gap, the counts, the
notices, a 16 pt gap, **Cancel** · **Export…** (default, Return) at the trailing edge. Cancel and
Esc close; nothing has been written. Behaviour and the mapping:
[design/entry-points/postman-export.md](../entry-points/postman-export.md). The layout follows
Postman's export card, and the steps copy its checked steps, but only for work that happens.

- **Title**: `Export “Sociolla”`, 15 pt semibold, end-truncated, one line.
- **Steps**: three rows, 22 pt, each a 12 pt `checkmark` in `systemGreen`, 8 pt, then the text in
  13 pt label color. A row is drawn when its step has finished, so a step is never shown before
  its work is done:
  - “Read 41 Requests from ~/Raccoon” (the Data Folder's path abbreviated with `~`,
    middle-truncated; “Read 1 Request from …”)
  - “Formatted as Collection Format v2.1”
  - “Scanned for credentials”
- **Motion**: each row fades in on opacity only, 150 ms ease-out
  (`CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)`), starting when its step finishes
  and no sooner than 60 ms after the previous row's start. No artificial delay: a slow step is
  shown when it finishes. The counts, the credential warning and Export… all appear and enable in
  the third row's frame, together, so nothing is clickable before the warning shows. Reduce Motion: every row is drawn at its finish, with no fade. A read over
  150 ms shows the system small spinner, in the first row's check position, until that row's check
  appears (the rows' height is reserved, so nothing moves). The three rows'
  height is kept from the first frame, so rows appearing move nothing.
- **Counts**, drawn in the same frame as the third row, 13 pt, no motion of their own:
  “41 Requests · 11 Folders” (“1 Request · 1 Folder”, “0 Requests · 0 Folders”). The numbers are
  what the file holds; an empty Collection exports.
- **Credentials** (only when the scan found some), under the counts: an orange
  `exclamationmark.triangle.fill` 14 pt, “18 credentials in plain text” in 13 pt semibold
  (“1 credential in plain text”); under it, 12 pt secondary, “The file keeps them exactly as
  typed.”; under that, 11 pt secondary, the Requests' names in tree order, one per Request (the repeats of one Request's several
  findings are dropped; two Requests that share a name both show, unless they sit next to each
  other), joined by
  “ · ”, as many as fit one line, then “and 12 more”; a single name too long is cut in the middle
  so “and N more” stays readable (the Import sheet's rule). The sheet gives no way to remove
  them: Export never changes what a Request holds.
- **Not exported** (only when a Request file was skipped): an orange triangle and “1 file is not
  exported” (“3 files are not exported”), 13 pt semibold; under it, 12 pt secondary, “Raccoon
  can't read it as a Request, and won't change it.” (the same words for any number: “it” is the
  file as a kind); then the file names on one line, the same rule; its tooltip lists each file
  with the reason the unreadable row shows.
- **Dirty Requests** (only when a Dirty Tab holds one of the Collection's Requests): an ⓘ and “2
  Requests have edits in Tabs. Export uses what is saved.”, 12 pt secondary; for one,
  “1 Request has edits in a Tab. Export uses what is saved.” (Dirty's Avoid line bans “unsaved”)
- **Failure**: an 11 pt system-red line above the buttons, “Not exported. <reason>.”, the reason
  being the StoreError's (“Not exported. The folder “Archive” is not writable.”). The sheet stays
  and Export… works for another place.
- **Export…** opens an `NSSavePanel` as a sheet on this one, `.json`, named
  `Sociolla.postman_collection.json`, in the folder the panel last used. Cancel in the panel
  returns to this sheet. A saved file closes the sheet and gives focus back to where it was.

### Environment Export sheet (native)

Opened by Export… in an Environment's row in the Environments sheet. 380 pt wide: 20 pt
margins, the title, a 6 pt gap, a 12 pt secondary line, a 14 pt gap, the checkbox, its hint, a
16 pt gap, **Cancel** · **Export…** (default, Return).

- **Title**: `Export “Staging”`, 15 pt semibold, end-truncated. Under it “14 Variables, 2
  secrets” (“1 Variable, 1 secret”, “0 Variables, 0 secrets”), 12 pt secondary.
- **Include secret values**: a checkbox, 13 pt, off by default and off every time the sheet
  opens. Its hint, 11 pt secondary, indented to the label, reads “Secrets are exported empty.”
  when off and “Secret values are written to the file in plain text.” when on. With no secret in
  the Environment the checkbox and its hint are not drawn.
- **Export…** opens an `NSSavePanel` as a sheet, named `Staging.postman_environment.json`.
  Cancel in the panel returns here with nothing read from the Keychain. Ticked, the values are
  read from the Keychain only after the panel returns (a Keychain prompt never follows a
  Cancel), then the file is written.
- **Failure**: the same red line as the Collection sheet, “Not exported. <reason>.”; the sheet
  stays.
- **Result**, only when a Secret Variable could not be read (the same sheet, replaced): a green
  `checkmark` and “Exported to Staging.postman_environment.json” (13 pt, file name
  middle-truncated); under it, an orange triangle and “2 secrets could not be read from the
  Keychain and are empty in the file.” (“1 secret could not be read from the Keychain and is
  empty in the file.”), then the names in SF Mono 11 on one line, joined by “ · ”, then “and N
  more”; **Done** (default) closes. A Secret Variable that was never given a value is not named:
  there was nothing to read. With nothing to report the sheet closes at once after the write.

### Variable popover

A popover on `backgroundElevated` with `border`, 6 pt radius, 8 pt padding, 320 pt wide,
appearing after the system tooltip delay and instantly for the next token while one is open,
as Postman's does. Top to bottom:
- defined: the value in SF Mono 11 / 16, wrapping anywhere, in a box: `backgroundRecessed`,
  1 pt `border`, 4 pt radius, 6 × 4 pt padding. The box is as tall as the value up to five
  lines, then scrolls vertically; the text can be selected and copied, never edited;
- secret: a lock glyph and "Secret" in `variableSecret`, no box. The value is never shown;
- undefined: "Not defined in <Environment> or Globals" in `variableUndefined`, no box; "Not
  defined in Globals" when no Environment is active.

Under it, 6 pt down, a 20 pt footer: a 16 pt chip (4 pt radius, `selection`, 10 pt bold `text`)
reading "E" for an Environment or "G" for Globals, then the source ("Staging", "Globals") in 11 pt
`textTertiary`; an undefined name has neither. At the trailing end, **Variables in request →**
in 11 pt `accent`, underlined on hover: it closes the popover and opens the inspector on
Variables with that name's row selected.

It hangs 4 pt below the token (above it where the screen ends). The pointer may move from the
token into it to scroll or select: leaving the token closes it after 0.3 s unless the pointer
is over it, and leaving it closes it. A key press closes it (⌘C and ⌘A inside it copy and
select), as does a click or scroll outside it. It takes focus only when the value is clicked,
so ⌘C reaches it; closing gives focus back to the window.

### Variable suggestions

Typing `{{` in a field that takes Variables (URL field, table cells, raw body, Auth fields)
opens a list under the caret of the enabled Variables in scope, as Postman does. Typing on
filters it: case-insensitive, names that start with what was typed first, then the rest, each
group by name. No match, or no Variables, shows no list.

- Rows 22 pt: the name in SF Mono 12 `text`, and at the trailing end the source ("Staging",
  "Globals") in 11 pt `textTertiary`, "· Secret" after it for a secret. Never a value.
- Selected row: `selection` fill; the first row is selected when the list opens.
- `backgroundElevated`, `border`, 6 pt radius, a shadow; 4 pt inside padding; 200 to 320 pt
  wide, 8 rows tall at most, then it scrolls. It hangs 4 pt below the caret's line (above it
  where the screen ends) and takes no focus: the caret stays in the field.
- ↑ ↓ move the selection, Return or Tab writes `name}}` over what was typed (and over a `}}`
  already there), a click on a row does the same, Esc closes the list and nothing else. These
  keys keep their usual meaning while no list is open.
- It closes when the caret leaves the `{{name`, a character that cannot be in a name is typed,
  the field loses focus, or on a click outside it, a scroll or a ⌘ shortcut. The hover tooltip
  hides while it is open.

### Toolbar toggles

The sidebar toggle sits at the leading edge of the toolbar and the inspector toggle at the
trailing edge, as in Finder and Xcode: native toolbar buttons with SF Symbols
`sidebar.left` and `sidebar.right`, pressed (filled background) while their pane is open.
Both have View-menu items, "Show Sidebar" (⌃⌘S) / "Show Inspector" (⌥⌘I) (decided, Q12), which
read "Hide Sidebar" / "Hide Inspector" while the pane is open, docked or overlaid. The
inspector toggle comes right after the Environment control, with that control's 12 pt
trailing inset between them (§6 Environment picker).

### Sidebar filter (native)

An `NSSearchField` at the top of the sidebar, above "Collections", placeholder "Filter
Collections". Hidden while there are no Collections (screen 1).

- Filters as you type, no debounce, over Request, Folder and Collection names, case- and
  diacritic-insensitive. A name matches when it contains the query, or failing that, when
  the query's characters appear in it in order with gaps (Q19): "refnd" finds "List
  refunds". Unreadable rows match by file name.
- A node stays if it matches; ancestors open. Everything under a Collection or Folder stays
  only when its name contains the query. A container matched only with gaps keeps just the
  rows under it that match on their own.
- The match is highlighted with the system find-highlight color **and** set semibold, so it
  is not shown by color alone. A match with gaps highlights each run: "**ref**u**nd**s".
- Under the field, an 11 pt count in secondary label color: "4 matches in 1 Collection".
- No matches: "No Requests, Folders or Collections match “graphql”. Esc clears the filter."
- The clear button (ⓧ) and Esc restore the tree and the expansion state from before.
- Clicking a match opens it; the filter stays until cleared.
- ⌥⌘F focuses the field, listed as Edit ▸ Find ▸ "Filter Collections" (Q12). A hidden
  sidebar opens first: docked, or as the overlay in a narrow window. ⌘F stays Edit ▸ Find ▸
  "Find…", the system find bar over the body editor or Response body that has focus.

### Inspector

A right-hand pane, `NSSplitViewItem(inspectorWithViewController:)`, themed:
`backgroundRecessed`, 1 pt `border` on its leading edge, closed by default. A 34 pt header
(aligned with the tab strip) holds the pane's name on the left (12 pt semibold `text`) and,
on the right, a two-segment icon control: `curlybraces` for Variables and `terminal` for
Curl (SF Symbols), 30 × 22 pt each, the selected one on `selection`. Each segment has a
tooltip and an accessibility label with the pane's name. The last choice is remembered
in UserDefaults (decided, Q14).

**Variables pane** (a table whose values edit in place):
- Group titles 11 pt semibold `textTertiary`; rows 24 pt, name SF Mono 12 `text`, value SF
  Mono 12 `textSecondary`, end-truncated with the full value in a tooltip.
- Order: **Not defined** first, only when the Tab uses a name nothing defines: a
  `variableUndefined` title with an error glyph, each name in `variableUndefined` with its
  wavy underline and where the Tab uses it ("URL", "Headers", "Body", "Auth"). Then the
  **Active Environment** ("Staging · Active Environment"), names this Tab uses first. Then
  **Globals**, where an entry the Environment overrides is struck out in `textDisabled`.
- A Secret Variable's value is a lock glyph and "Secret" in `variableSecret`.
- No Environment: the group reads "No Environment · pick one in the toolbar"; Globals follow.
  No Globals: the group reads "No Globals.".
- The selected Variable: its row on `selection`, value in `text`, still one 24 pt table row
  with its rule. The Variable popover's link selects the row that resolves its name (never a
  struck-out Global) and scrolls to it; a click anywhere on a row selects that row, and a click
  on its value also edits it. One row at most is selected, until the next link or click.
- One click on a value edits it in place, in any row: a 20 pt SF Mono 12 field on
  `background` with the focus ring. Return or clicking away saves it to its file (the Active
  Environment's or globals.json), Esc puts it back; an unchanged value writes nothing. Names
  are not edited here.
  - A secret's field is a secure field that starts empty: what is typed replaces the
    Keychain value on Return; the old value is never read or shown. Empty writes nothing.
  - A Not defined row's field starts empty with the placeholder "Value": a value adds the name
    to the Active Environment, or to Globals under No Environment, and the row moves there.
  - Not saved: under the row, 11 pt `error`, "Not saved. <reason>." as in the Environments
    sheet; the value shown goes back to what the file holds.
- Footer: **Edit Environments…** opens the Environments sheet on the active set: names,
  enabling, secrets, new and deleted Variables stay there.

**Curl pane**:
- The curl command for the selected Tab, as Copy as Curl renders it, in SF Mono 11 / 17 on
  `background` inside a 6 pt-radius `border` box, colored by `Highlighter.curl`
  ([curl.md](../entry-points/curl.md#the-curl-pane) has the table):
  - `curl` and every flag (`-X`, `-H`, `--data-raw`, `-k`) in `curlFlag`;
  - the method after `-X` in its method token, as in the URL bar;
  - the URL in `text`, as in the URL field;
  - a header's name in `jsonKey`, its `:` in `jsonPunctuation`, its value in `jsonString`;
  - every other quoted value (body, form fields, cookies) in `jsonString`;
  - the quotes around a word and the `\` that ends a line in `jsonPunctuation`;
  - a Secret Variable as `{{name}}` in `variableSecret` with its dotted underline, over
    whatever it sits in.

  Only attributes change: the text is what Copy puts on the pasteboard. Wraps anywhere and
  scrolls; it never truncates, because Copy must match what is shown.
- Under it, 11 pt `textTertiary`: "Resolved with Dev. Disabled Rows are left out." With No
  Environment: "Resolved with Globals. Disabled Rows are left out."
- Footer: an **Include secrets** checkbox (off by default, not remembered) and **Copy**
  (primary). Include secrets fills secrets in the copied text only; the preview never shows
  them. With no command, the footer holds only Copy, disabled.
- Undefined Variables: an error glyph, "No curl command yet" in `statusFailed`, and the
  sentence naming every missing Variable ("charge_id and tenant_id are not defined in Staging
  or in Globals."); Copy disabled.
- An invalid URL: the same, with "After substitution the URL was <url>." as the sentence.
- An empty Draft (a blank URL): "Type a URL to see the curl command." in `textTertiary`.

### View ▸ Theme menu (native)

A submenu: a "Theme" header and the Themes (Catppuccin, checked); a "Light Appearance"
header and the light Flavors (Latte); a "Dark Appearance" header and the dark Flavors (Frappé,
Macchiato, Mocha). One check per section. Picking applies immediately.

## 7. Every error and state, and its place

Every entry of [e-where-it-breaks.md](../e-where-it-breaks.md) with a visible place:

| §4 entry | Place | Component |
|---|---|---|
| send: any SendError | Response pane | Response viewer, failed |
| cancelled | Response pane returns to idle | Response viewer, idle |
| timedOut(seconds) | Response pane: "No response after 60 s", or the Request Timeout that was set | failed |
| tooManyRedirects(followed) | Response pane: "Too many redirects", naming how many were followed | failed |
| untrustedCertificate | Response pane, host named, "Allow insecure TLS for this request" | failed |
| invalidURL | URL field outlined in `error`; Response pane quotes the substituted URL | URL bar, failed |
| fileMissing(path) | the multipart chip marked; message line names the path | Body editor |
| transport(code) | Response pane: description plus the code and host | failed |
| resolve: undefined(names) | red underlines already on screen; message line names every one; no spinner | URL bar, key/value table |
| Keychain unreadable | becomes undefined; the Environments sheet row says "Not in the Keychain" | Environments sheet |
| body not UTF-8, or image/* that does not decode | Response pane: binary | Response viewer |
| JSON did not parse | Raw, no message | Response viewer |
| unterminatedQuote | message line with the position; Tab unchanged | URL bar |
| noURL | message line: "No URL in this curl command." | URL bar |
| unknown flag | the Ignored note | URL bar |
| @file unreadable / not UTF-8 | the Ignored note names the file; a multipart part keeps its path | URL bar, Body editor |
| two commands pasted | the Ignored note: "2 more commands" | URL bar |
| Data Folder root not writable | window banner with Open Workspace…; sidebar empty | Banners, Sidebar |
| remembered Workspace missing or unreadable | window banner, not readable, with Open Workspace… and Remove from List; one empty Draft | Banners, Workspace pop-up |
| raccoon.json undecodable | its secrets read as undefined; setting one: the sheet row says "raccoon.json can't be read" | Environments sheet |
| New Workspace… on an existing name, or can't create | alert sheet with the reason; nothing written | Workspace pop-up |
| Session of a removed Workspace not deleted | logged only | — |
| file undecodable | unreadable sidebar row with reason and Reveal in Finder | Sidebar rows |
| duplicate RequestID | the second is an unreadable row: "Same id as …" | Sidebar rows |
| write failed | Tab banner "Not saved", Tab stays Dirty | Banners |
| file deleted under a Tab | Tab banner "Deleted on disk", the Tab becomes a Draft (italic) | Banners, Tab |
| Breadcrumb: no index entry for the Tab's Request | the last known segments stay; none: the Tab's title alone | Breadcrumb |
| Breadcrumb: a segment's path has no sidebar row | the sidebar shows, nothing is selected, nothing is said | Breadcrumb, Sidebar |
| Breadcrumb: too narrow | the middle becomes "…", then the names truncate; tooltips hold the full text | Breadcrumb |
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
| Postman Export: save panel cancelled | back on the Export sheet; nothing written, no Keychain read | Collection or Environment Export sheet |
| Postman Export: target not writable, write fails | red line “Not exported. <reason>.”; the sheet stays | Collection or Environment Export sheet |
| Postman Export: a Request file that does not decode | “N files are not exported”, named; Export… still enabled | Collection Export sheet |
| Postman Export: credentials found | “18 credentials in plain text”, the Request names; Export… still enabled | Collection Export sheet |
| Postman Export: a Request that is Dirty in a Tab | an info line, “Export uses what is saved” | Collection Export sheet |
| Postman Export: Keychain refuses a secret value | the result names it; it is empty in the file | Environment Export sheet |
| Postman Export: Reduce Motion | the step rows are drawn at once, no fade | Collection Export sheet |

## 8. Worst case (break-ui)

Run on every screen with the worst-case data (including 0 B, binary and missing
files): 30 Tabs, Japanese and emoji names, PROPFIND, a 2,048-character URL, 60 headers, a
1.2 KB JWT with no spaces, a 20.4 MB body, an unreadable file with a long name. Checked
visually in headless Chrome at 2120 px.

### What broke, and the fix (all applied)

| # | Severity | Field | Worst-case value | What happened | Fix |
|---|---|---|---|---|---|
| 1 | Broken | sidebar unreadable row | `Create charge (conflicted copy 2026-10-14).json` | the Reveal in Finder text button took the row; the name showed as "Creat…" | icon-only Reveal button (20 × 18) with label and tooltip; the reason moves to its own line |
| 2 | Broken | status line | `511 Network Authentication Required`, `20.4 MB` | code, time, size and the Pretty note each wrapped onto two lines | `nowrap` on every status-line item; only the reason truncates (`min-width: 0`), never the code, time or size |
| 3 | Ugly | Tab | 6 Tabs in a 768 pt content area | a later `min-width: 0` overrode the 104 pt minimum; every Tab shrank to "List c…" including the selected one | removed the override; the selected Tab keeps 168 pt |
| 4 | Ugly | sidebar method badge | `PROPFIND`, `OPTIONS` | the 38 pt badge cut them to "PROPFI…" | 52 pt badge, end-truncated beyond 8 characters (left-aligned since the indentation pass, §6 Sidebar rows) |
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
   2026-10-19: closing the last Tab opens an empty Draft, so the editor always has a Tab.
   **Reversed 2026-10-28:** closing the last Tab leaves no Tab, and the content area shows
   the empty state (§6 Empty state). A Draft that appears by itself after ⌘W reads as the
   close not working, and it was written into every Session. A Session of zero Tabs relaunches
   with zero; a first launch with no Session file still opens the empty Draft, so a new
   user sees the URL bar first (surfaces.md §4/§5, tabs.md §close and §relaunch).
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
5. **Shortcut to open the Environments sheet.** variables.md gives ⌃E to the picker. Decided
   2026-10-23: ⌥⌃E opens the sheet, listed as View ▸ Edit Environments….
6. **`success` has no surface.** The prompt requires the token and the JSON carries it, but
   v1 has no success message: a save clears the dot, a Curl Import fills the Tab. Candidates:
   a "Copied" confirmation for Copy as Curl, or a short "Imported from curl" note when nothing
   was ignored. Decided 2026-10-19: neither. v1 shows no success message, and the token stays
   in the Theme unused.
7. **Corrupt Session.** §4 renames the file to `sessions/<key>.corrupt-<date>.json` and starts
   empty. Should the empty window say so (a one-time banner with Reveal in Finder), or stay
   silent? Decided 2026-10-19: silent. The file is renamed and logged, and the window opens
   with one empty Draft, as on first launch.
8. **Close confirmation** (Save · Don't Save · Cancel) is a native alert;
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
12. **Shortcuts for the new panes.** Decided 2026-10-24: ⌥⌘F focuses the sidebar filter
    (Edit ▸ Find ▸ Filter Collections) and ⌘F stays find-in-body (Edit ▸ Find ▸ Find…, the
    system find bar); ⌥⌘I shows or hides the inspector (View ▸ Show Inspector) and ⌃⌘S the
    sidebar (View ▸ Show Sidebar, the system default).
13. **What the filter matches.** Decided 2026-10-19: names only. Collection,
    Folder and Request names, and an unreadable row's file name. Matching the method and URL
    too ("POST /refunds") was declined: it would find Requests named badly, at the cost of
    noisier results.
14. **Inspector state across relaunch.** Decided 2026-10-24: whether it is open, its width
    and Variables vs Curl live in UserDefaults. The Session is for Tabs and does not change
    when only the inspector changes.
15. **Format on paste or on save.** Decided 2026-10-16: Format is manual only, from the
    Format button or ⇧⌥F. Formatting on save would rewrite what the user typed into the file
    in git, and formatting on paste would change text the user did not ask to change.
16. **Re-importing a newer Postman export.** Import never overwrites, so a second import makes
    "Payments API 2". A merge (match by Postman item id, update changed Requests, keep
    Raccoon-side edits) is the obvious next step for people who keep using Postman in
    parallel; it needs its own design. Decided 2026-10-25: v1 never overwrites; the merge is
    out of v1.
17. **Postman's data-dump zip.** Settings ▸ Export Data gives a zip of every Collection and
    Environment. v1 asks the user to unzip it and pick the files; reading the zip directly is
    a small addition at the boundary. Decided 2026-10-25: v1 opens `.json` files only; the user
    unzips.
18. **Drag and drop.** Dropping Postman `.json` files onto the sidebar could open the same
    sheet. Decided 2026-10-25: not in v1. Import opens from File ▸ Import from
    Postman… (⇧⌘I) and the sidebar's + menu only.

19. **Fuzzy matching in the sidebar filter.** A query that is not a substring of any name,
    such as "refnd" for "List refunds" or "crch" for "Create charge", found nothing. Decided
    2026-10-28: a name matches when it contains the query, or failing that, when the query's
    characters appear in it in order (a subsequence). Q13 still holds: names only. Results
    keep tree order, so nothing ranks them. A Collection or Folder keeps everything under it
    only on a substring match; a gap match on a long container name is usually an accident
    ("pai" in "Payments API"), so there it keeps only the rows that match on their own.
    Swapped or wrong letters ("refnuds") and queries across levels ("pay ref") still find
    nothing.

20. **Postman Export.** Decided 2026-11-06, with the user: an Environment's Secret Variables are
    written `type: "secret"` with an empty value unless the sheet's Include secret values box
    is ticked (off by default), and the Keychain is read only after the save panel returns. A
    Collection's credentials are listed, never removed or masked: the file is exactly what the
    Requests hold. The Collection sheet's steps are Postman's checked steps, drawn only for
    work that has finished, 60 ms apart, opacity only. The Environments sheet gets Import from
    Postman…, which closes it and runs File ▸ Import from Postman…. Raccoon has no Collection
    variables, so an exported Collection has no `variable`. Settled in the design pass, not yet
    confirmed with the user: a
    Request file that does not decode is skipped and listed, never blocks; the scan counts
    Disabled Rows and not Cookies, and an empty `authorization` value counts so the example
    gives Postman's 18; output is sorted-keys and indented, so it diffs; the Environments sheet
    is not reopened after an import.

### Docs pane

The Docs section's pane: one NSTextView filling it, 16 pt padding, `background`, no line
numbers. Body text is the system font 13 pt in `text`. Markdown is styled in place and the
marks stay, in `textTertiary`: `#` headings at 20, 17 and 15 pt semibold for levels 1, 2 and 3+;
`**bold**` semibold; `*italic*` italic; `` `code` `` and fenced blocks in SF Mono 12 on
`backgroundRecessed`; list markers and `>` in `textSecondary`, a quote's text in `textSecondary`;
`[text](url)` text in `accent`, ⌘-click opens an `http`/`https` URL. Empty: the placeholder
"Notes for this Request, in markdown." in `textDisabled`. Undo, Find (⌘F, the system find bar)
and spelling are NSTextView's own.

### Example pane

What an Example Tab shows in place of the URL bar, RequestEditor and Response viewer. A 44 pt
header row, 12 pt side padding: the name field (fills), "Status" with a 64 pt numeric field
(100–599) and its reason phrase in `textTertiary` ("OK"), "Delay" with a 64 pt field and "ms".
Under it a Section bar: Headers (with its count) · Body. Headers is the key/value table. Body
is the raw text editor, coloured by the Example's Content-Type (JSON, XML, else plain); a
`.bytes` body is the Hex view, read-only, with "Replace from File…" and "Save Body…" in its
toolbar. A status out of range is clamped when the field ends editing.
