# §6 Boundary — `unknown → trusted`

Part of the [Raccoon design graph](../DESIGN.md).

```
pasted text in the URL bar  → CurlImport                // CurlImporter, pure. The only
                                                        //   parser of shell syntax
typed text in the URL bar   → url + [Row]               // URLText.split, every keystroke
<Data Folder>/**/*.json     → Request                   // `version` read first; an unknown
                                                        //   version is .unreadable, never
                                                        //   guessed at
globals.json, environments/*.json → Globals, Environment // a .secret entry with a "value"
                                                        //   key is decoded with the value
                                                        //   dropped and a warning: someone
                                                        //   hand-edited a secret into git
session.json                → Session                   // Application Support, ours, but
                                                        //   written by an older build too
Keychain item               → String                    // UTF-8 or treated as absent
a file named by @path       → Data                      // read at import (--data-binary)
                                                        //   or at send (multipart)
URLSession reply            → Response                  // status, headers in wire order,
                                                        //   body bytes. Nothing decoded here
Response.body               → ResponseBody presentation // JSON/XML parsed off the main
                                                        //   actor; failure is .raw
FolderWatch event paths     → [RequestID]               // via DataFolderIndex, so a path
                                                        //   that is not a Request is dropped
a Postman export file       → PostmanFile               // PostmanImporter, pure. Not JSON
                                                        //   or an unknown schema is
                                                        //   .notPostman, never a throw
bundled theme JSON          → Theme                     // ours: a failure is DIE (§4)
UserDefaults ThemeChoice    → ThemeChoice               // unknown names fall back
```

**Every JSON file Raccoon writes carries `"version": 1`.** The Data Folder is a format other
people's git repositories will hold (collections.md). The first change to it needs to know what it
is reading, and adding the field later means files without it, which is a second format.

**Decoding is hand-written where absence has meaning.** `isEnabled` absent means true, `body`
absent means `.none`, `settings` absent means the defaults. A file someone wrote by hand
with only `method` and `url` must open, which synthesised `Codable` refuses.

**Nothing past this list parses.** Inside the graph a `Request` is a `Request`; no node
re-validates a URL it was handed or re-reads a file to check it.
