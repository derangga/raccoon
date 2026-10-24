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
Postman export Raccoon reads" and not imported. The user picks one or many `.json` files at
once, so an unzipped Postman data export imports in one pass.

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
  -> Import
    -> for each Collection
      -> DataFolderStore.writeDirectory(tmp)     boundary, atomic per Collection: written to a
                                                 hidden temp folder in the Data Folder, then one
                                                 rename into place
                                                 E: unwritable -> escape: that Collection is
                                                 reported failed, the others still land
      -> WriteLedger.record(every file)          §7: our own writes are not filesChanged
    -> for each Environment
      -> secrets first: SecretStore.set(env, name, value)    R: SecretStore
                                                 E: SecretError -> escape: the Variable is
                                                 written as a secret with no value, so it is
                                                 undefined until set, and the note says so.
                                                 Never written to the file in clear
      -> EnvironmentFile.encode -> DataFolderStore.write      E: unwritable -> escape
    -> Globals: add entries whose names are new  existing names are kept, listed as skipped
  -> the sidebar reveals and selects the first imported Collection
```

**Import never overwrites.** A Collection or Environment whose name is taken gets ` 2`, like a
duplicate Request file name (collections.md). Re-importing a newer Postman export therefore
creates a second copy instead of silently replacing edits made in Raccoon. A merge is a
later feature (design/ui/design-system.md, Open UI questions).

## The mapping

Raccoon is smaller than Postman on purpose. Each row where Postman has more says what happens,
and every loss becomes a note on the Import sheet, counted and naming the Requests.

| Postman | Raccoon |
|---|---|
| item with `item` | Folder, any depth, order kept |
| item with `request` | Request, a new `RequestID`, order kept; file name from its name (collections.md) |
| `request.url`, a string or an object | `url` without the query, plus Params from `url.query` (disabled ones become Disabled Rows). `raw` is the url when present, else it is built from `protocol`, `host`, `port` and `path`; a `#fragment` is dropped, since it is never sent. A string url's query is split as the URL bar splits it |
| path variables `:id` with `url.variable` | the value is written into the path (`.pathVariable`, info); an empty or missing value keeps `:id` and is noted (`.pathVariableEmpty`). Raccoon has no path variables |
| `header`, `disabled: true` | Headers, Disabled Rows. A `Cookie` header is split into Request Cookies rows, as in Curl Import |
| body `raw`, `options.raw.language` json / xml / text | `.raw(.json / .xml / .text)`; html and javascript become `.text` |
| body `urlencoded` | `.formURLEncoded`, disabled fields kept as Disabled Rows |
| body `formdata`, text and `src` parts | `.multipart`; a file part keeps its `src` path. Postman often stores only a file name, so the send reports `fileMissing` until it is re-picked, and the note says which |
| body `graphql` | `.raw(.json)` with `{"query", "variables"}`, as in Curl Import |
| body `file` (binary) | `.none`, noted: binary bodies are not supported |
| a `raw`, `urlencoded`, `formdata` or `graphql` body with nothing in it | `.none`: Postman exports `{"mode": "raw", "raw": ""}` on plain GETs, and an empty body sends no bytes, so no Content-Type is added for it |
| auth `noauth`, `basic`, `bearer` | `.none`, `.basic`, `.bearer` |
| auth `inherit`, or no auth on the item | the nearest Folder's or the Collection's auth, copied onto the Request and noted (`.authInherited`, info) unless it is `noauth`. Raccoon has no inherited Auth, so the effective one is written down |
| auth `apikey` | a header or a Param with that name and value, which is the same bytes on the wire |
| auth `oauth2`, `oauth1`, `digest`, `awsv4`, `ntlm`, `jwt`, `hawk`, `akamai`, `edgegrid` | `.none`, noted per Request. The settings are not kept |
| `protocolProfileBehavior.followRedirects`, `strictSSL: false` | Request Settings `followsRedirects`, `allowsInsecureTLS`. An absent `followRedirects` is Postman's default, which follows, so it imports as on |
| collection `variable` | added to Globals (new names only). Raccoon has no Collection Variables; Globals keep Postman's "Environment wins" order, and a name that collides is listed |
| `{{name}}` | unchanged: Raccoon uses the same syntax |
| dynamic variables `{{$guid}}`, `{{$timestamp}}`, `{{$randomInt}}`, `{{$random…}}` | left as typed and noted. `$` is not a `VariableName` character, so each is an Undefined Variable and the request will not send until it is replaced. Sending the literal text would be worse |
| `event` (pre-request and test scripts) | dropped, counted: Raccoon runs no scripts. A blank script is not counted; a Folder's or the Collection's script counts on every Request under it, since Postman runs it for each |
| `response` (saved examples), `description` | dropped, counted. A Folder's or the Collection's description is named by that Folder or Collection |
| environment `values`, `enabled` | Environment entries, disabled ones kept disabled |
| environment value with `type: "secret"` | a Secret Variable: Keychain first, file without the value (variables.md order) |

**The plan is computed before anything is written.** `PostmanMapping.plan` is pure, so the
Import sheet shows exactly what Import will do, including every note, and the tests assert on
the plan without a Data Folder.

## Rules carried over from Yaak's and Bruno's importers

`yaak/plugins/importer-postman` (MIT) and `bruno/packages/bruno-converters/src/postman` record
cases they already handle. Their fixtures become `PostmanImporter` tests (swap-r.md):

- `url` may be a string or an object; an object's `host` and `path` may be arrays or strings.
- Auth parameters are arrays of `{key, value}`, not objects.
- A body header (`Content-Type`) is added only when the request has none of that name.
- An item with neither `item` nor `request` is skipped and counted, not a failure.
- `{{ name }}` with spaces is the same Variable (variables.md).
