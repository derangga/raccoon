# §1 Shapes

Part of the [Raccoon design graph](../DESIGN.md).

## IDs

Branded where two of them could be swapped:

`RequestID` (UUID, written inside the Request file) · `TabID` (UUID, lives in the Session) ·
`VariableName` (validated: ASCII letters and digits, `_`, `-`, `.`; not empty)

A Request's identity is its `RequestID`, not its path. A path changes when a Folder is renamed
or a `git mv` happens, and "a Request is open in at most one Tab" must survive both. The path
is where the Request is, `RequestID` is which one it is.

Environments and Collections have no ID. Their name is their file or folder name, and nothing
else holds a reference to them except the Session's Active Environment, which is a name and
falls back to none when the file is gone (§4).

## Records

```
RequestDefinition        what Request and Draft share, and the only thing a Tab edits
  method                 String, uppercased. Not an enum: curl -X PURGE is a real method
  url                    String, the text before `?`, may hold {{name}}
  params                 [Row]
  headers                [Row]
  cookies                [Row]            Request Cookies
  body                   Body
  auth                   Auth
  settings               RequestSettings

Row                      name, value, isEnabled         a Disabled Row is isEnabled == false
Body                     .none
                         .raw(RawKind, String)          RawKind: json · text · xml
                         .formURLEncoded([Row])
                         .multipart([Part])
Part                     name, isEnabled, .text(String) | .file(path: String)
Auth                     .none · .basic(user, password) · .bearer(token)
RequestSettings          allowsInsecureTLS, followsRedirects, requestsCompression
                         all false in RequestDefinition.empty, as in curl: -k, -L and
                         --compressed are what turn them on

Request                  id: RequestID, name, definition         one file in the Data Folder
TreeNode                 .folder(name, [TreeNode]) · .request(RequestID, name, path)
                         .unreadable(path, reason)              §4: a file that did not decode
Collection               name, [TreeNode]

VariableEntry            name: VariableName, isEnabled, value: .plain(String) | .secret
Environment              name, [VariableEntry]
Globals                  [VariableEntry]
VariableScope            the Active Environment's entries over Globals, flattened once per
                         send or per highlight pass. A value, not a lookup service

Tab                      id: TabID
                         source: .draft | .request(RequestID)
                         definition: RequestDefinition           the working copy
                         baseline: RequestDefinition?            what is on disk; nil for a Draft
                         response: ResponseState                 never written to the Session
                         isChangedOnDisk: Bool
Session                  tabs: [TabSnapshot], selected: TabID?, activeEnvironment: String?
TabSnapshot              id, source, definition, baseline       a Tab minus its Response

ResolvedRequest          a RequestDefinition with every {{name}} substituted and every
                         Disabled Row dropped, Auth turned into an Authorization
                         header (auth is .none), plus url: URL, the base and the
                         percent-encoded params built once. What the transport sends, and
                         what Copy as Curl renders. Only `VariableResolver` can build one
Response                 status, headers [(name, value)] in wire order, body Data,
                         elapsed Duration, byteCount
ResponseState            .idle · .sending(since: ContinuousClock.Instant)
                         · .received(Response) · .failed(SendError)
                         · .notSent(ResolveError)          resolution failed, no byte went out

CurlImport               definition, ignoredFlags [String], fileReferences [String]
                         the second is the "ignored flags" note, the third are the
                         `@path`s that still have to be read (§6)
PasteTarget              .currentTab · .newDraftTab

PostmanFile              .collection(Collection) · .environment(Environment)
                         · .globals([VariableEntry]) · .notPostman(reason)
ImportPlan               collections, environments, globals to add, each with its final name
                         (" 2" on a collision), and [ImportNote]
ImportNote               what was dropped or changed, and the Requests it applies to:
                         .scriptsDropped · .authNotSupported(type) · .binaryBody · .pathVariable
                         · .dynamicVariable(name) · .fileOnlyName(path) · .globalSkipped(name)
                         · .examplesDropped · .renamed(from, to)

Theme                    name, flavors [Flavor]
Flavor                   name, appearance: .light | .dark, colors [ColorToken: ThemeColor]
                         ThemeColor is #rrggbb as three bytes; not Color, which SwiftUI owns
ThemeChoice              theme name, light Flavor name, dark Flavor name
```

`RequestDefinition.empty` is the empty Draft: method `GET`, every other field empty or off.

## Why these are not simpler

**Dirty is computed, not stored.** `tab.isDirty == (baseline != nil && definition != baseline)`.
A stored flag has to be right after every edit, every undo, every save and every reload, and
undoing back to the saved text must clear it. Equality over `RequestDefinition` does that by
construction, which is why every record in it is `Equatable` and nothing in it is a reference.

**Disabled is a property of a Row, not a separate list.** Toggling a row does not move it, so
the table order is the order the user typed, and the order the headers go out in.

**`url` holds no query string.** Params are the source of truth (`editing.md`), so the `?` part
of the URL bar is always rendered from `params`. Two places holding the same query is two
places that disagree after a Disabled Row is toggled.

**`method` is a String.** An enum would make Curl Import refuse `-X PURGE` or `-X PROPFIND`,
and refusing a pasted request is worse than an unusual method.

**`.secret` holds no value.** The value lives in the Keychain under the Variable's name and the
Environment's name. A `VariableEntry` that carried it would be one `Codable` encode away from
writing it into a file that is in git.

**`ResolvedRequest` has no public init.** The transport takes only a `ResolvedRequest`, so a
request with an Undefined Variable cannot reach the socket: the type that the transport
accepts does not exist until resolution succeeded.

## Errors

Named, typed, carrying what the user needs to see:

```
CurlImportError          .unterminatedQuote(position) · .noURL
ResolveError             .undefined([VariableName])       every missing one, not the first
                         .invalidURL(String)              the URL text after substitution
SendError                .fileMissing(path)               a multipart file part, read by
                                                          the transport before sending
                         .timedOut
                         .untrustedCertificate(host)
                         .transport(URLError.Code, String)
StoreError               .unreadable(path, reason) · .undecodable(path, reason)
                         .unwritable(path, reason)
SecretError              .unavailable(OSStatus)
ImportError              .unwritable(collection, reason)    per Collection; the others still land
```

Cancelling a send is not an error. It is `ResponseState.idle` (§4).
