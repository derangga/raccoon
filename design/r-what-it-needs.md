# §5 R — what each node needs

Part of the [Raccoon design graph](../DESIGN.md).

## Rules: pure, in RaccoonDomain, need nothing

```
CurlDetector, CurlLexer, CurlFlags, CurlMapping, CurlImporter     text -> CurlImport
CurlRenderer                                                      ResolvedRequest -> text
URLText.split / join, Params.merge                                the URL bar ↔ Params
BodyConversion, Headers.contentType                               Body Type switches
AutomaticHeaders.rows                                             ResolvedRequest -> the headers
                                                                  sent that no row sets
VariableTokens.ranges                                             {{…}} positions
VariableKinds.tooltip                                             name -> what the hover popover says
VariablesPane                                                     definition + Environment + Globals
                                                                  -> the inspector's groups
VariableCompletion.query / .insertion                             text + caret -> the typed `{{name`,
                                                                  and what accepting a name writes
VariableKinds.suggestions                                         prefix -> the names offered
VariableScope, VariableResolver                                   definition -> ResolvedRequest
PasteTarget.for                                                   current Tab or a new one
ResponseBody.presentation, Highlighter.ranges                     bytes -> what to draw
LineIndex, FoldRegion.find                                        text -> line starts, Fold Regions
FoldSet.toggle, .innermost(at:), FoldedText                       what is folded -> what is shown,
                                                                  and offsets mapped both ways
ResponseState.showsSpinner(at:)                                   .sending + now -> spinner, §7 150 ms
TreeDecoder, DataFolderIndex                                      files -> sidebar tree
WorkspaceFile encode·decode                                       raccoon.json <-> WorkspaceID
WorkspaceList.titles                                              paths -> pop-up titles, a
                                                                  parent folder only on a clash
RequestFile / EnvironmentFile / SessionFile encode·decode         Codable, versioned
Tab.isDirty, Tab.hasLosableContent                                computed, never stored
ThemeChoice.flavor(for:)                                          appearance -> Flavor
PostmanImporter.read, PostmanMapping.plan                         export bytes -> ImportPlan
```

Everything a test would want to assert on is in this list. That is the point of it: Curl
Import, resolution and the URL ↔ Params sync are the three places the app can be wrong
without crashing, and none of them needs a socket, a file or a window to test.

## Ports: protocols in RaccoonDomain, implemented in RaccoonData

```
HTTPTransport     send(ResolvedRequest) async throws(SendError) -> Response
                  the Request Settings ride inside the ResolvedRequest. The live one
                  reads multipart file parts through the FileReading given to its init
FileReading       read(path) throws(StoreError) -> Data       @file and multipart parts
DataFolderStore   ensureExists, scan -> DataFolderScan (files [path: Data] and every
                  folder, so an empty Collection or Folder shows), read, write (atomic), move, trash,
                  createDirectory, writeDirectory (temp + rename); all throws(StoreError).
                  The root is given to init; every path is relative to it
FolderWatch       events(root) -> AsyncStream<[String]>        changed paths
SecretStore       get / set / delete (environment?, name) throws(SecretError)
                  the Keychain, one per Workspace. environment nil is Globals. One
                  generic password per secret: service `Raccoon/<WorkspaceID>` for
                  Globals or `Raccoon/<WorkspaceID>/<Environment>`, account the
                  Variable name
SessionStore      read -> Data? / write(Data) / delete() throws(StoreError)
                  Application Support, one file per Workspace: sessions/<key>.json, the
                  key derived from the root given to init (workspaces.md); bytes only,
                  SessionFile owns the format.
                  setAside() throws(StoreError) -> String: renames <key>.json to
                  <key>.corrupt-<date>.json and returns the new path; the date comes
                  from a clock given to init
ClipboardWriter   setString                                    Copy as Curl
InstantSource     now                                          .sending(since:)
```

Each port is a protocol with one live implementation and one test implementation (§9). The
test implementations live in the `RaccoonTesting` target, which only test targets link. No
port has a `shared` instance; the app's composition root builds them once and hands them to
the models that need them.

## Who needs what

```
TabModel          HTTPTransport, SecretStore, InstantSource
WindowModel       DataFolderLocation, FolderWatch, InstantSource
                                                    DataFolderLocation is the open root and the
                                                    list: open(root) -> DataFolderStore,
                                                    SecretStore(id) and SessionStore(root),
                                                    remember(root), add / remove; the
                                                    composition root backs it with UserDefaults.
                                                    InstantSource for SessionWriter's coalescing.
                                                    The stores live for one withDataFolder (§8)
CurlImport flow   FileReading                       only for @file references
Copy as Curl      SecretStore, ClipboardWriter
ThemeController   UserDefaults, the app bundle,     no port: all three are already injectable.
                  an appearance source              NSApp in the app, an NSView in tests
MainSplitViewController,  InspectorMemory              whether the inspector is open, its width
InspectorViewController                                 and its pane, and how to remember each;
                                                        the composition root backs it with
                                                        UserDefaults (Q14), tests with a
                                                        suite of their own or nothing
Postman Import    FileReading, DataFolderStore, SecretStore      through the window, which owns
                                                    the index and the WriteLedger
```

**`TabModel` does not need `DataFolderStore`.** Saving goes through the window, which owns
the index and the WriteLedger. A Tab that could write files itself could write one the index
does not know about.
