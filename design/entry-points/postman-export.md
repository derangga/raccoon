# §2 A — Postman Export

Writing a Collection as a Postman Collection v2.1 file and an Environment as a Postman
Environment file, so work done in Raccoon can go back to Postman or to a teammate. Milestone
M9, after Postman Import (M7), whose mapping it reads backwards, and Workspaces (M8).

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md). The mapping going
the other way is [postman.md](./postman.md).

## What it writes

| From | File | Default name in the save panel |
|---|---|---|
| a Collection | Postman Collection v2.1 | `<name>.postman_collection.json` |
| an Environment | Postman Environment | `<name>.postman_environment.json` |

Globals have no Export. An Environment that does not decode has none either: its row is
read-only (variables.md), and there is no `VariableEntry` list to write. The name in the save
panel is the Collection's or Environment's name with `/` and `:` turned into `-`, as a file name
is chosen (collections.md). The user picks where the file goes, so it is written through
`FileWriting`, not through `DataFolderStore`, which writes only inside the Data Folder.

**Export never changes anything in the Data Folder.** It reads Request files, writes one file
somewhere else, and records nothing in the WriteLedger. It works on a Data Folder that is not
writable, unlike Import. If the user picks a place inside the Data Folder, the watch sees an
ordinary outside change, and a `.json` inside a Collection that is not a Request shows as an
unreadable row (collections.md); Raccoon does not stop it, because the choice is the user's.

## Entry points

```
-> exportCollection(collection)                  File ▸ Export Collection… (right after Import from
                                                 Postman…, no shortcut; enabled when the sidebar
                                                 selection is in a Collection and no sheet is up: a rule
                                                 of Export's own, so the item is disabled and the
                                                 action also returns early with a sheet up), and Export…
                                                 in a Collection row's context menu (not on a
                                                 Folder, Request or unreadable row)
  -> the Collection Export sheet opens           R: none. Cancel or Esc -> nothing written
  -> WindowModel.prepareExport(collection, id)   R: the window's DataFolderStore, its index and its
                                                 Tabs. Returns an AsyncStream<ExportStep>? that
                                                 yields an ExportStep as each one finishes, the last
                                                 one carrying the ExportPlan and its bytes. Runs off
                                                 the main actor; the sheet draws each step as it
                                                 arrives. Stopping iteration stops the work (cancel
                                                 propagates): checked before each file is read and
                                                 before the format and the scan. The main actor reads
                                                 only the index and the Tabs; the sort and the reads
                                                 are the stream's, off it. `id` is the UUID below
                                                 E: the Collection is no longer in the index
                                                 (renamed or trashed outside Raccoon) -> escape:
                                                 nil, nothing opens
    -> CollectionExport.sorted(nodes)            pure (RaccoonDomain), R: none: Folders first, then Requests and
                                                 unreadable rows together, each by the name shown
                                                 (`localizedStandardCompare`), as TreeDecoder sorts.
                                                 The exporter keeps the order it is given; this is
                                                 where the sidebar's order is chosen
    -> for each .request node, in that order
      -> DataFolderStore.read(path)              boundary    R: DataFolderStore
                                                 E: StoreError -> escape: skipped, ExportSkip
      -> RequestFile.decode                      pure, R: none
                                                 E: RequestFileError -> escape: skipped
    -> for each .unreadable node                 R: none. escape: skipped with the reason the
                                                 sidebar shows it, not read again
    -> yield .read(count)                        R: none. The Requests that decoded
    -> PostmanExporter.collection(collection, id)
                                                 pure: the bytes, sorted keys (below)
                                                 R: id, a UUID passed in by the caller, so a test
                                                 exports with a fixed one
    -> yield .formatted                          R: none
    -> CredentialScan.find(requests)             pure, R: none: [CredentialFinding], on the same
                                                 RequestDefinitions the exporter wrote
    -> Tabs that are Dirty and show a Request    (the Dirty Tabs' names are read when prepareExport is
       of this Collection                        called, on the main actor, and handed to the stream,
                                                 which picks this Collection's in tree order: the
                                                 sheet is modal, so the Tabs do not change meanwhile)
                                                 R: the window's Tabs and index, matched by
                                                 RequestID (a Tab's `.request(id)` against the
                                                 tree's ids), never by name: two Requests may
                                                 share one. The names come from the index. The file
                                                 holds what is saved
    -> yield .scanned(ExportPlan)                R: none. The plan holds the counts, the findings,
                                                 the skipped files, dirtyRequests and the bytes
  -> the sheet: the third check, and in its frame the counts, the credentials, the skipped files,
     the Dirty Requests, and Export… enabled     R: none. Nothing is clickable before the warning
                                                 is on screen
  -> Export…: NSSavePanel as a sheet             boundary (AppKit), R: none, .json, default name
                                                 above. `beginSheetModal(for:)` is called on the Export
                                                 sheet's own window, a sheet on a sheet: checked in a
                                                 running AppKit app, the panel attaches to the Export
                                                 sheet, which stays on the window, and Cancel returns
                                                 .cancel. A unit test host cannot show a save panel
                                                 (the runner exits), so that is a manual scenario.
                                                 Cancel -> back on the Export sheet, nothing
                                                 written
  -> FileWriting.write(plan.data, to: url)       boundary, atomic    R: FileWriting
                                                 E: StoreError -> escape: the sheet stays, a red
                                                 line "Not exported. <reason>.", Export… still
                                                 works. The old file at that url is as it was
  -> the sheet closes                            R: none
```

**The bytes written are the bytes the sheet described.** The plan is computed once, before the
save panel, and `plan.data` is what `write` gets. A Request saved or changed on disk while the
sheet is open is not picked up, so the credential warning, the counts and the file never
disagree. The sheet is modal, so the window is not editing meanwhile.

**Export reads files, not Tabs.** A Dirty Tab's edits are not in the file. The sheet says so
("2 Requests have edits in Tabs. Export uses what is saved.") rather than exporting what
the user did not save or saving for them.

```
-> exportEnvironment(environment)                Export… in an Environment row's context menu in the
                                                 Environments sheet. Globals and a row that does not
                                                 decode have no menu
  -> the Environment Export sheet opens          R: none. "N Variables, M secrets", and the checkbox
                                                 Include secret values, off. With M = 0 the
                                                 checkbox and its hint are not drawn
                                                 Cancel or Esc -> nothing written, nothing read
  -> Export…: NSSavePanel as a sheet             boundary (AppKit), R: none, default name above
                                                 Cancel -> back on the sheet. No Keychain read
                                                 has happened, ticked or not
  -> ticked? -> WindowModel.readSecrets(of: environment) -> EnvironmentSecrets
                                                 after the panel returns, never before: a Cancel
                                                 never reaches the Keychain. R: SecretStore
    -> for each Secret Variable, enabled or not
      -> SecretStore.get(environment: name, name)
                                                 R: SecretStore
                                                 nil -> the value is "": it was never typed, and
                                                 the file says so. Not named
                                                 E: SecretError -> escape: that one is "" and is
                                                 listed in `unreadable`; the others are still read
  -> unticked -> EnvironmentSecrets.none         R: none. No SecretStore call at all
  -> PostmanExporter.environment(environment, secrets, id, exportedAt, version)
                                                 pure    R: id, exportedAt and version are passed in
                                                 (a UUID, the clock's Date, the bundle's version),
                                                 so a test exports with fixed ones
  -> FileWriting.write(data, to: url)            boundary, atomic    R: FileWriting
                                                 E: StoreError -> escape: the sheet stays with the
                                                 red line; the values read are dropped with it
  -> unreadable is empty -> the sheet closes     R: none
  -> unreadable is not   -> the result: the file written, and the names that are empty in it, Done
                                                 R: none. Never a failed export: the file is on disk
```

**A Secret Variable is never read unless the box is ticked.** Off writes it as `type: "secret"`
with an empty value, and no `SecretStore.get` runs: a test with the swapped SecretStore proves
that by what it was asked. Ticked, the Keychain is read once per Secret Variable, after the
save panel has returned, so a refused panel never causes a Keychain prompt. The values go from
memory to one file and are dropped; Raccoon keeps no copy.

```
-> importFromPostman(), from the Environments sheet
  -> the Environments sheet closes               R: none. The same close as Done: focus goes back to
                                                 the field that had it (surfaces.md §8). It must
                                                 have finished closing before the next node
  -> NSApp.sendAction(AppDelegate.importFromPostman(_:), to: nil, from: nil)
                                                 R: none. The action File ▸ Import from Postman…
                                                 (⇧⌘I) sends, as an Empty state row does. It
                                                 returns early while `window.attachedSheet != nil`
                                                 (RaccoonApp.swift), so sent before the Environments
                                                 sheet is gone it would do nothing
    -> the open panel, then the Import sheet     unchanged: postman.md. No new import code, R: none
                                                 Cancel in the open panel -> not an error, no sheet
```

**The Environments sheet is not reopened after an import.** Import's own flow ends on the
sidebar, as it does from the menu; an imported Environment is in the picker and in the sheet the
next time it opens (⌥⌃E). Reopening it would be a second rule for one entry.

## Output is byte-stable

Both files are encoded as Request files are (collections.md): `JSONEncoder` with
`[.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]`, so two-space indent, and a final newline.
Postman writes tabs and its own key order; neither matters to a reader, and sorted keys make two
exports of one Collection byte-equal and a changed header a one-line diff.

The one thing that is not stable is what is passed in: `info._postman_id`, the Environment's
`id`, and its `_postman_exported_at`. With the same arguments the bytes are equal, which is what
the test does. In the app, `id` is a new UUID each time, so two real exports of one Collection
differ by that one line.

## The mapping, Raccoon to Postman

Import's table read backwards ([postman.md](./postman.md)). Where Raccoon has less than Postman,
the key is not written.

| Raccoon | Postman Collection v2.1 |
|---|---|
| Collection | `info.name`, `info._postman_id` (the id passed in), `info.schema` = `https://schema.getpostman.com/json/collection/v2.1.0/collection.json`. No `variable` (Raccoon has no Collection variables), `auth`, `event`, `description` or `info._exporter_id` (Postman's account id) |
| Folder | an item with `item`, at any depth. An empty Folder is `"item": []` |
| order | the order the exporter is given, kept as it is. `prepareExport` gives it the sidebar's: Folders first, then Requests, each by the name shown (`localizedStandardCompare`), as TreeDecoder sorts |
| Request | an item with `name` (the name inside the file, never the file name), `request`, and `response: []`, which Postman writes on every item. The `RequestID` is not written |
| `method` | `request.method` |
| `url` and Params | `request.url.raw` is the URL bar's text (`URLText.join`) with Disabled Rows left out, as Postman leaves them out of `raw`. The parts are derived from `url`, splitting only outside `{{ }}`: `protocol` (before `://`, absent with none), `host` (an array split at `.`), `port` (digits after `:` in the host), `path` (an array split at `/`). `query` is every Param, enabled or not, as typed and not percent-encoded: `{key, value}` and `disabled: true` on a Disabled Row. No fragment |
| Path Variables | `:id` stays in `path`. `url.variable` has one `{key, value}` per distinct `:name` in `url`, in URL order, with `value: ""` when the Request holds none. Import drops the empty ones, so nothing changes on the way back |
| Headers, Disabled Rows | `header`: `{key, value}` in row order, `disabled: true` on a Disabled Row. No `type` |
| Request Cookies | `Cookie` headers, built in row order from runs: each run of enabled cookies is one `Cookie` header `a=1; b=2`, each run of disabled ones one `Cookie` header with `disabled: true`. Import splits them back in the same order, so the rows return as they were. With no disabled cookie between them there is one header |
| headers the send adds (Content-Type, Content-Length, User-Agent) | only the rows in `headers` are written, so a Content-Type row the user can see in the Headers table is written like any other. `AutomaticHeaders` is never read: what is computed at send (sending.md) is not in the file, and Postman computes its own. Raccoon adds nothing to the file |
| Body `.none` | no `body` key |
| Body `.raw(json / xml / text)` | `body: {mode: "raw", raw, options: {raw: {language: "json" / "xml" / "text"}}}` |
| Body `.formURLEncoded` | `body: {mode: "urlencoded", urlencoded: [{key, value}]}`, `disabled: true` on a Disabled Row |
| Body `.multipart` | `body: {mode: "formdata", formdata: [...]}`: a text Part is `{key, value, type: "text"}`, a file Part `{key, type: "file", src: <path as typed>}`, `disabled: true` on a Disabled Row. The path is written as the Request holds it, so an absolute one names the user's home folder |
| Auth `.none` | `auth: {type: "noauth"}`, written on every Request. An item with no `auth` inherits in Postman, so leaving it out would change what the Request sends |
| Auth `.basic` | `auth: {type: "basic", basic: [{key: "username", value, type: "string"}, {key: "password", value, type: "string"}]}` |
| Auth `.bearer` | `auth: {type: "bearer", bearer: [{key: "token", value, type: "string"}]}` |
| Request Settings | `protocolProfileBehavior` on the item: `followRedirects` always, true or false, because Raccoon's default is off and an absent key means follow in Postman; `strictSSL: false` only when `allowsInsecureTLS` is on; `disableBodyPruning: true` when the method is GET or HEAD and the Body is not `.none`, so Postman keeps the body Raccoon holds. Import drops it without a note |
| `{{name}}` | unchanged: Postman uses the same syntax. A Collection file holds names only; the values are in Environments, which are exported on their own |
| `description`, `event`, `response` | not written: Raccoon has none |

| Raccoon Environment | Postman Environment |
|---|---|
| the file | `id` (the id passed in), `name`, `values`, `color: null` (a synthesized `Encodable` omits a nil key, so this is an explicit `encodeNil`), `_postman_variable_scope: "environment"`, `_postman_exported_at` (ISO 8601 UTC with milliseconds, as in the example), `_postman_exported_using: "Raccoon/<version>"` (the bundle's short version). Key for key, the keys of `example/Sociolla Beauty Journal.postman_environment.json` |
| plain Variable | `{key, value, type: "default", enabled}` |
| Secret Variable | `{key, value, type: "secret", enabled}`. `value` is `""` unless the box is ticked and the Keychain gave one |
| Disabled entry | `enabled: false`, in the same place |
| order | the file's |

`<version>` is `CompositionRoot.appVersion()`: the bundle's `CFBundleShortVersionString`, or `"dev"` when there is none, as under `swift run`.

**What does not come back by round trip.** Export, then `PostmanImporter.read` and
`PostmanMapping.plan`, gives equal `RequestDefinition`s and no `ImportNote`, with these
exceptions, each from `PostmanMapping`:

- **An empty body.** `.raw(_, "")`, `.formURLEncoded([])` and `.multipart([])` re-import as
  `.none`: Import reads an empty `raw`, and a `urlencoded` or `formdata` with no row, as no body
  (Postman writes `{"mode": "raw", "raw": ""}` on plain GETs).
- **A Content-Type row.** A Request with a body and no Content-Type row gets one on re-import,
  from `Headers.contentType`, which Import runs on every Request, so the definition is not equal.
  A Request that has the row, as one the user switched Body Type on does, comes back unchanged.
- **A file Part with a relative path, or none.** A path that does not start with `/` re-imports
  with an `.fileOnlyName` note, because Import cannot tell it from the file name Postman often
  stores alone. That includes the empty path of a Part whose file is not picked yet: it comes back
  equal, with `.fileOnlyName("")`. An absolute path is unchanged.
- **A `#fragment` in `url`.** It is written as typed and dropped on re-import: `PostmanMapping.url`
  cuts the text at `#`. With enabled Params, `raw` reads `…#frag?a=1`, which is the URL bar's text.
- **A Request Cookie value with `;` or edge spaces.** One containing `;`, or with a leading or
  trailing space, does not come back as typed: `CurlImporter.cookieRows` splits on `;` and trims.
  Import has the same limit.
- **Dynamic variables.** A `{{$guid}}`-style text anywhere in a Request re-imports with a
  `.dynamicVariable` note: the text is unchanged, and Raccoon already treats it as an Undefined
  Variable.
- **A Headers row named `Cookie`**, which Import turns into Request Cookies.
- **Names.** Import never overwrites, so a re-import of the Collection is "<name> 2", and the
  Environment is "<name> 2" too. The plan's Requests are what is compared, not the folder names.

## The credential scan

Postman warned "18 secrets" on `example/Sociolla.postman_collection.json`. Postman's word
collides with Secret Variable (CONTEXT.md), so Raccoon says **credential**: a literal value
typed into a Request, in a field whose name says what it holds, that is not a `{{name}}`
reference. The scan is pure and runs on the `RequestDefinition`s the exporter wrote, so the
warning describes the file as written, and a Disabled Row counts because the file holds it
(`disabled: true`).

A **field counts** when these hold:

1. **Its place is scanned**: a Headers row (a header named `Cookie` is not), a Params row, the
   `.bearer` token, or the `.basic` password. The `.basic` user name is not a credential.
2. **Its value is not a reference**: `VariableTokens.ranges` finds no `{{name}}` in it. `Bearer
   {{token}}` is a reference, `Bearer eyJ…` is not. A `{{$name}}` is not a reference either: `$`
   is not a VariableName character, so `VariableTokens.ranges` reads it as text, and a header
   like `authorization: {{$token}}` counts as a credential.
3. **It holds something**, for the Auth fields only: an empty `.bearer` token or `.basic` password,
   or one that is only whitespace, is nothing typed, so it is not a finding. An empty or
   whitespace Headers or Params value still counts: the row is a field the file carries, and
   Postman counts it.

A Headers or Params row also needs a **credential name**: trimmed and compared without case,
exactly `authorization`, `proxy-authorization` or `key`, or containing `token`, `secret`,
`password`, `passwd`, `apikey`, `api-key` or `api_key`. An Auth field needs no name: its place
says what it is.

Each finding is one field: the Request's name and where (`.header(name)`, `.query(name)`,
`.bearerToken`, `.basicPassword`). It carries **no value**, so no sheet can print one. A Request
with two credentials has two findings and is named once on the sheet.

**On the example the scan finds 18**, in 18 Requests: 16 `authorization` headers (15 hold
`Bearer eyJ…`, and `New Article` holds an empty value) and 2 `Access-Token` headers that hold a
token. 12 `authorization` headers are `{{bearer}}`, 2 `Access-Token` headers are
`{{zalo_access_token}}` and `Refresh-Token` is `{{zalo_refresh_token}}`: references, not found.
Postman's 18 is the same set. Counting only non-empty values gives 17, so the empty value
counts, as in Postman, and the test pins 18.

**What is not scanned**, said here so the warning is not read as a guarantee: Cookie headers and
Request Cookies (the example has 33 Cookie headers, all carrying session and token cookies, and
Postman does not count them; counting them would drown the list), Body fields (`client_secret`
in a form), the URL's user info, and the text of any value that is not in the places above.
The warning is a list of what is certain, not a proof that the rest is clean.

**Warn and list only.** The file is written exactly as the Requests hold it: nothing is
removed, masked or replaced. Raccoon adds and hides nothing.

## The Collection Export sheet

Opened by the first tree above. One sheet, one run; the layout and strings are
[design/ui/design-system.md](../ui/design-system.md) §6, modeled on Postman's.

```
-> ExportStep stream, from prepareExport         R: none in the sheet: it draws what arrives
  -> ExportStepReveal.starts(finishedAt, reduceMotion)
                                                 pure, R: none: check i starts at max(finish i,
                                                 start of check i-1 + 60 ms). A step that finishes
                                                 late is shown when it finishes; the stagger only
                                                 spaces steps that finish together. No artificial
                                                 delay. reduceMotion -> every start is its finish,
                                                 with no fade
  -> a step's check fades in                     opacity only, 150 ms ease-out. Not yet drawn: the
                                                 steps, until they finish
  -> .read(count)       "Read 41 Requests from ~/Raccoon"
  -> .formatted         "Formatted as Collection Format v2.1"
  -> .scanned(plan)     "Scanned for credentials"
  -> then, in the same frame as the third check starts, with no motion of their own:
     counts "41 Requests · 11 Folders"; the credentials if any; the skipped files if any; the
     Dirty Requests if any; and Export… enabled. All of it at once, so nothing is clickable before
     the credential warning is on screen
  -> a read that takes over 150 ms               the system small spinner in the first row's check
                                                 position, until that check appears (behavior.md, as
                                                 the Response pane)
```

**The steps are the real ones.** "Read N Requests" is the count that decoded, so with a skipped
file it is below the sidebar's count. Each check is drawn when the work behind it has
finished, never earlier, so the sheet cannot claim a scan that has not run.

**A file that does not decode is skipped and listed, and never blocks the export.** A Request
file the scan marked `.unreadable`, or one that no longer decodes when it is read, is left out
of the file and named on the sheet ("1 file is not exported"). Blocking would make one
half-written file in a big Collection stop the whole export, and the user can neither see the
problem from the sheet nor fix it there. The file on disk is untouched, as everywhere
(collections.md).

## Rules carried over

- The importer's fixtures run backwards: each fixture's `PostmanFile` is exported and read
  again (swap-r.md, Round trip).
- `example/Sociolla.postman_collection.json`: import, build the `ExportCollection` straight from
  the first plan's nodes, export, import again, and compare the two plans in plan order. Postman's
  order differs from the sorted one in 10 places in this file, so the test does not go through
  disk, where `prepareExport` would re-sort. The export's counts are 41 Requests, 11 Folders and
  18 credentials.
- The Environment's keys are checked against `example/Sociolla Beauty Journal.postman_environment.json`
  key for key, and the file round-trips to 14 Variables.
