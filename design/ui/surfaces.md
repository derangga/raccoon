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
    WorkspacePopUp              native pop-up button at the top: the open Workspace's title
    SidebarFilter               native search field, "Filter Collections"
    unit: SidebarRow            Collection · Folder · Request · Unreadable
  Content                       themed
    TabStrip                    unit: Tab
    Breadcrumb                  unit: segment: Collection · Folder · Request name, or a Draft's
                                title; "…" for collapsed Folders. Between the TabStrip and the URLBar
    EmptyState                  in place of the Breadcrumb, banner and editor while no Tab is
                                open: the raccoon mark and three command rows
    TabBanner                   Changed on Disk · Deleted on disk · Not saved
    URLBar                      MethodPopUp · URLField · SendButton
    MessageLine                 under the URL bar: Curl Import error · Ignored note ·
                                Undefined Variables
    RequestEditor               sections: Params · Headers · Body · Auth · Cookies · Settings
      unit: KeyValueRow         Params, Headers, Cookies, form and multipart fields
      PathVariablesTable        in the Params pane under the Query Params table, only while the
                                URL holds a Path Variable. unit: PathVariableRow: read-only Name,
                                editable Value; no checkbox, delete or trailing row
      BodyEditor                Body Type picker, text editor, multipart rows
      AuthSection               two columns, stacked below 600 pt: AuthTypePopUp (None · Basic
                                Auth · Bearer Token) and AuthNote on the left, the fields on the right
      RequestSettings           two checkboxes
    Split                       draggable divider
    ResponseViewer              StatusLine · Body (Pretty | Raw) · Headers
  Inspector                     themed, right of the content, closed by default
    VariablesPane               what the selected Tab resolves against; values edit in place
    CurlPane                    Copy as Curl of the selected Tab, live, with Copy
  WindowBanner                  Data Folder not writable or not readable, the one global failure
Overlays
  VariableTooltip               hover on {{name}}
  EnvironmentsSheet             native sheet
  SaveDraftSheet                native sheet
  NewWorkspacePanel             native NSSavePanel: name + location
  OpenWorkspacePanel            native NSOpenPanel: one folder
  PostmanImportSheet            native sheet: the plan, the notes, then the result
  CloseConfirm                  native card sheet: ✕ · body · Always discard checkbox (i) ·
                                Don't Save · Cancel · Save
  ThemeMenu                     native menu, View ▸ Theme
```

**States** (enumerated, nothing improvised):

| Unit | States |
|---|---|
| Tab | rest · hover · selected · Dirty · Draft · sending · Changed on Disk · combinations of the last four |
| KeyValueRow | rest · hover · editing (focus ring) · Disabled Row · trailing empty row |
| `{{name}}` token | defined · secret · undefined |
| PathVariableRow | rest · editing (focus ring on the Value cell); the Name cell is never editing |
| `:name` token (URLField) | one state: drawn while the name is in the URL |
| SidebarRow | rest · selected · unreadable (decode failure, unknown version, duplicate id) |
| Breadcrumb segment | rest · hover · last (the Request's name) · static (a Draft's title, "…") |
| SendButton | Send · Cancel (while sending) |
| URLField | rest · focus · invalid (outlined after an invalidURL send) |
| Multipart part | text · file · file missing |
| Secret toggle | plain · secret · save failed |

**Moves:** open a Request (sidebar click) · select a location (click a Breadcrumb segment) · new Tab (⌘T) · select Tab (click, ⌘1…9, ⌃⇥) ·
close Tab (⌘W, ✕) · type in the URL bar · paste curl · edit a row · toggle a row ·
pick Body Type · send (⌘↩) · cancel (⌘., Cancel) · switch Pretty/Raw · switch Body/Headers ·
save (⌘S) · save Draft (⌘S on a Draft, sheet) · Reload · Keep Mine · pick Environment (⌃E,
pop-up) · open Environments sheet · edit / mark secret · pick Theme or Flavor · switch
Workspace (pop-up) · New Workspace… · Open Workspace… · Remove from List · Reveal in Finder · Allow insecure TLS for this request · filter the sidebar (type, ⌥⌘F focuses,
Esc clears) · toggle the sidebar (⌃⌘S) · toggle the inspector (⌥⌘I) · find in a body (⌘F) · switch Variables / Curl · Copy · Include secrets ·
Edit Environments… (from the Variables pane) · Import from Postman… (File menu, ⇧⌘I, the
sidebar's + menu) · untick a file · Import.

## §2 C: the flow graph

```
-> launch
  -> Window                                      N: Session read, Data Folder scanned
    -> Sidebar (tree)                            V: empty -> "No Collections yet" + path
    -> Content with the restored Tabs            V: no Session -> one empty Draft Tab
                                                 V: a Session of zero Tabs -> EmptyState
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
-> switch Workspace
  -> WorkspacePopUp -> a Workspace               the open one's Session written, its Tabs
                                                 closed; the other's tree, Environments and
                                                 Tabs restored
                                                 V: can't be read -> WindowBanner, one empty
                                                 Draft, its Session untouched
  -> New Workspace… -> NewWorkspacePanel -> created, switched to
                                                 V: exists -> alert; can't create -> alert
  -> Open Workspace… -> OpenWorkspacePanel -> listed, switched to
  -> Remove from List -> forgotten; folder and secrets kept
-> find
  -> SidebarFilter: type -> the tree narrows to matches, parents open
                                                 V: no matches -> one sentence + Esc hint
  -> click a match -> openRequest; the filter stays until cleared
  -> click a Request row -> openRequest; keyboard focus stays in the outline (the selection stays
     emphasized), except that a field being edited in the Tab ends its edit first
-> locate
  -> Breadcrumb: click a segment -> Sidebar shows, the row's ancestors expand, a filter that hides
     it clears, the row is selected and in view; no Tab opens, focus stays in the Tab
                                                 V: Draft -> its title alone, not clickable
                                                 V: no row for the path -> the sidebar shows, nothing selected
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
| WorkspacePopUp | many, sorted by title | 1 Workspace, 30; two folders with the same name; a name of 120 characters (end-truncated to the sidebar width, full in the menu) |
| Sidebar | many, a tree | 0 Collections, 1, 40 Collections × 500 Requests; names in any script |
| SidebarFilter results | many, a pruned tree | 0 matches, 1, 2,000 matches (scrolls; the count line says how many) |
| VariablesPane | many, grouped | No Environment, 0 Globals, 200 Variables (scrolls), values of any length (end-truncated, full value in a tooltip) |
| CurlPane | one record, live | a 2,000-character URL and a 20 KB body: wraps anywhere, scrolls, Copy gives the exact text |
| TabStrip | many, ordered | 1 Tab, 30 Tabs (scrolls past the 104 px minimum, selected kept in view) |
| Breadcrumb | one record, the selected Tab's; 1 to many segments | a Draft (1), a Request at the Collection's top (2), 8 Folders deep (middle collapses into "…"), a 120-character name (end-truncated, tooltip), names in any script |
| KeyValue table | many | 0 rows (trailing row only), 60 rows (scrolls, header sticky; in the Params pane the pane scrolls and no header sticks) |
| PathVariablesTable | one row per name in the URL, in order | 0 names (the table and its label are absent), 30 names (the pane scrolls), a 200-character name (end-truncated, tooltip), a 2,000-character value (end-truncated) |
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
| WorkspacePopUp | one Workspace: its row, checked, and Remove from List ▸ disabled | n/a: the switch is as synchronous as launch | n/a | the open one can't be read: the pop-up still shows it; the WindowBanner says why | n/a |
| SidebarFilter | placeholder "Filter Collections"; hidden while there are no Collections | n/a: synchronous | n/a | n/a | no matches: "No Requests, Folders or Collections match “q”. Esc clears the filter." |
| VariablesPane | No Environment: the group says so and points at the toolbar; Globals still listed; no Globals: "No Globals." | n/a | disabled Variables are not listed; overridden Globals struck out | undefined names the Tab uses, first, in `variableUndefined`, with where each is used; an edit not saved: "Not saved. <reason>." under its row | secret: "Secret", never the value; its field starts empty |
| CurlPane | empty Draft: `curl ''` is not shown; the pane says "Type a URL to see the curl command." | n/a | secrets stay `{{name}}` | undefined: "No curl command yet" + the names; invalidURL: the same + the URL after substitution; Copy disabled | n/a |
| TabStrip | no Tab open: only the + button; the content area under it is the EmptyState. Closing the last Tab gets here, and so does relaunching a Session of zero Tabs (reversed 2026-10-28; it was "never empty", Open UI Q1) | n/a | n/a | n/a | n/a |
| EmptyState | the raccoon mark and three rows: New Tab ⌘T, Import from Postman… ⇧⌘I, Edit Environments… ⌥⌃E. ⌘T, the strip's +, a row, or opening a Request from the sidebar leaves it by opening a Tab | n/a | n/a | n/a | n/a |
| Inspector, no Tab open | Variables: no "used by this request" group; the Active Environment and Globals are listed and still edit. Curl: "Open a Tab to see its curl command." in `textTertiary`, Copy disabled, no Include secrets | n/a | n/a | n/a | n/a |
| Tab | empty Draft: italic "Draft" | sending: spinner replaces the method badge after 150 ms | n/a | Changed on Disk glyph; Deleted on disk turns it into a Draft | n/a |
| Breadcrumb | a Draft: its title alone, not clickable | n/a: derived from the index in memory | the middle collapsed into "…"; a name end-truncated, tooltip with the full name; last-known segments while the index has no entry for the Request | n/a: no segment can fail, and a click that finds no row selects nothing | n/a |
| TabBanner | absent | n/a | n/a | Changed on Disk (Reload · Keep Mine), Deleted on disk (Dismiss), Not saved (Dismiss) | n/a |
| URLField | placeholder "Enter a URL, or paste a curl command" | n/a | n/a | invalidURL: red outline + Response pane message quoting the substituted URL | n/a |
| MessageLine | absent | n/a | Ignored note: `Ignored: --retry, -s`, "2 more commands", unreadable @file | unterminatedQuote (position), noURL, Undefined Variables (every name) | n/a |
| KeyValue table | trailing empty row with grey "Name" / "Value" | n/a | Disabled Rows dimmed and unchecked | undefined `{{name}}` red wavy underline in the cell | n/a |
| PathVariablesTable | absent when the URL has no Path Variable; a Value cell shows the grey placeholder "Value" | n/a | n/a | undefined `{{name}}` in a Value: red wavy underline, and the Params count in red (the label, when there is no count) | n/a |
| BodyEditor | Body Type none: "This request has no body." | n/a | n/a | multipart file missing: chip outlined red + MessageLine at send | binary @file: Curl note, body none |
| ResponseViewer | idle: "Send a request to see the Response here." + ⌘↩ | sending: spinner, live elapsed, Cancel in the URL bar | Raw shown first while Pretty is computed off-main; above 5 MB Pretty is disabled with "Pretty is off above 5 MB" | failed: title + detail + the one fix if there is one (Allow insecure TLS); timedOut; transport code | n/a |
| ResponseViewer Body | 0 B: "Empty body." | as above | not JSON/XML or did not parse: Raw, no error | n/a | binary: "Binary body, N KB …" |
| ResponseViewer Headers | none: "No headers." | n/a | wire order can't be kept (environment-facts.md): rows sorted by name, footer "macOS merges repeated headers and doesn't keep their order." | n/a | n/a |
| VariableTooltip | n/a | n/a | n/a | undefined: "Not defined in <Env> or Globals" | secret: "Secret", the value is never shown |
| EnvironmentsSheet | Globals only, no Environments: list shows Globals and "+" | n/a | Keychain unreadable: the secret's row says "Not in the Keychain" and resolves as undefined | SecretStore.set failed: row message with the OSStatus, file untouched | n/a |
| PostmanImportSheet | no file picked: the sheet does not open (Cancel in the open panel) | parsing is pure and fast; for a large export the rows show a spinner until counted | some files are not Postman exports: their rows are disabled with the reason, the rest import | a Collection fails to write: the result names it, says nothing of it is left behind, the others landed; a secret the Keychain refused is imported with no value | Data Folder not writable: Import disabled, the reason in the footer |
| SaveDraftSheet | no Collections: Location pop-up offers "New Collection…" only | n/a | n/a | write failed: sheet closes, TabBanner Not saved, Tab stays a Draft | Data Folder not writable: ⌘S on a Draft shows the WindowBanner instead of the sheet |
| CloseConfirm | n/a: an empty Draft closes without it | n/a | n/a | Save fails: the sheet has closed, TabBanner Not saved, the Tab stays open | Always discard on: no sheet, the Tab closes; File ▸ Always Discard Unsaved Changes is checked and turns it off |
| Environment picker | "No Environment" | n/a | Active Environment file gone at relaunch: "No Environment" (§4) | n/a | n/a |
| ThemeMenu | n/a | n/a | n/a | unknown stored Theme: falls back to Catppuccin Latte / Mocha, silently | n/a |

**Denied** is almost empty by construction: Raccoon has no accounts and no permissions. The
two cases are a binary body and a secret value, and both say why instead of showing nothing.

## §5 N: what each surface needs

| Surface | Needs, satisfied on the edge that reaches it |
|---|---|
| RequestEditor, URLBar, ResponseViewer | a selected Tab. With none, the EmptyState takes their place (reversed 2026-10-28; it was "There is always one", Q1) |
| Breadcrumb | a selected Tab, and the window's index for a Request Tab. It reads nothing else. With none it is hidden with the editor |
| TabBanner | a selected Tab; with none it is hidden |
| Save, Close Tab, Copy as Curl, Show Tab N, Show Next / Previous Tab | a Tab to act on: with none they are disabled, never hidden |
| EmptyState | `selectedTab == nil`; nothing else |
| Breadcrumb segment, clickable | a target path: the Collection's, a Folder's, or the Request's own file. A Draft's title and "…" have none |
| TabBanner Changed on Disk | `tab.isChangedOnDisk`, which only `filesChanged` or relaunch sets |
| Save on a Request | `tab.source == .request`; on a Draft the same ⌘S routes to SaveDraftSheet |
| SaveDraftSheet | a writable Data Folder; otherwise the WindowBanner shows and the sheet does not open |
| Allow insecure TLS button | the failure is `untrustedCertificate`; never drawn for other errors |
| Cancel | `.sending`; the Send button becomes Cancel only then |
| Pretty | a parsed body ≤ 5 MB; above it the control is shown disabled with its reason, because hiding it would hide why the body looks raw |
| VariableTooltip | pointer over a `{{name}}` range in a field that takes Variables |
| WorkspacePopUp | always shown; Remove from List needs a row that is not the open Workspace |
| SidebarFilter | at least one Collection; with none it is hidden, not disabled |
| Inspector | the Curl pane needs a selected Tab; the Variables pane does not. Width for 280 pt beside an editor of at least 480 pt, otherwise it overlays the content edge (decided, Q2) |
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
| Breadcrumb change, hover, and the sidebar revealing a row | tens/day | **None.** The segments swap on the Tab switch's frame, hover fills at once, and the row is selected and scrolled into view without animating (`scrollRowToVisible`). The sidebar showing is the system's split-view collapse, unmodified |
| Pretty / Raw switch | tens/day | **None.** The text view swaps on the same frame |

## §8 Scope: attention

| Overlay | Acquires | Released by | Focus returns to |
|---|---|---|---|
| VariableTooltip | nothing until its value is clicked; then the panel, so ⌘C copies | pointer leaves the token and the popover, any other key, a click or scroll outside it, the link | n/a |
| EnvironmentsSheet | window focus | Done, Esc | the field focused before ⌃E or the menu |
| PostmanImportSheet | window focus | Import (then Done on the result), Cancel, Esc | the sidebar, on the first imported Collection; on Cancel, where it was |
| SaveDraftSheet | window focus | Save, Cancel, Esc | the URL field of the same Tab |
| CloseConfirm | window focus | Save (Return), Don't Save (⌘D), Cancel, Esc, ✕ (all three = Cancel) | the Tab, or its neighbour if closed; where it was on Cancel |
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
