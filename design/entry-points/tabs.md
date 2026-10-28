# §2 A — Tabs

New, switch, close, quit and relaunch. Milestone M3.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

## Ownership

```
WindowModel                          @MainActor @Observable, one per window (one window)
  tabs: [TabModel]                   order is the tab strip's order
  selected: TabID?
TabModel                             @MainActor @Observable, owns one Tab value and one
                                     in-flight send (§8)
TabViewController                    only the selected Tab has one. Switching Tabs swaps
                                     which TabModel the single editor is bound to
```

**Only the selected Tab has views.** The memory trade-off accepted in the design session is
per-Tab *state*: the definition, the baseline and the last Response. It is not per-Tab
`NSTextView`s. Ten Tabs cost ten `Tab` values and at most ten Response bodies, not ten editor
hierarchies. Switching rebinds one editor, and scroll position and selection are part of the
`TabModel` so they come back. Rebinding swaps the view's whole `NSTextStorage`: replacing the
characters of a large coloured storage in place takes minutes (environment-facts.md).

## Entry points

```
-> newTab()                                      ⌘T
  -> Tab(id: TabID(), source: .draft, definition: .empty, baseline: nil)
  -> insert after the selected Tab, select it
  -> SessionWriter.schedule()                    §7: coalesced
```

```
-> select(tabID)                                 click, ⌘1…8, ⌘9 the last Tab, ⌃⇥ ⌃⇧⇥
  -> editor.bind(tabModels[tabID])               no I/O, no copy
```

**A Request Tab's name is its Request's name, read from `DataFolderIndex` by RequestID**
(decided 2026-10-19). The name has one home, the file, so a rename in the sidebar or on disk
shows in the strip and the close prompt at once, and neither `Tab` nor the Session stores it.
A Draft's name is `Tab.title`: "Draft", else its URL's path. A Request Tab whose id the index
no longer has falls back to `Tab.title` until filesChanged turns it into a Draft.

**⌘9 is the last Tab**, as in Safari and Finder, and ⌃⇥ wraps at either end. Undo is one
stack for the window and its actions read whichever Tab is bound, so a switch clears it.

```
-> close(tabID)                                  ⌘W, the ✕, the Tab menu
  -> CloseMemory.alwaysDiscards()                R: UserDefaults "AlwaysDiscardOnClose",
                                                 read at every close so a change counts at
                                                 once. Not a Bool -> off, see §4
  -> CloseStep(hasLosableContent:alwaysDiscards:) pure: ask only when the Tab is Dirty or a
                                                 non-empty Draft and the preference is off
     .close -> TabModel.close() below, no sheet
    -> ask: Don't Save · Cancel · Save           the Close sheet on the window (Open UI Q8),
            + "Always discard unsaved changes    design-system §6 Close confirmation
              when closing a Tab"
                                                 escape: Cancel or Esc keeps the Tab;
                                                 the checkbox is forgotten
    -> Don't Save, checkbox ticked
      -> CloseMemory.remember(true)              R: UserDefaults; nothing else writes true
    -> Save -> collections.md save(tab)          a Draft: the Save Request sheet first;
                                                 closes only once the write landed. The
                                                 checkbox is forgotten
                                                 E: StoreError -> escape, Tab stays open
                                                 with Not saved
  -> TabModel.close()                            §8: cancels the in-flight send
  -> remove, select the neighbour               the last Tab -> no Tab, selected = nil:
                                                 the empty state below (reversed 2026-10-28)
  -> SessionWriter.schedule()                    a Session of zero Tabs is written as such
```

```
-> open the Tab menu                             right-click or double-click a Tab. Opens on
                                                 that Tab without selecting it
  -> New Tab                                     newTab(), as ⌘T
  -> Duplicate Tab -> duplicate(tabID)           a Draft holding the Tab's definition, inserted
                                                 right after it and selected; no baseline, so
                                                 never a second Tab on one Request
                                                 E: tabID gone -> escape: nothing happens
  -> Close Tab, Close Other Tabs, Close All Tabs close(scope, of: tab) below
  -> Force Close Tab                             TabModel.close(), no sheet: the quick path
  -> Force Close All Tabs                        losing = Tabs with hasLosableContent
     losing == 0, or CloseMemory.alwaysDiscards() TabModel.close() for each, no sheet
     else -> confirmForce(losing)                the Force close confirmation (design-system §6)
        Force Close -> TabModel.close() for each
        Cancel, Esc                              E: escape: nothing closes
-> close(scope, of: tab)                         scope .others is every Tab but this one,
                                                 .all every Tab
  -> close(tab) for each, in strip order         the single-Tab path above, one sheet at a time
     closed                                      -> the next Tab
     Cancel, or a Save that did not land         E: escape: stop; this Tab and the ones after it
                                                 stay, the ones already closed stay closed
```

**Close Other Tabs and Close All Tabs stop at the first "no"** (decided 2026-10-28). Cancel
on one Tab's sheet is a "not this one", and carrying on to the next Tab's sheet would ask
the user to answer for Tabs they just asked to be spared. Tabs closed before it stay closed:
they were closed with the user's answer or had nothing to lose. A hop of one turn separates
two sheets, because the first is still ending when the second is asked for.

**Closing the last Tab leaves the window with no Tab** (decided 2026-10-28, reversing Open
UI Q1, which opened an empty Draft so the editor always had one). `selectedTab` was already
optional; what read it as always present now has a state for none:

```
-> the empty state                               selectedTab == nil, observed like
                                                 showSelectedTab()
  -> ContentViewController.show(nil)             the EmptyState view in place of the
                                                 Breadcrumb, banner and TabViewController's
                                                 view; the TabStrip stays, + only
  -> TabViewController                           keeps its last TabModel, out of the window
                                                 and so out of the responder chain: Copy as
                                                 Curl finds no target and is disabled
  -> BreadcrumbBinding, TabBannerBinding         already read `selectedTab?`: a Draft's
                                                 "Draft" and no banner, both hidden
  -> InspectorViewController                     Variables: definition .empty, so only the
                                                 Active Environment and Globals; Curl: "Open a
                                                 Tab to see its curl command.", Copy disabled
  -> AppDelegate.validateMenuItem                Save, Close Tab, Show Tab N, Show Next and
                                                 Previous Tab disabled; ⌘S and ⌘W do nothing
  -> TabStripLayout(count: 0, selected: nil)     no Tab, + at the leading edge; no scroll
  -> SessionWriter                               tabs [], selected nil
-> leave it                                      ⌘T, the strip's +, an EmptyState row, or
                                                 openRequest from the sidebar
  -> newTab() / openRequest(id)                  inserted at the end, selected; the editor
                                                 is bound to it and shown again
```

An EmptyState row sends its menu item's action through the responder chain
(`NSApp.sendAction(_:to: nil, from:)`), so New Tab, Import from Postman… and Edit
Environments… run exactly the code their menu items run. Nothing here can fail: no E.

```
-> toggle File ▸ Always Discard Unsaved Changes  the way back, and the only other way in
  -> CloseMemory.remember(!alwaysDiscards())     R: UserDefaults
                                                 the item is checked while it is on
```

**Always discarding is reversible from the menu bar** (decided 2026-10-28). It is the one
path that throws work away without a prompt, so it has to be undoable, and Raccoon has no
Settings window. The smallest control is a checkable item under Close Tab in the File menu:
it sits next to the command it changes, it shows the state as a check without opening
anything, and unchecking it brings the sheet back on the next ⌘W. It is a preference of the
app, kept in UserDefaults like the inspector's state, never in a Session: it does not change
with the Workspace.

**A Draft is not Dirty, but closing a non-empty one still asks.** Dirty is defined against a
saved baseline and a Draft has none (CONTEXT, Dirty). The prompt is about losing work, so the
rule is "has content the user would lose", which for a Draft is `definition != .empty`. That
holds for Path Variables with no extra code: `pathVariables` is part of the definition, so a
changed value makes a Request Dirty, Changed on Disk compares it, and the Session's
`TabSnapshot` carries it for a Draft and a Dirty edit (boundary.md).

```
-> quit()                                        ⌘Q, logout, restart
  -> SessionWriter.writeNow(session)             boundary    R: SessionStore
                                                 E: unwritable -> escape: log, quit
                                                 anyway, see §4
  -> every TabModel.close()                      §8: after the snapshot, so a cancelled
                                                 send cannot change a Tab while it is read
```

**Quit does not prompt for Dirty Tabs.** The Session keeps Dirty edits and Drafts (decision
Q4 in the design session), so nothing is lost by quitting, and a prompt per Tab on ⌘Q would
punish the feature that makes it unnecessary.

```
-> relaunch()                                    applicationDidFinishLaunching, and after
                                                 switchWorkspace (workspaces.md), against
                                                 that Workspace's Session. Skipped when its
                                                 Data Folder can't be read
  -> SessionStore.read()                         boundary    R: SessionStore
                                                 nil -> the one empty Draft (board 01)
                                                 E: unreadable -> escape: log, start empty
  -> SessionFile.decode(data)                    E: undecodable -> escape: start empty
    -> SessionStore.setAside()                   rename to <key>.corrupt-<date>.json, log;
                                                 nothing on screen (Open UI Q7)
                                                 E: rename fails -> escape: log; the next
                                                 write replaces the file
  -> for each TabSnapshot
    -> source .request(id)
      -> DataFolderIndex.path(for: id)           from collections.md load
         found -> Tab, with baseline re-read from disk
                  disk == snapshot.baseline -> restored as it was
                  disk differs, snapshot not Dirty -> definition = disk, silently
                  disk differs, snapshot Dirty -> edits kept, isChangedOnDisk
         gone  -> Tab becomes a Draft, definition kept
    -> source .draft -> Tab as it was
  -> select session.selected, else the first Tab; a Session of zero Tabs restores zero:
                                                 the empty state (2026-10-28). No Session
                                                 file at all keeps the one empty Draft
  -> activeEnvironment by name               missing -> none, variables.md
```

```
-> restore the inspector                          applicationDidFinishLaunching (design-system
                                                 §9 Q14). UserDefaults, never the Session
  -> CompositionRoot.inspectorMemory(defaults)   boundary    R: UserDefaults
                                                 InspectorShown, InspectorWidth, InspectorPane
  -> MainSplitViewController(memory)             open as remembered, at the remembered width
                                                 clamped to 240–400; docked or overlaid as
                                                 the window allows (Q2)
  -> InspectorViewController(memory)             on the remembered pane
-> toggle, drag the divider, pick a pane         each change remembered at once
  -> memory.rememberShown / rememberWidth / rememberPane
```

**The Session is for Tabs.** Nothing the inspector does schedules a Session write, so a
Workspace's Session file does not change when only the inspector does. `NSSplitView`'s
`autosaveName` was not used: it writes only to the standard defaults, which tests cannot
swap, and it keeps `isCollapsed`, which is also true of an inspector open as an overlay.

**A relaunch compares baselines.** If a `git pull` changed a Request while Raccoon was not
running, the Tab's Dirty edits were made against the old file. That is exactly Changed on
Disk, so it reuses that state instead of inventing a second one.
