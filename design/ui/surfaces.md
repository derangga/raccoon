# Surfaces

Part of the [Raccoon UI](./design-system.md). The interface graph from
`effect-swift` `references/design-graph.md`: surfaces, the moves between them,
every void state, and what each surface needs before it may exist. Domain words are from
[CONTEXT.md](../../CONTEXT.md); failures are from [§4](../e-where-it-breaks.md).

**Job:** turn what the user typed or pasted into exactly one HTTP request, send it, and see
what came back, without the app adding or hiding anything.

## §1 Surfaces, units, states, moves

```
Window                          one, native chrome
  Toolbar                       native: sidebar toggle (leading), title, Environment picker,
                                inspector toggle (trailing)
  Sidebar                       native material: the Collection tree
    SidebarFilter               native search field, "Filter Collections"
    unit: SidebarRow            Collection · Folder · Request · Unreadable
  Content                       themed
    TabStrip                    unit: Tab
    TabBanner                   Changed on Disk · Deleted on disk · Not saved
    URLBar                      MethodPopUp · URLField · SendButton
    MessageLine                 under the URL bar: Curl Import error · Ignored note ·
                                Undefined Variables
    RequestEditor               sections: Params · Headers · Body · Auth · Cookies · Settings
      unit: KeyValueRow         Params, Headers, Cookies, form and multipart fields
      BodyEditor                Body Type picker, text editor, multipart rows
      AuthSection               None · Basic · Bearer
      RequestSettings           three checkboxes
    Split                       draggable divider
    ResponseViewer              StatusLine · Body (Pretty | Raw) · Headers
  Inspector                     themed, right of the content, closed by default
    VariablesPane               what the selected Tab resolves against, read-only
    CurlPane                    Copy as Curl of the selected Tab, live, with Copy
  WindowBanner                  Data Folder not writable, the one global failure
Overlays
  VariableTooltip               hover on {{name}}
  EnvironmentsSheet             native sheet
  SaveDraftSheet                native sheet
  PostmanImportSheet            native sheet: the plan, the notes, then the result
  CloseConfirm                  native alert: Save · Don't Save · Cancel
  ThemeMenu                     native menu, View ▸ Theme
```

**States** (enumerated, nothing improvised):

| Unit | States |
|---|---|
| Tab | rest · hover · selected · Dirty · Draft · sending · Changed on Disk · combinations of the last four |
| KeyValueRow | rest · hover · editing (focus ring) · Disabled Row · trailing empty row |
| `{{name}}` token | defined · secret · undefined |
| SidebarRow | rest · selected · unreadable (decode failure, unknown version, duplicate id) |
| SendButton | Send · Cancel (while sending) |
| URLField | rest · focus · invalid (outlined after an invalidURL send) |
| Multipart part | text · file · file missing |
| Secret toggle | plain · secret · save failed |

**Moves:** open a Request (sidebar click) · new Tab (⌘T) · select Tab (click, ⌘1…9, ⌃⇥) ·
close Tab (⌘W, ✕) · type in the URL bar · paste curl · edit a row · toggle a row ·
pick Body Type · send (⌘↩) · cancel (⌘., Cancel) · switch Pretty/Raw · switch Body/Headers ·
save (⌘S) · save Draft (⌘S on a Draft, sheet) · Reload · Keep Mine · pick Environment (⌃E,
pop-up) · open Environments sheet · edit / mark secret · pick Theme or Flavor · Choose
Folder… · Reveal in Finder · Allow insecure TLS for this request · filter the sidebar (type,
Esc clears) · toggle the inspector · switch Variables / Curl · Copy · Include secrets ·
Edit Environments… (from the Variables pane) · Import from Postman… (File menu, ⇧⌘I, the
sidebar's + menu) · untick a file · Import.

## §2 C: the flow graph

```
-> launch
  -> Window                                      N: Session read, Data Folder scanned
    -> Sidebar (tree)                            V: empty -> "No Collections yet" + path
    -> Content with the restored Tabs            V: no Session -> one empty Draft Tab
-> compose
  -> TabStrip: select or ⌘T
  -> URLBar: type, or paste curl
    -> paste curl -> RequestEditor filled        V: error / ignored -> MessageLine
  -> RequestEditor: rows, Body, Auth, Settings
-> send ⌘↩
  -> resolve                                     V: undefined -> MessageLine, no spinner
  -> ResponseViewer .sending (after 150 ms)
  -> ResponseViewer .received                    V: failed / binary / empty / raw-only
-> keep
  -> ⌘S on a Request -> Tab clean                V: write failed -> TabBanner, stays Dirty
  -> ⌘S on a Draft -> SaveDraftSheet -> Tab becomes the Request, row appears in Sidebar
-> the world changes
  -> file changed under a Dirty Tab -> TabBanner Changed on Disk -> Reload | Keep Mine
  -> file deleted under a Tab -> TabBanner Deleted on disk, Tab is a Draft
-> find
  -> SidebarFilter: type -> the tree narrows to matches, parents open
                                                 V: no matches -> one sentence + Esc hint
  -> click a match -> openRequest; the filter stays until cleared
-> inspect
  -> inspector toggle -> VariablesPane | CurlPane for the selected Tab
    -> VariablesPane                             V: undefined names first; No Environment
      -> Edit Environments… -> EnvironmentsSheet
    -> CurlPane -> Copy                          V: undefined -> no command, Copy disabled
-> Variables
  -> Environment picker -> every highlight re-runs, the inspector re-renders
  -> EnvironmentsSheet -> edit, mark secret      V: Keychain failed -> row message
-> move from Postman
  -> Import from Postman… -> open panel, many .json -> PostmanImportSheet (the plan)
                                                 V: not a Postman export -> that row, disabled
                                                 V: notes -> "What won't come across"
  -> Import -> the result, then the sidebar reveals the first new Collection
                                                 V: a Collection failed -> named in the result
-> appearance
  -> ThemeMenu -> content re-reads tokens
  -> system appearance flips -> Flavor for that appearance
```

Every node above appears on a screen in `mockups/` or in a component spec in
`design-system.md`. No screen exists that is not on this graph.

## §3 Cardinality

| Surface | Shape | Must survive |
|---|---|---|
| Sidebar | many, a tree | 0 Collections, 1, 40 Collections × 500 Requests; names in any script |
| SidebarFilter results | many, a pruned tree | 0 matches, 1, 2,000 matches (scrolls; the count line says how many) |
| VariablesPane | many, grouped | No Environment, 0 Globals, 200 Variables (scrolls), values of any length (end-truncated, full value in a tooltip) |
| CurlPane | one record, live | a 2,000-character URL and a 20 KB body: wraps anywhere, scrolls, Copy gives the exact text |
| TabStrip | many, ordered | 1 Tab, 30 Tabs (scrolls past the 104 px minimum, selected kept in view) |
| KeyValue table | many | 0 rows (trailing row only), 60 rows (scrolls, header sticky) |
| URLBar, RequestEditor | one record, the selected Tab | a 2,000-character URL on one line |
| ResponseViewer | one record, **live while sending** | 0 B, 20 MB (Raw only above 5 MB), binary |
| StatusLine elapsed time | live while sending | ticks every 100 ms, tabular figures so it does not jitter |
| EnvironmentsSheet | list + detail | no Environments (Globals only), secrets the Keychain cannot read |

## §4 V: void states and where each is shown

Each row is a designed state. "Place" is the surface the user is already looking at, per
§4's rule that every escape is shown where it happened.

| Surface | Empty | Loading | Partial | Error | Denied |
|---|---|---|---|---|---|
| Sidebar | "No Collections yet." + Data Folder path + New Collection | none: the scan is synchronous at launch (§7 of design/) | unreadable rows inline among good ones, with the reason and Reveal in Finder | Data Folder not writable: WindowBanner, sidebar shows the empty text | n/a |
| SidebarFilter | placeholder "Filter Collections"; hidden while there are no Collections | n/a: synchronous | n/a | n/a | no matches: "No Requests, Folders or Collections match “q”. Esc clears the filter." |
| VariablesPane | No Environment: the group says so and points at the toolbar; Globals still listed; no Globals: "No Globals." | n/a | disabled Variables are not listed; overridden Globals struck out | undefined names the Tab uses, first, in `variableUndefined`, with where each is used | secret: "Secret", never the value |
| CurlPane | empty Draft: `curl ''` is not shown; the pane says "Type a URL to see the curl command." | n/a | secrets stay `{{name}}` | undefined: "No curl command yet" + the names; Copy disabled | n/a |
| TabStrip | proposed never empty: closing the last Tab opens an empty Draft (Open UI Q1) | n/a | n/a | n/a | n/a |
| Tab | empty Draft: italic "Draft" | sending: spinner replaces the method badge after 150 ms | n/a | Changed on Disk glyph; Deleted on disk turns it into a Draft | n/a |
| TabBanner | absent | n/a | n/a | Changed on Disk (Reload · Keep Mine), Deleted on disk (Dismiss), Not saved (Dismiss) | n/a |
| URLField | placeholder "Enter a URL, or paste a curl command" | n/a | n/a | invalidURL: red outline + Response pane message quoting the substituted URL | n/a |
| MessageLine | absent | n/a | Ignored note: `Ignored: --retry, -s`, "2 more commands", unreadable @file | unterminatedQuote (position), noURL, Undefined Variables (every name) | n/a |
| KeyValue table | trailing empty row with grey "Name" / "Value" | n/a | Disabled Rows dimmed and unchecked | undefined `{{name}}` red wavy underline in the cell | n/a |
| BodyEditor | Body Type none: "This request has no body." | n/a | n/a | multipart file missing: chip outlined red + MessageLine at send | binary @file: Curl note, body none |
| ResponseViewer | idle: "Send a request to see the Response here." + ⌘↩ | sending: spinner, live elapsed, Cancel in the URL bar | Raw shown first while Pretty is computed off-main; above 5 MB Pretty is disabled with "Pretty is off above 5 MB" | failed: title + detail + the one fix if there is one (Allow insecure TLS); timedOut; transport code | n/a |
| ResponseViewer Body | 0 B: "Empty body." | as above | not JSON/XML or did not parse: Raw, no error | n/a | binary: "Binary body, N KB …" |
| ResponseViewer Headers | none: "No headers." | n/a | wire order can't be kept (environment-facts.md): rows sorted by name, footer "macOS merges repeated headers and doesn't keep their order." | n/a | n/a |
| VariableTooltip | n/a | n/a | n/a | undefined: "Not defined in <Env> or Globals" | secret: "Secret", the value is never shown |
| EnvironmentsSheet | Globals only, no Environments: list shows Globals and "+" | n/a | Keychain unreadable: the secret's row says "Not in the Keychain" and resolves as undefined | SecretStore.set failed: row message with the OSStatus, file untouched | n/a |
| PostmanImportSheet | no file picked: the sheet does not open (Cancel in the open panel) | parsing is pure and fast; for a large export the rows show a spinner until counted | some files are not Postman exports: their rows are disabled with the reason, the rest import | a Collection fails to write: the result names it, says nothing of it is left behind, the others landed; a secret the Keychain refused is imported with no value | Data Folder not writable: Import disabled, the reason in the footer |
| SaveDraftSheet | no Collections: Location pop-up offers "New Collection…" only | n/a | n/a | write failed: sheet closes, TabBanner Not saved, Tab stays a Draft | Data Folder not writable: ⌘S on a Draft shows the WindowBanner instead of the sheet |
| Environment picker | "No Environment" | n/a | Active Environment file gone at relaunch: "No Environment" (§4) | n/a | n/a |
| ThemeMenu | n/a | n/a | n/a | unknown stored Theme: falls back to Catppuccin Latte / Mocha, silently | n/a |

**Denied** is almost empty by construction: Raccoon has no accounts and no permissions. The
two cases are a binary body and a secret value, and both say why instead of showing nothing.

## §5 N: what each surface needs

| Surface | Needs, satisfied on the edge that reaches it |
|---|---|
| RequestEditor, URLBar, ResponseViewer | a selected Tab. There is always one if Q1 is accepted |
| TabBanner Changed on Disk | `tab.isChangedOnDisk`, which only `filesChanged` or relaunch sets |
| Save on a Request | `tab.source == .request`; on a Draft the same ⌘S routes to SaveDraftSheet |
| SaveDraftSheet | a writable Data Folder; otherwise the WindowBanner shows and the sheet does not open |
| Allow insecure TLS button | the failure is `untrustedCertificate`; never drawn for other errors |
| Cancel | `.sending`; the Send button becomes Cancel only then |
| Pretty | a parsed body ≤ 5 MB; above it the control is shown disabled with its reason, because hiding it would hide why the body looks raw |
| VariableTooltip | pointer over a `{{name}}` range in a field that takes Variables |
| SidebarFilter | at least one Collection; with none it is hidden, not disabled |
| Inspector | a selected Tab; width for 280 pt beside an editor of at least 480 pt, otherwise it overlays the content edge (decided, Q2) |
| Include secrets | the Curl pane; it changes only the copied text |
| Window minimum size | 760 × 480, Sidebar collapsing to an overlay below 960 wide, each Split pane keeping 160 pt (decided, Open UI Q2) |

## §7 Behavior: motion decisions (from `animate`)

| Motion | Frequency | Decision |
|---|---|---|
| Tab open / close | 100+/day, keyboard-driven (⌘T, ⌘W) | **None.** Tabs appear and vanish; neighbours reflow on the same frame |
| Sending spinner | tens/day | System `NSProgressIndicator` (spinning, small). Appears after 150 ms (design/behavior.md), with a 120 ms opacity fade so it doesn't pop. Kept under Reduce Motion: it is status, not decoration |
| Banner appearing | occasional | Purpose: prevent a jarring jump. `NSAnimationContext` group, 200 ms, ease-out (`CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)`), height from 0 plus opacity 0 → 1. Leaves the same way in 150 ms. Reduce Motion: no height animation, 150 ms opacity only |
| Inspector show / hide | tens/day, a toolbar click or a shortcut | The system's `NSSplitViewItem` inspector collapse, unmodified: it is native chrome behaviour and already honours Reduce Motion. No custom motion |
| Sidebar filter narrowing | every keystroke | **None.** Rows appear and vanish on the same frame as the keystroke |
| Pretty / Raw switch | tens/day | **None.** The text view swaps on the same frame |

## §8 Scope: attention

| Overlay | Acquires | Released by | Focus returns to |
|---|---|---|---|
| VariableTooltip | nothing (no focus) | pointer leaves, any key | n/a |
| EnvironmentsSheet | window focus | Done, Esc | the field focused before ⌃E or the menu |
| PostmanImportSheet | window focus | Import (then Done on the result), Cancel, Esc | the sidebar, on the first imported Collection; on Cancel, where it was |
| SaveDraftSheet | window focus | Save, Cancel, Esc | the URL field of the same Tab |
| CloseConfirm | window focus | Save, Don't Save, Cancel, Esc (= Cancel) | the Tab, or its neighbour if closed |
| SidebarFilter | keyboard focus | Esc clears the query; a second Esc, or Return on a match, gives focus back to the editor (Return also opens the match) | the editor of the selected Tab |
| Inspector | nothing: it is a pane, not an overlay, except when it overlays a narrow window (Q2), where clicking the content or Esc closes it | | |
| ThemeMenu | menu tracking | pick, Esc, click outside | where it was |
| TabBanner | nothing, it is inline | its buttons; Changed on Disk has no Dismiss because ignoring it is Keep Mine | n/a |

## §9 Swap N: the four runs

- **Day one** (screen 1): no Collections, one empty Draft, idle Response, No Environment.
  Every surface still says what it is for.
- **Year three** (worst-case board): 30 Tabs, names in Japanese with emoji, 60 headers,
  a 2,000-character URL, a 20 MB body, an unreadable file. Findings in design-system.md.
- **Least access**: a read-only Data Folder (WindowBanner, components board). Collections
  vanish; Drafts and sending still work, so the window stays an HTTP client.
- **Small and slow**: the 760 × 480 minimum (Q2), a send that times out after 60 s, Reduce
  Motion on. The graph re-routes (Sidebar collapses, banners cross-fade), it does not
  degrade.
