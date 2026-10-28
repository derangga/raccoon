# §6 Boundary — `unknown → trusted`

Part of the [Raccoon design graph](../DESIGN.md).

```
pasted text in the URL bar  → CurlImport                // CurlImporter, pure. The only
                                                        //   parser of shell syntax
typed text in the URL bar   → url + [Row]               // URLText.split, every keystroke
the same text               → [PathVariableToken]       // PathVariables.tokens: draws the
                                                        //   table, and picks what send replaces
<Data Folder>/**/*.json     → Request                   // `version` read first; an unknown
                                                        //   version is .unreadable, never
                                                        //   guessed at
globals.json, environments/*.json → Globals, Environment // a .secret entry with a "value"
                                                        //   key is decoded with the value
                                                        //   dropped and a warning: someone
                                                        //   hand-edited a secret into git
raccoon.json                → WorkspaceID               // `version` read first; undecodable
                                                        //   means no secrets, never a rewrite
sessions/<key>.json         → Session                   // Application Support, ours, but
                                                        //   written by an older build too
UserDefaults Workspaces     → [path]                    // a path that no longer loads stays;
                                                        //   loading it is the check
Keychain item               → String                    // UTF-8 or treated as absent
a file named by @path       → Data                      // read at import (--data-binary)
                                                        //   or at send (multipart)
URLSession reply            → Response                  // status, headers in wire order,
                                                        //   body bytes. Nothing decoded here
Response.body               → ResponseBody presentation // JSON/XML parsed off the main
                                                        //   actor; failure is .raw
Response.body, image/*      → NSImage                   // in Raccoon.app, on show; nil is
                                                        //   the binary state
FolderWatch event paths     → [RequestID]               // via DataFolderIndex, so a path
                                                        //   that is not a Request is dropped
a Postman export file       → PostmanFile               // PostmanImporter, pure. Not JSON
                                                        //   or an unknown schema is
                                                        //   .notPostman, never a throw
bundled theme JSON          → Theme                     // ours: a failure is DIE (§4)
UserDefaults ThemeChoice    → ThemeChoice               // unknown names fall back
UserDefaults Inspector…     → InspectorMemory           // open, width, pane; a wrong type is
                                                        //   absent, the width clamped by the split
```

**Every JSON file Raccoon writes carries `"version": 1`.** The Data Folder is a format other
people's git repositories will hold (collections.md). The first change to it needs to know what it
is reading, and adding the field later means files without it, which is a second format.

**Decoding is hand-written where absence has meaning.** `isEnabled` absent means true, `body`
absent means `.none`, `settings` absent means the defaults. A file someone wrote by hand
with only `method` and `url` must open, which synthesised `Codable` refuses.

**`pathVariables` is one optional key of the Request file, and of the Session's definitions.**
`RequestFile` stays `version: 1`: the key is an object of Path Variable name to value, written
with sorted keys like the rest and **omitted when there are none**, so every file saved before
this key existed stays byte-identical when saved again, git shows no diff, and Changed on Disk
does not fire. Absent means no Path Variables. The Request file and the Session share one
definition encoding (`DefinitionJSON`), so a Draft and a Dirty edit carry their values through
a relaunch with no second format. A value that is not a string, or a `pathVariables` that is
not an object, is `.malformed("pathVariables")`, as a wrong type is for any other key: the file
is `.unreadable`, kept byte for byte, never rewritten. An empty-string value is read as absent
(an empty value is no value, shapes.md), and a name the URL no longer has is **kept**: decoding
never edits what it read, so the baseline equals the disk. It does nothing until the next URL
edit prunes it (editing.md).

**Nothing past this list parses.** Inside the graph a `Request` is a `Request`; no node
re-validates a URL it was handed or re-reads a file to check it.
