# §2 A — Workspaces

Remembering several Data Folders and switching the window between them. Milestone M8.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md). Loading one Data
Folder is [collections.md](./collections.md); this file is what changes around it.

## What a Workspace is

A Workspace is a Data Folder plus two things kept per Data Folder: its Secret Variables in the
Keychain and its Session. The window shows one Workspace at a time (decided 2026-10-19, with
the rest of this file). Two windows on two Workspaces would mean a FolderWatch, a Session
and an Active Environment per window, and there is one window.

```
~/Raccoon/                             a Data Folder, as collections.md lays it out
  raccoon.json                         { "version": 1, "id": "<UUID>" }  the WorkspaceID
  globals.json
  environments/ …
  Payments API/ …

UserDefaults
  "DataFolder"                         the open Workspace's path, as before
  "Workspaces"                         [path], every remembered Workspace

~/Library/Application Support/Raccoon/
  sessions/<key>.json                  one Session per Workspace, <key> = the first 16 hex
                                       digits of SHA-256 of the standardized path
```

**The id lives in the folder, the Session is keyed by the path.** Secrets follow the id, so
moving or renaming the folder keeps them, and two git clones of one repository share them,
which is harmless because a value never leaves the Keychain. Tabs follow the path, because a
Request Tab points at a file under that path and two clones must not share one set of Tabs.
Moving a folder therefore keeps its secrets and starts it with no Tabs.

**`raccoon.json` is committed with the Collections.** It is a top-level file, so TreeDecoder
already leaves it out of the tree. It is read once per load; a `git checkout` that changes it
takes effect on the next switch or relaunch.

There is no migration: nothing has been released, so no Keychain item or `session.json`
exists under the old keys.

## Entry points

```
-> loadDataFolder(root)                          collections.md, with these nodes added
  -> list empty?                                 first launch: root = ~/Raccoon,
     -> DataFolderStore.ensureExists(root)       created as before. A remembered root is
                                                 never created: missing -> escape: banner
  -> DataFolderStore.scan(root)                  as collections.md
  -> WorkspaceFile.decode(scan["raccoon.json"])  pure        E: undecodable -> escape:
                                                 secrets unavailable, never rewritten
     absent -> WorkspaceID()
            -> DataFolderStore.write("raccoon.json", WorkspaceFile.encode(id))
                                                 E: unwritable -> escape: the existing
                                                 not-writable banner; no id, no secrets
  -> SecretStore for the id                      R: KeychainSecretStore(service:
                                                 "Raccoon/<id>"); no id -> one whose get
                                                 is nil and whose set throws
  -> SessionStore for the root                   R: sessions/<key>.json
  -> TreeDecoder, DataFolderIndex, FolderWatch   as collections.md
  -> relaunch() against this Session             tabs.md; skipped when the scan failed,
                                                 see "An unreadable Workspace" below
```

```
-> switchWorkspace(root)                         a row of the Workspace pop-up, or Open
                                                 Workspace… on a folder already listed
  -> root == the open root?                      -> nothing, end
  -> SessionWriter.writeNow(session)             §7's coalescing is skipped, as on quit
  -> the withDataFolder scope ends               §8: every withTab scope inside it ends
                                                 first, so in-flight sends are cancelled,
                                                 as Close cancels them; then FolderWatch
  -> loadDataFolder(root)
  -> DataFolderLocation.remember(root)           the open path, even when the load failed:
                                                 relaunch reopens the Workspace the user
                                                 chose, and shows the same banner
```

**Switching never prompts.** The Session keeps Drafts and Dirty edits, so the Tabs left
behind are exactly where they were when the user switches back, for the same reason quit
does not prompt (tabs.md).

```
-> newWorkspace()                                New Workspace… in the pop-up
  -> NSSavePanel: name + location                default directory ~; Cancel -> nothing
  -> exists already?                             -> escape: alert "A folder named “<name>”
                                                 already exists. Use Open Workspace… to
                                                 add it." Nothing written
  -> DataFolderStore.createDirectory(root)       E: StoreError -> escape: an alert sheet,
                                                 "Couldn't create “<name>”: <reason>."
  -> WorkspaceList.add(root)
  -> switchWorkspace(root)                       loadDataFolder writes raccoon.json
```

```
-> openWorkspace()                               Open Workspace… in the pop-up and in the
                                                 Data Folder banner
  -> NSOpenPanel: one folder                     New Folder allowed; Cancel -> nothing
  -> WorkspaceList.add(root)                     already listed -> unchanged
  -> switchWorkspace(root)
```

Any folder can be opened. Its top-level folders become Collections, as in collections.md, and
`raccoon.json` is written into it on load: it shows in `git status` once, and from then on
every clone shares the id.

```
-> removeWorkspace(root)                         Remove from List ▸ <Workspace> in the
                                                 pop-up, or Remove from List in the Data
                                                 Folder banner
  -> root == the open root?                      the pop-up's submenu leaves it out; only
                                                 the banner reaches here with it
     -> switchWorkspace(first other Workspace by name); none -> the banner doesn't offer it
  -> WorkspaceList.remove(root)
  -> SessionStore(root).delete()                 E: StoreError -> escape: log; a stale
                                                 Session file costs nothing
```

**Remove from List forgets, it does not delete.** The folder stays, and so do its Keychain
items, so Open Workspace… on the same folder brings its secrets back. Its Tabs do not come
back.

## An unreadable Workspace

A remembered folder that was deleted, moved, or is on a drive that is not mounted stays in
the list. Switching to it shows the existing Data Folder not-readable banner, whose buttons
are Open Workspace… and Remove from List. The sidebar is empty and the window has one empty
Draft, so it is still an HTTP client (§4, Data Folder).

**Its Session is neither read nor written while it cannot be read.** Restoring it against an
empty index would turn every Request Tab into a Draft, and the next write would make that
permanent. So `relaunch()` is skipped and the SessionWriter has no store: Tabs made while the
banner shows are lost on switch or quit. When the drive comes back, switching to it again
restores the Tabs it had. This applies at launch too, which changes what tabs.md did for an
unreadable root.

A Data Folder that can be read but not written loads its Session as usual: the index is
whole, only saving fails.

## The Workspace pop-up

```
-> workspaceMenu()                               opening the pop-up at the top of the sidebar
  -> WorkspaceList.titles(paths)                 pure: the folder name; two with the same
                                                 name -> "<name> — <parent folder>" for
                                                 those two only
  -> rows sorted by title                        localizedStandardCompare, as the sidebar;
                                                 the open one checked
  -> separator, New Workspace…, Open Workspace…, Remove from List ▸ (every other one)
```

The list is not checked against the disk when the menu opens. A missing folder is found the
way any other is, by loading it.
