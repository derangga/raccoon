# §2 A — Postman Import

Turning Postman exports into Collections, Environments and Globals, so a Postman user can move
to Raccoon in one step. Milestone M7, after Collections (M4) and Variables (M5), which it
writes into.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

## What it reads

| Postman export | How it is recognised | Becomes |
|---|---|---|
| Collection v2.1 or v2.0 | `info.schema` is the v2.1.0 or v2.0.0 schema URL, and `item` is an array | one Collection |
| Environment | `_postman_variable_scope == "environment"`, or a `name` with a `values` array | one Environment |
| Globals | `_postman_variable_scope == "globals"` | entries merged into Globals |

Anything else (Collection v1, a Postman data-dump zip, an Insomnia file) is listed as "not a
Postman export Raccoon reads" and not imported. So is a Collection wrapped in
`{"collection": …}`, as Postman's API returns it, and a file Foundation's JSON parser rejects,
such as one with a number too large for a Double (`1e309`), which Postman never writes. The user
picks one or many `.json` files at once, so an unzipped Postman data export imports in one pass.

## Entry points

```
-> importPostman()                               File ▸ Import from Postman… (⇧⌘I),
                                                 and the sidebar's + menu
  -> NSOpenPanel, .json, multiple                boundary    Cancel -> not an error, nothing
  -> FileReading.read(path) for each             boundary    R: FileReading
                                                 E: unreadable -> that file's row says so
  -> PostmanImporter.read(data)                  pure        R: none
     -> .collection(PostmanCollection) | .environment(PostmanEnvironment)
        | .globals([PostmanVariable]) | .notPostman
                                                 E: not JSON -> .notPostman, never a crash
                                                 E: an item with neither `item` nor
                                                 `request` -> .other(name), the plan counts it
  -> PostmanMapping.plan(files, dataFolder, globals, environments, newID)
                                                 pure: the ImportPlan, every note attached
                                                 R: newID () -> RequestID, passed in by the
                                                 caller, so a test plans with fixed ids
  -> the Import sheet: what will be created, what will be dropped    the user can untick any
                                                 Cancel -> nothing written
  -> Import: WindowModel.importPostman(plan) -> ImportResult       R: the window's DataFolderStore,
                                                 SecretStore and WriteLedger
    -> WindowModel.checkWritable()               the store's ensureExists. The sheet calls it too,
                                                 to disable Import
                                                 E: StoreError -> propagate: Import refuses before
                                                 anything is written, Keychain included
    -> for each Collection
      -> ImportCollection.contents               pure: folders and Request files by path inside the
                                                 Collection, file names chosen (below)
      -> DataFolderStore.writeDirectory(contents, to: name)
                                                 boundary, atomic per Collection: written to a
                                                 hidden temp folder in the Data Folder, then one
                                                 rename into place. A name taken on disk since the
                                                 plan fails the rename: never overwritten
                                                 E: StoreError -> escape: .collectionUnwritable,
                                                 nothing of it remains, the others still land
      -> WriteLedger.record(every file and folder)   §7: our own writes are not filesChanged
    -> for each Environment
      -> its file already on disk (taken since the plan, any case)?
                                                 yes -> escape: .environmentUnwritable, never
                                                 written over, no secret stored
      -> environments/ made if missing           E: StoreError -> escape: .environmentUnwritable
      -> secrets first: SecretStore.set(value, env, name)    R: SecretStore
                                                 an empty value deletes instead, as marking does
                                                 E: SecretError -> escape: .secretNotStored; the
                                                 Variable is written as a secret with no value, so
                                                 it is undefined until set. Never written to the
                                                 file in clear
      -> EnvironmentFile.encode -> DataFolderStore.write      through WindowModel.write
                                                 E: StoreError -> escape: .environmentUnwritable,
                                                 the secrets it stored are deleted again
    -> Globals: globals.entries + the plan's     names are new (the plan checked); secrets first,
                                                 environment nil, as for an Environment
                                                 E: StoreError -> escape: .globalsUnwritable, also
                                                 when globals.json does not decode (never rewritten)
  -> ImportResult: the Collections that landed, by folder name, and every problem
  -> the sidebar reveals and selects the first imported Collection
```

**File names inside a Collection** are chosen as New Folder and Save choose them: sanitised
(`/` and `:` become `-`, a leading `.` too), and ` 2` on a clash with a sibling, ignoring case.
A Folder and a Request file share one set of sibling names. Postman allows empty names; a
Folder whose name is empty is written as "New Folder", a Request's as "Request" (its file and
the name inside it), a Collection's as "New Collection" and an Environment's as "New
Environment", each with ` 2` when taken. The plan shows the empty name; ImportResult names
the Collection as written.

**Import never overwrites.** A Collection or Environment whose name is taken gets ` 2`, like a
duplicate Request file name (collections.md). Re-importing a newer Postman export therefore
creates a second copy instead of silently replacing edits made in Raccoon. A merge is a
later feature (design/ui/design-system.md, Open UI questions); the user confirmed the ` 2`
rule for v1 on 2026-10-25. Taken means the Workspace's names and the names planned earlier in
the same import, compared without case, so two imported "Prod" files give Prod and Prod 2. The
name is sanitised first, as New Collection sanitises it (`/` and `:` become `-`). Any change is
noted as `.renamed(from, to)`.

**Globals are added to, never changed.** Collection variables are planned first, then Globals
files, each in file order; a name already in Globals or planned earlier keeps the value it has
and is listed in `.globalSkipped`. Collection variables first matches Postman, where a
Collection variable wins over a Global. Collections whose variables were added are named in
`.collectionVariables` (info).

## The mapping

Raccoon is smaller than Postman on purpose. Each row where Postman has more says what happens,
and every loss becomes a note on the Import sheet, counted and naming the Requests.

| Postman | Raccoon |
|---|---|
| item with `item` | Folder, any depth, order kept |
| item with `request` | Request, a new `RequestID`, order kept; file name from its name (collections.md) |
| `request.method` absent, `null` or `""` | GET, Postman's default. A method is uppercased |
| `request.url`, a string or an object | `url` without the query, plus Params from `url.query` (disabled ones become Disabled Rows). `raw` is the url when present, else it is built from `protocol`, `host`, `port` and `path`; a `#fragment` is dropped, since it is never sent. A string url's query is split as the URL bar splits it |
| path variables `:id` with `url.variable` | `:id` stays in `url`, and each `url.variable` entry whose key is a name `PathVariables.tokens(in: url)` finds in the imported URL, with a value that is not empty, becomes `pathVariables[key]` (the JSON-text rule for non-string values applies). No note: nothing is lost. An empty or missing value is simply an empty Path Variable, and the request sends `:id` as it does in Postman. An entry whose key is not in the URL, a `disabled` entry (Raccoon has no enabled flag), and an entry's `description` and `type` are not written, without a note: none of them is sent. A `{{name}}` in a value is kept, and read at send like any other. Yaak and Bruno do the same: `:id` stays in the URL and the value goes to their own path-parameter store (environment-facts.md) |
| `header`, `disabled: true` | Headers, Disabled Rows. A `Cookie` header is split into Request Cookies rows, as in Curl Import |
| `header` as one string, or strings among its objects (`"Name: value"`, one per line) | Headers, split at the first `:` and trimmed, as Postman reads them; a line with no `:` is a name with an empty value |
| a header, query, `urlencoded` or text `formdata` entry whose key and value are both empty or `null` | no row: there is nothing to send, and the URL bar skips an empty pair the same way. A Disabled one is skipped too |
| a value that is a number, `true`/`false`, an object or an array | its JSON text (`5000`, `true`, `{"id":1}`, `["some","text"]`): what Postman shows and sends for it |
| body `raw`, `options.raw.language` json / xml / text | `.raw(.json / .xml / .text)`; html and javascript become `.text` |
| body `urlencoded` | `.formURLEncoded`, disabled fields kept as Disabled Rows |
| body `formdata`, text and `src` parts | `.multipart`; a file part keeps its `src` path, and a `src` list becomes one file Part per path under the same name, the same bytes on the wire. Postman often stores only a file name, so the send reports `fileMissing` until it is re-picked, and the note says which. A part's `contentType` is dropped without a note, as Curl Import drops `;type=…`: a Part has no Content-Type of its own |
| body `graphql` | `.raw(.json)` with `{"query", "variables"}`, as in Curl Import |
| body `file` (binary) | `.none`, noted: binary bodies are not supported |
| a `raw`, `urlencoded`, `formdata` or `graphql` body with nothing in it | `.none`: Postman exports `{"mode": "raw", "raw": ""}` on plain GETs, and an empty body sends no bytes, so no Content-Type is added for it |
| auth `noauth`, `basic`, `bearer` | `.none`, `.basic`, `.bearer` |
| auth `inherit`, or no auth on the item | the nearest Folder's or the Collection's auth, copied onto the Request and noted (`.authInherited`, info) unless it is `noauth`. Raccoon has no inherited Auth, so the effective one is written down |
| auth `apikey` | a header or a Param with that name and value, which is the same bytes on the wire. With no `key` nothing is added: a header or a Param needs a name |
| auth `basic` or `bearer` on a Request that also has an enabled `Authorization` header | both are imported, with no note. At send the Headers row wins and Auth's header is not sent (sending.md) |
| auth `oauth2`, `oauth1`, `digest`, `awsv4`, `ntlm`, `jwt`, `hawk`, `akamai`, `edgegrid` | `.none`, noted per Request. The settings are not kept |
| `protocolProfileBehavior.followRedirects`, `strictSSL: false` | Request Settings `followsRedirects`, `allowsInsecureTLS`. An absent `followRedirects` is Postman's default, which follows, so it imports as on |
| any other `protocolProfileBehavior` key (`maxRedirects`, `disableUrlEncoding`, `followAuthorizationHeader`, `disabledSystemHeaders`, `disableBodyPruning`) | dropped without a note: Raccoon has no such Request Setting. Postman writes `disableBodyPruning` on most requests it exports, so a note would name nearly every Request |
| a request item with an empty or blank `name` | named as its Draft Tab would be titled: the URL's path, else the URL as typed; with no URL, its method. A Request needs a name for its file name (collections.md) |
| collection `variable` | added to Globals (new names only). Raccoon has no Collection Variables; Globals keep Postman's "Environment wins" order, and a name that collides is listed |
| a variable `key` that is not a `VariableName` (`base url`, `a/b`) | dropped and listed (`.variableNameInvalid`): no `{{…}}` Raccoon resolves could reach it, and the file would not decode. Surrounding spaces are trimmed first, as the Environments sheet trims them; an empty key is no variable and is dropped silently |
| `{{name}}` | unchanged: Raccoon uses the same syntax |
| dynamic variables `{{$guid}}`, `{{$timestamp}}`, `{{$randomInt}}`, `{{$random…}}` | left as typed and noted. `$` is not a `VariableName` character, so each is an Undefined Variable and the request will not send until it is replaced. Sending the literal text would be worse |
| `event` (pre-request and test scripts) | dropped, counted: Raccoon runs no scripts. A blank script is not counted; a Folder's or the Collection's script counts on every Request under it, since Postman runs it for each |
| `response` (saved examples), `description` | dropped, counted. A Folder's or the Collection's description is named by that Folder or Collection. A header's, Param's, path variable's or body field's own `description` is dropped without a note: it is never sent |
| environment `values`, `enabled` | Environment entries, disabled ones kept disabled |
| environment, Globals or collection value with `type: "secret"` | a Secret Variable: Keychain first, file without the value (variables.md order). The plan carries the value in `ImportVariable.secret`, which is not Codable; what goes to the file is its `entry`, a `.secret` with none |

**The plan is computed before anything is written.** `PostmanMapping.plan` is pure, so the
Import sheet shows exactly what Import will do, including every note, and the tests assert on
the plan without a Data Folder.

## The Import sheet

```
-> PickedFile.read(paths, FileReading)           R: FileReading, from the composition root
                                                 E: StoreError -> escape: .unreadable(reason), a
                                                 disabled row "Can't be read: <reason>"
  -> PostmanImporter.read(data)                  E: .notPostman -> escape: a disabled row
-> PostmanImport(files, window)                  R: WindowModel: index, globals, environments,
                                                 brokenEnvironments (as empty Environments, so a
                                                 rename never takes an unreadable file's name)
  -> plan = PostmanMapping.plan(ticked files)    re-planned on every tick: unticking the first of
                                                 two "Prod" files makes the second plain Prod
  -> rows: one per picked file, by file name   as Finder lists them; "pick order" below is this
     -> PostmanMapping.plan(before + [file])     before = the ticked files the planner reads
                                                 first: Collections, then Environments, then
                                                 Globals, each in pick order. The row is what
                                                 this file adds after them: its Collection or
                                                 Environment (renamed or not), or the Globals it
                                                 adds and the names it keeps. An unticked row
                                                 shows what it would add if ticked
  -> notes: plan.notes as lines                  .renamed is on its row, not a note; .globalSkipped
                                                 is on the Globals row, and only the Collection
                                                 variables Globals keeps become a note.
                                                 Dynamic variables share one line
  -> footer: WindowModel.checkWritable()         E: StoreError -> escape: Import disabled, the
                                                 reason in the footer
  -> Import: WindowModel.importPostman(plan)     E: StoreError -> escape: as above, nothing written
    -> no problems -> the sheet closes           and the sidebar selects result.collections.first
    -> problems -> the result, one line each     Done closes, then the same selection
```

**Names on the sheet are the names written.** The plan keeps Postman's empty name; the sheet
asks the window for the name Import will give it (`WindowModel.importName`), the same call the
writer makes, so an empty Collection reads "New Collection" (" 2" when taken) and never "".
An empty name inside a note's list is left out of the list, never shown blank; the count still
counts it.

**A note's names fit one line.** Under a note, as many names as fit the sheet's width, joined
by " · ", then "and N more"; a single name too long for the line is cut in the middle so "and N
more" stays readable.

## Rules carried over from Yaak's and Bruno's importers

`yaak/plugins/importer-postman` (MIT) and `bruno/packages/bruno-converters/src/postman` record
cases they already handle. Their fixtures become `PostmanImporter` tests (swap-r.md):

- `url` may be a string or an object; an object's `host` and `path` may be arrays or strings.
- Auth parameters are arrays of `{key, value}`, not objects.
- A body header (`Content-Type`) is added only when the request has none of that name.
- An item with neither `item` nor `request` is skipped and counted, not a failure.
- `{{ name }}` with spaces is the same Variable (variables.md).
- A path variable's value is kept apart from the URL (Yaak's `:key` URL parameter, Bruno's
  `type: "path"` param), and a variable with no key is skipped (Bruno), so the importer
  tests cover: a value, an empty value, no `variable` array, a key that is not in the URL, a
  variable with no key, a repeated `:id`, and `:id.json`.
