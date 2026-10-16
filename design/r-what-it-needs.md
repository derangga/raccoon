# §5 R — what each node needs

Part of the [Raccoon design graph](../DESIGN.md).

## Rules: pure, in RaccoonDomain, need nothing

```
CurlDetector, CurlLexer, CurlFlags, CurlMapping, CurlImporter     text -> CurlImport
CurlRenderer                                                      ResolvedRequest -> text
URLText.split / join, Params.merge                                the URL bar ↔ Params
BodyConversion, Headers.contentType                               Body Type switches
VariableTokens.ranges                                             {{…}} positions
VariableScope, VariableResolver                                   definition -> ResolvedRequest
PasteTarget.for                                                   current Tab or a new one
ResponseBody.presentation, Highlighter.ranges                     bytes -> what to draw
TreeDecoder, DataFolderIndex                                      files -> sidebar tree
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
DataFolderStore   ensureExists, scan -> [path: Data], read, write (atomic), move, trash,
                  createDirectory, writeDirectory (temp + rename); all throws(StoreError).
                  The root is given to init; every path is relative to it
FolderWatch       events(root) -> AsyncStream<[String]>        changed paths
SecretStore       get / set / delete (environment?, name) throws(SecretError)
                  the Keychain. environment nil is Globals
SessionStore      read -> Data? / write(Data) throws(StoreError)   Application Support;
                  bytes only, SessionFile owns the format
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
WindowModel       DataFolderStore, FolderWatch, SessionStore, SecretStore
CurlImport flow   FileReading                       only for @file references
Copy as Curl      SecretStore, ClipboardWriter
ThemeController   UserDefaults, the app bundle      no port: both are already injectable
Postman Import    FileReading, DataFolderStore, SecretStore      through the window, which owns
                                                    the index and the WriteLedger
```

**`TabModel` does not need `DataFolderStore`.** Saving goes through the window, which owns
the index and the WriteLedger. A Tab that could write files itself could write one the index
does not know about.
