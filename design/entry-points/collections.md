# §2 A — Collections

The Data Folder, the sidebar tree, saving, and files that change underneath. Milestone M4.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

## Layout on disk

```
~/Raccoon/                             the Data Folder; Choose Folder… changes it
  globals.json                         Globals
  environments/
    Dev.json                           one Environment per file, name = file name
    Prod.json
  Payments API/                        a Collection: a top-level folder
    Create charge.json                 a Request: { "version": 1, "id": "…", "name": …, … }
    Refunds/                           a Folder, any depth
      List refunds.json
```

**Plain JSON files, not one database and not a custom format.** Files let users diff, review
and share Collections through git, as Bruno does. JSON through `Codable` rather than a DSL like
Bruno's `.bru` means there is no parser to write. The cost is that a save is atomic per file,
not per Collection, and this layout is now a format that has to stay readable (boundary.md).

The Session is **not** here. It lives in `~/Library/Application Support/Raccoon/session.json`,
because it holds Drafts and unsaved edits, and those must never show up in `git status`.

A Request's file name is its name, sanitised (`/` and `:` replaced by `-`). The name inside the
JSON is the one shown. Two Requests may share a name, so the file name gets ` 2` (then ` 3`) on
collision, compared without case because APFS is case-insensitive by default.

Within a Collection or Folder, Folders come first, then Requests and unreadable rows together,
each sorted by the name shown (`localizedStandardCompare`, as Finder sorts).

## Entry points

```
-> loadDataFolder()                              launch, before relaunch(): .16 looks
                                                 Request Tabs up in the index
  -> root = UserDefaults "DataFolder"            read by the composition root; absent ->
                                                 ~/Raccoon. R: DataFolderLocation (root,
                                                 open(root) -> DataFolderStore, remember)
  -> DataFolderStore.ensureExists(root)          boundary    R: DataFolderStore
                                                 E: unwritable -> escape: banner
  -> DataFolderStore.scan(root)                  boundary    -> DataFolderScan
                                                 E: unreadable -> escape: banner, as unwritable
  -> TreeDecoder.collections(scan)               pure: top-level folders but environments/
                                                 are Collections, deeper ones Folders, empty
                                                 ones too; top-level files are not Requests
     -> .request per decodable file              E: undecodable -> .unreadable row,
                                                    the file kept byte-for-byte
  -> DataFolderIndex(tree)                       pure: RequestID -> path, and duplicate IDs
                                                 duplicate -> escape: the second one is
                                                 .unreadable("duplicate id of …")
  -> FolderWatch.start(root)                     §8          R: FolderWatch
```

```
-> chooseDataFolder(root)                        Choose Folder… in the Data Folder banner
  -> the old withDataFolder scope ends           §8: its FolderWatch stream has ended
                                                 before the new one starts
  -> loadDataFolder(root)
  -> DataFolderLocation.remember(root)           only once it loaded: a folder that fails
                                                 keeps the banner and is not remembered
```

**There is no Settings window in v1** (decided 2026-10-19). Choose Folder… in the Data Folder
banner is the one way to change the root, so a working Data Folder cannot be moved until a
Settings window exists. The root is kept in UserDefaults under `DataFolder`, a path.

**A file Raccoon failed to read is never rewritten.** It shows as a warning row with Reveal in
Finder. Saving over a file the user hand-edited into a broken state would destroy the edit
that broke it, which is often the one they want back.

**Duplicate IDs are a git fact, not a bug.** Copying a Request file in Finder copies its id.
The index keeps the first by path order and marks the second, so "one Tab per Request" holds.

```
-> openRequest(requestID)                        click (or Return) on a sidebar Request row
  -> window.tab(showing: requestID)?             one Tab per Request (CONTEXT, Tab)
     found -> select it, end
  -> DataFolderIndex.path(of: requestID)         pure; the row came from the index
  -> DataFolderStore.read(path)                  boundary    E: unreadable -> escape: rescan
  -> RequestFile.decode                          E: undecodable since the scan -> escape:
                                                 rescan, so the row turns unreadable with
                                                 its reason; no Tab opens
  -> Tab(source: .request(id), definition: r.definition, baseline: r.definition)
                                                 inserted after the selected Tab, selected
  -> one Tab per RequestID                       DIE (assertion) otherwise, §4 Invariants
```

```
-> save(tab)                                     ⌘S on a Request Tab
  -> RequestFile.encode(id, name, definition)    pure: sorted keys, pretty, `version: 1`
  -> DataFolderStore.write(path, data)           boundary, atomic
                                                 E: unwritable -> escape: stays Dirty
  -> WriteLedger.record(path, hash)              §7: our own write is not Changed on Disk
  -> tab.baseline = tab.definition               Dirty clears by computation
  -> tab.isChangedOnDisk = false
```

**Files are written with sorted keys and stable formatting.** A save that changes nothing
must produce no git diff, and a save that changes one header must produce a one-line diff.
`JSONEncoder` with `[.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]` gives both.

```
-> saveDraft(tab)                                ⌘S on a Draft
  -> Data Folder unusable?                       -> no sheet: the window banner says why
  -> sheet: name + Collection/Folder             default: the last one used this run;
                                                 no Collections: New Collection… + its name
                                                 Cancel -> not an error, nothing written
  -> RequestID()
  -> save(tab) with the new path
  -> tab.source = .request(id)                   the Tab becomes that Request
  -> DataFolderIndex.insert
```

```
-> filesChanged(paths)                           §3: a stream, from FolderWatch
  -> WriteLedger.isOurs(path, hash)?             yes -> drop it
  -> TreeDecoder / DataFolderIndex rebuilt       pure, for the affected Collections only
  -> for each open Tab whose path changed
    -> file deleted
      -> Tab becomes a Draft, definition kept    banner: "Deleted on disk"
    -> not Dirty
      -> definition = baseline = disk            silently (design session Q7)
    -> Dirty
      -> baseline = disk, isChangedOnDisk = true banner: Reload · Keep Mine
         Reload    -> definition = baseline
         Keep Mine -> isChangedOnDisk = false, the next ⌘S writes over the file
```

**Keep Mine moves the baseline forward.** After Keep Mine the Tab is Dirty against the *new*
file, so ⌘S is an ordinary save and Undo still works. Leaving the old baseline would make the
next save silently overwrite the pulled change, which is the bug Changed on Disk exists to stop.

```
-> renameOrMove(node) · delete(node) · newCollection · newFolder
  -> DataFolderStore.move / trash / createDirectory   boundary
                                                 delete goes to the Trash, never unlink
  -> handled as filesChanged, with the ledger marking them as ours
```

## Filtering the sidebar

```
-> filterSidebar(query)                          every keystroke in the sidebar search field
  -> TreeFilter.matches(tree, query)             pure        R: none
     -> a node is kept if its name contains the query (case- and diacritic-insensitive,
        localizedStandardContains), or an ancestor's does; .unreadable rows match by file name
     -> ancestors of a kept node are kept and shown expanded
     -> the matched ranges, for highlighting
  -> the sidebar shows the filtered tree         query empty -> the tree and the expansion
                                                 state from before the filter, restored
```

**The filter is a view, not a second index.** It runs over the in-memory tree that
`DataFolderIndex` already holds, so it needs no I/O and no debounce: a linear scan of names
is microseconds even for tens of thousands of Requests (§7 has no wrapper for it, for the
same reason highlighting has none). A `filesChanged` while a filter is active re-runs it on
the new tree.
