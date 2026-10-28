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
-> close(tabID)                                  ⌘W, the ✕
  -> tab.isDirty or tab is a non-empty Draft?
    -> ask: Save · Don't Save · Cancel           a sheet on the window (Open UI Q8)
                                                 escape: Cancel or Esc keeps the Tab
    -> Save -> collections.md save(tab)          a Draft: the Save Request sheet first;
                                                 closes only once the write landed
                                                 E: StoreError -> escape, Tab stays open
                                                 with Not saved
  -> TabModel.close()                            §8: cancels the in-flight send
  -> remove, select the neighbour               the last Tab -> newTab() (Open UI Q1)
  -> SessionWriter.schedule()
```

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
  -> select session.selected, else the first Tab, else newTab()
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
