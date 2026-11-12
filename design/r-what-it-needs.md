# §5 R — what each node needs

Part of the [Raccoon design graph](../DESIGN.md).

## Rules: pure, in RaccoonDomain, need nothing

```
CurlDetector, CurlLexer, CurlFlags, CurlMapping, CurlImporter     text -> CurlImport
CurlRenderer                                                      ResolvedRequest -> text
URLText.split / join, Params.merge                                the URL bar ↔ Params
PathVariables.tokens / .names / .prune / .setValue                url text -> the `:name` tokens, and
                                                                  the values kept for them
PathEncoding.segment                                              a Path Variable value -> what
                                                                  goes in the path
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
HexDump                                                           bytes -> the Hex view's text
Timing(marks)                                                     a request's marks -> its phases
TimelineText.blocks, .showsHeadersNote                            Response -> the Timeline's lines,
                                                                  and whether any Redirect has headers
ResponseFileName.suggest                                          Response -> the name Save offers
FindMatches, .first(atOrAfter:), .step, .count                    query + body -> the Find panel's
                                                                  matches, current one and count
FoldSet.unfolding(_:in:)                                          a match -> the folds that hide it,
                                                                  opened; the rest kept
                                                                  (image/* is decided by the header; the
                                                                  decode is NSImage's, in Raccoon.app)
Highlighter.curl                                                  curl command -> its token ranges
CloseStep(hasLosableContent:alwaysDiscards:)                      closing a Tab -> ask, or close
LeaveConfirm.message(count:)                                      Tabs with something to lose -> the
                                                                  Leave sheet's sentence
WindowModel.confirmLeave                                          losing Tabs -> may the switch go on;
                                                                  set at the composition root, refuses
                                                                  until then
LineIndex, FoldRegion.find                                        text -> line starts, Fold Regions
FoldSet.toggle, .innermost(at:), FoldedText                       what is folded -> what is shown,
                                                                  and offsets mapped both ways
ResponseState.showsSpinner(at:)                                   .sending + now -> spinner, §7 150 ms
TreeDecoder, DataFolderIndex                                      files -> sidebar tree
Breadcrumb.of                                                     source, title, index, last known
                                                                  -> segments
Breadcrumb.fit                                                    segment widths + room -> which
                                                                  middle segments "…" stands for
SidebarPath.ancestors(of:)                                        "A/B/C/F.json" -> ["A", "A/B", "A/B/C"]
WorkspaceFile encode·decode                                       raccoon.json <-> WorkspaceID
WorkspaceList.titles                                              paths -> pop-up titles, a
                                                                  parent folder only on a clash
RequestFile / EnvironmentFile / SessionFile encode·decode         Codable, versioned
Tab.isDirty, Tab.hasLosableContent                                computed, never stored
ThemeChoice.flavor(for:)                                          appearance -> Flavor
PostmanImporter.read, PostmanMapping.plan                         export bytes -> ImportPlan
PostmanExporter.collection                                        ExportCollection, id -> Collection
                                                                  v2.1 bytes
PostmanExporter.environment                                       Environment, EnvironmentSecrets, id,
                                                                  date, version -> Environment bytes
CredentialScan.find                                               Requests -> [CredentialFinding]
DocsStyle.ranges                                                  markdown -> styled ranges (docs.md)
GraphQLPayload.encode / .text, GraphQLMethod.forPick              GraphQL body -> the JSON sent;
                                                                  the method a pick sets
Highlighter.ranges(_, .graphql)                                   GraphQL query -> token ranges
Example.from(response)                                            Response -> Example
ExampleFile (inside RequestFile) encode·decode                    `examples` <-> [Example]
MockRoutes.build                                                  Requests -> [MockRoute]
MockRequestHead.parse                                             socket bytes -> head, or 400/413/501
MockMatch.answer                                                  routes + head + CORS -> MockReply
MockReply.bytes                                                   MockReply -> HTTP/1.1 bytes
ExportStepReveal.starts                                           when each step finished,
                                                                  reduceMotion -> when its check
                                                                  starts, 60 ms apart
```

Path Variables add no port and no boundary: reading the URL, setting a value and encoding it
are pure, and the file key rides the existing `RequestFile` and `SessionFile` encoders.

Everything a test would want to assert on is in this list. That is the point of it: Curl
Import, resolution and the URL ↔ Params sync are the three places the app can be wrong
without crashing, and none of them needs a socket, a file or a window to test.

## Ports: protocols in RaccoonDomain, implemented in RaccoonData

```
HTTPTransport     send(ResolvedRequest) async throws(SendError) -> Response
                  the Request Settings ride inside the ResolvedRequest. The live one
                  reads multipart file parts through the FileReading given to its init,
                  and its init's `timeout` is only the fallback for a Request that
                  sets no Request Timeout of its own
FileReading       read(path) throws(StoreError) -> Data       @file and multipart parts
FileWriting       write(Data, to: URL) throws(StoreError)     Postman Export and Save Response
                  Body: a path the user picked, outside the Data Folder. Atomic: a temp file in the target's
                  folder, then replace, so a failed write leaves the old file as it was.
                  StoreError.unwritable(path, reason) carries url.path. Never records in
                  the WriteLedger: the Data Folder is not what it writes. DataFolderStore
                  cannot do this: its paths are relative to its root
DataFolderStore   ensureExists, scan -> DataFolderScan (files [path: Data] and every
                  folder, so an empty Collection or Folder shows), read, write (atomic), move, trash,
                  createDirectory, writeDirectory(DataFolderScan, to:) (temp + rename, so empty
                  Folders land too); all throws(StoreError).
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
MockListening     listen(port: UInt16?, handler) async throws(MockError) -> MockListener
                  binds 127.0.0.1, port nil lets the system pick; the listener has `port` and
                  `stop()`. For each connection it reads until MockRequestHead.parse has a
                  head and the body's bytes are drained, calls `handler(head) async -> MockReply`
                  and writes MockReply.bytes. Network.framework NWListener in RaccoonData; the
                  test one in RaccoonTesting calls the handler with heads it is given
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
                                                    the index and the WriteLedger. The sheet
                                                    reads the picked files through a
                                                    FileReading the composition root builds
Export Collection DataFolderStore, FileWriting      through the window, which owns the index, the
                                                    Tabs and the store. The sheet reads and writes
                                                    nothing itself: it draws the ExportStep stream
                                                    and the ExportPlan the window hands it. No
                                                    SecretStore: a Collection file holds `{{name}}`
                                                    only
Export Environment SecretStore, FileWriting         SecretStore only when Include secret values is
                                                    ticked, and only after the save panel returns.
                                                    No DataFolderStore: the Environment is the one
                                                    the window already decoded
  id, date, version                                 a `() -> UUID`, a `() -> Date` and a String
                                                    from the composition root, as Import's newID
                                                    is. Not ports: each is one value, and a test
                                                    passes a fixed one
Save Response Body FileWriting                      through the Tab, which holds the Response. The
                                                    save panel is AppKit's, in Raccoon.app; the
                                                    name it offers is ResponseFileName.suggest
Copy (Body toolbar) ClipboardWriter                 through the Tab, which already holds one for
                                                    Copy as Curl
Find panel        nothing                           pure rules over the text the viewer holds
Redirects, Timing nothing new                       the live transport's per-send SendDelegate
                                                    records them; no port changes
Import from Postman… in the Environments sheet
                  nothing                           one closure: close the sheet, then send
                                                    AppDelegate.importFromPostman(_:) up the responder
                                                    chain, once the sheet has finished closing
Examples          DataFolderStore, FileReading      through the window, which owns the index and
                                                    the WriteLedger: every Example write is a
                                                    read-modify-write of the Request file. FileReading
                                                    for Replace from File…
Mock Server       MockListening, DataFolderStore    through the window: it builds the routes from
                                                    the Collection's files and holds one MockServer
                                                    per running Collection. WorkspaceFile for the
                                                    remembered port
Docs, GraphQL     nothing new                       pure rules and the existing TabModel.edit
BreadcrumbBar     the selected Tab's Breadcrumb,        no port. The window derives the
                  and one closure, select(path)         Breadcrumb from its index and hands it
                                                        down; the bar reads no file and holds no
                                                        index. The closure is MainSplitViewController
                                                        .revealSidebar, then SidebarViewController
                                                        .reveal(path)
Sending loader    the bundled JSON as `() -> Data?`,    no port. `Data?` because a missing file is an
                  Reduce Motion as `() -> Bool`, and    escape, not a crash; the closure is
                  the window's occlusion and            Bundle.module in the app, a fixed value in
                  miniaturise notifications             tests. Reduce Motion is the closure the
                                                        banner already gets. The rule
                                                        SendingLoaderMode.of(state, now,
                                                        reduceMotion, bodyHeight, assetLoaded) is
                                                        pure but lives in Raccoon, not
                                                        RaccoonDomain: it takes a layout height, and
                                                        Domain does not change. lottie-ios is linked
                                                        by Raccoon alone
```

**`TabModel` does not need `DataFolderStore`.** Saving goes through the window, which owns
the index and the WriteLedger. A Tab that could write files itself could write one the index
does not know about.
