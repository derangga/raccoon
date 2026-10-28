# §1 Shapes

Part of the [Raccoon design graph](../DESIGN.md).

## IDs

Branded where two of them could be swapped:

`RequestID` (UUID, written inside the Request file) · `TabID` (UUID, lives in the Session) ·
`WorkspaceID` (UUID, written in the Data Folder's `raccoon.json`) ·
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
  pathVariables          [String: String]   Path Variable name -> value, no `:`. Holds only
                         names with a non-empty value; "" is absent, so clearing a value
                         returns the definition to what it was
  headers                [Row]
  cookies                [Row]            Request Cookies
  body                   Body
  auth                   Auth
  settings               RequestSettings

Row                      name, value, isEnabled         a Disabled Row is isEnabled == false
PathVariableToken        range: NSRange (UTF-16, covers `:` and the name), name: String
                         one Path Variable in `url`, found by PathVariables.tokens(in:)
                         (editing.md). Names are not VariableNames: Unicode letters and
                         digits, `_` and `-`, no `.`
Body                     .none
                         .raw(RawKind, String)          RawKind: json · text · xml
                         .formURLEncoded([Row])
                         .multipart([Part])
Part                     name, isEnabled, .text(String) | .file(path: String)
HighlightRange           range: NSRange (UTF-16, as text storage takes it), token: ColorToken
BodyType                 .none · .raw(RawKind) · .formURLEncoded · .multipart
                         what the Body Type pop-up picks; Body.type reads it off a Body
Auth                     .none · .basic(user, password) · .bearer(token)
AutomaticHeader          name, value: String?          a header sent that no row sets;
                         nil is computed at send (Content-Length)
RequestSettings          allowsInsecureTLS, followsRedirects
                         both false in RequestDefinition.empty, as in curl: -k and -L
                         are what turn them on

Request                  id: RequestID, name, definition         one file in the Data Folder
TreeNode                 .folder(name, [TreeNode]) · .request(RequestID, name, method, path)
                         method is for the sidebar badge
                         .unreadable(path, reason)              §4: a file that did not decode
Collection               name, [TreeNode]
DataFolderScan           files: [path: Data], folders: Set<path>    what scan returns
DataFolderIndex          collections: [Collection], RequestID -> path and name, insert
RequestFileError         .notJSON(line) · .unknownVersion(Int) · .malformed(String)
                         .reason is the unreadable row's text (design-system §6)

VariableEntry            name: VariableName, isEnabled, value: .plain(String) | .secret
Environment              name, [VariableEntry]
Globals                  [VariableEntry]
VariableScope            the Active Environment's entries over Globals, flattened once per
                         send or per highlight pass. A value, not a lookup service
VariableToken            range: NSRange (UTF-16), name: VariableName      one {{name}} in a field
VariableKinds            name -> .defined | .secret, from the same merge as VariableScope but
                         with no secret values: what highlighting and the tooltip need without a
                         Keychain read; also each name's source (Environment name or "Globals")
VariableTooltip          .defined(name, source, value) | .secret(name, source) |
                         .undefined(name, environment?): what the hover tooltip says
VariableCompletion.Query range: NSRange (UTF-16, after `{{` up to the caret), prefix: the
                         name characters typed so far
VariableCompletion.Insertion  range: NSRange, text: "name}}", caret: Int
VariableSuggestion       name, source (Environment name or "Globals"), isSecret: one row of the
                         suggestion list; never a value
BrokenEnvironment        name, reason: an environments/*.json that did not decode, kept by the
                         window so the sheet can list it read-only; never in the picker
VariableEdit.Refusal     invalidName | duplicate(VariableName): why the sheet refused a name
EnvironmentEditError     empty | nameTaken(String) | store(StoreError) | secret(SecretError)
EnvironmentFile.Decoded  entries [VariableEntry], droppedSecretValues [VariableName]
                         the second is the boundary warning (boundary.md), logged by the window

Tab                      id: TabID
                         source: .draft | .request(RequestID)
                         definition: RequestDefinition           the working copy
                         baseline: RequestDefinition?            what is on disk; nil for a Draft
                         response: ResponseState                 never written to the Session
                         isChangedOnDisk: Bool
Session                  tabs: [TabSnapshot], selected: TabID?, activeEnvironment: String?
TabSnapshot              id, source, definition, baseline       a Tab minus its Response
Breadcrumb               segments [BreadcrumbSegment]           derived from the index by RequestID,
                         never stored on the Tab; a Draft's is its Tab title alone
BreadcrumbSegment        title, target: String?                 target is a sidebar path: a Collection's
                         name, a Folder's path, or a file's path, relative to the Data Folder, as
                         SidebarItem.path. nil is not clickable. The Request's segment is titled
                         by the name inside its file, never by the file name
BreadcrumbFit            .all · .collapsed(hidden: Range<Int>)  which middle segments "…" stands
                         for; the first and the last are never in the range

ResolvedRequest          a RequestDefinition with every {{name}} substituted and every
                         Disabled Row dropped, Auth turned into an Authorization
                         header (auth is .none), plus url: URL, the base and the
                         percent-encoded params built once. What the transport sends, and
                         what Copy as Curl renders. Only `VariableResolver` can build one
Response                 status, headers [(name, value)] sorted by name, body Data,
                         elapsed Duration, byteCount
MessageLine              .error(text) · .note(text)       the line under the URL bar, on the
                         TabModel, never saved: a note goes on the next URL edit, an error on
                         the next send or paste
ResponseState            .idle · .sending(since: ContinuousClock.Instant)
                         · .received(Response) · .failed(SendError, after: Duration)
                         · .notSent(ResolveError)          resolution failed, no byte went out

CurlImport               definition, ignoredFlags [String], fileReferences [String],
                         skippedCommands Int
                         the second is the "ignored flags" note, the third are the
                         `@path`s that still have to be read (§6), the fourth is the
                         "2 more commands" note
PasteTarget              .currentTab · .newDraftTab

PostmanFile              .collection(PostmanCollection) · .environment(PostmanEnvironment)
                         · .globals([PostmanVariable]) · .notPostman
                         in Postman's terms (`key`, `disabled`, `mode`, `listen`), not Raccoon's:
                         PostmanMapping turns them into an ImportPlan. Type variance is settled
                         here (url string or object, host and path string or array, auth params
                         array or object, values of any JSON type as text); nothing is dropped
                         but an item with neither `item` nor `request`, kept as .other(name).
                         .notPostman carries no reason: the sheet's row has one sentence (§4)
ImportPlan               collections, environments, globals to add, each with its final name
                         (" 2" on a collision), and [ImportNote]
ImportCollection         name, nodes [ImportNode]: one planned Collection
ImportEnvironment        name, variables [ImportVariable]: one planned Environment
ImportVariable           name VariableName, isEnabled, value .plain(String) · .secret(String)
                         a planned Environment or Global. A secret carries its value only so
                         Import can hand it to SecretStore.set; `entry` is the VariableEntry
                         written to the file, `.secret` with no value. Not Codable
ImportNode               .folder(name, [ImportNode]) · .request(Request)     in Postman's order;
                         file names are chosen when the plan is written (RequestFileName)
ImportResult             collections [String]: the ones that landed, by folder name, in plan
                         order; problems [ImportError]: everything else in the plan landed
ImportNote               kind, names: what was dropped or changed, and the Requests it applies
                         to by name (a Folder's name for its description, an item's for a
                         skipped one, a Variable's for a Variable, the Collection's for its
                         variables, the old name for a rename). The count is names.count. One
                         note per kind, in the order first met. Kinds:
                         .scriptsDropped · .authNotSupported(type) · .authInherited
                         · .binaryBody
                         · .dynamicVariable(name) · .fileOnlyName(path) · .examplesDropped
                         · .descriptionsDropped · .itemsSkipped
                         · .renamed(from, to) · .globalSkipped · .collectionVariables
                         · .variableNameInvalid

LineIndex                starts [Int]: the UTF-16 offset of each line start. Lines break
                         where NSString.lineRange breaks them: \n, \r, \r\n, U+2028, U+2029,
                         U+0085. Always at least one line
FoldRegion               openLine, closeLine, cut Range<Int>: UTF-16, from the open line's
                         terminator to the close line's first non-space character. Folded,
                         the cut is shown as " … "
FoldSet                  folded Set<Int>: the openLine of each folded Fold Region. View state
FoldedText               the outermost folded regions in text order, and offsets mapped
                         between the body and the shown text. Derived, never stored

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

**`pathVariables` is a dictionary, not `[Row]`.** A Row has an enabled flag and an order the
user chose; a Path Variable has neither. Its names and their order come from `url`, so a
second list holding the names would disagree with the URL after the first edit. Keyed by name,
a value cannot be attached to the wrong name, and `[String: String]` is `Equatable`, so Dirty,
Changed on Disk and the Session compare it with the rest of the definition. It is the inverse
of Params, where the table is the source and the URL is rendered from it. An empty value is
absent for one reason: a user who types a value and deletes it again must get back a
definition equal to the saved one, and no `"id": ""` may reach the file.

**A name that leaves `url` loses its value.** Every URL edit prunes `pathVariables` to the
names still in `url`, so typing `:i` and then `:id` does not leave `i` behind to be written to
git. The URL edit and its prune are one undo step, so Undo brings the value back. The URL has no
disabled part, so unlike Params there is no Disabled Row to keep a value alive.

**`url` holds no query string.** Params are the source of truth (`editing.md`), so the `?` part
of the URL bar is always rendered from `params`. Two places holding the same query is two
places that disagree after a Disabled Row is toggled.

**`method` is a String.** An enum would make Curl Import refuse `-X PURGE` or `-X PROPFIND`,
and refusing a pasted request is worse than an unusual method.

**`.secret` holds no value.** The value lives in the Keychain under the Variable's name, the
Environment's name and the WorkspaceID (workspaces.md). A `VariableEntry` that carried it would be one `Codable` encode away from
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
                         .transport(URLError.Code, String, host)  host[:port] the send went to
StoreError               .unreadable(path, reason) · .undecodable(path, reason)
                         .unwritable(path, reason)
SecretError              .unavailable(OSStatus)
                         .raccoonJSONUnreadable           the Workspace has no id (§4): set and
                                                          delete fail, the row reads
                                                          "raccoon.json can't be read"
ImportError              .collectionUnwritable(name, StoreError)   nothing of it remains; the
                                                          others still land
                         .environmentUnwritable(name, StoreError)  its secrets deleted again
                         .globalsUnwritable(StoreError)    no Global was added
                         .secretNotStored(name, environment?, SecretError)  written as a secret
                                                          with no value, undefined until set;
                                                          environment nil is Globals
FormatError              .notValid(line, column)          the body text is left unchanged
```

Cancelling a send is not an error. It is `ResponseState.idle` (§4).
