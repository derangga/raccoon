# §9 Swap R to prove it

Part of the [Raccoon design graph](../DESIGN.md).

```
// Production                          // Tests
HTTPTransport.urlSession               HTTPTransport.scripted   → returns a canned Response
  (RaccoonData)                          (RaccoonTesting)         or SendError, and records
                                                                  the ResolvedRequest it got
FileReading.disk                       FileReading.dictionary   → [path: Data]
DataFolderStore(root: ~/Raccoon)       DataFolderStore(root: a fresh temp dir per test)
FolderWatch.fsevents                   FolderWatch.manual       → the test calls emit(paths)
SecretStore.keychain                   SecretStore.inMemory     → a dictionary
SessionStore(appSupport)               SessionStore(temp dir)
Pasteboard.general                     Pasteboard.recording     → keeps the last string
Clock.continuous                       Clock.fixed
```

**The rules need no R at all.** Curl Import, Copy as Curl, URL ↔ Params, resolution and
the presentation of a body are pure functions, so their tests are input → output tables with
no setup. That is where most of the tests are:

- **Curl Import fixtures**, ported from Yaak's `tests/index.test.ts` (51 cases) and Bruno's
  `parse-curl.spec.js` (53 cases). The inputs are copied; the expected outputs are rewritten
  in Raccoon's shapes, and each case where Raccoon differs on purpose (curl.md) says so.
- **Postman Import fixtures**, from Yaak's `importer-postman/tests/fixtures` (auth, nested,
  params, dynamic variables) and Bruno's `bruno-converters/tests/postman`. The expected
  output is an `ImportPlan`, notes included, so no Data Folder is needed.
- **Round trip**: `import(render(r)) == r` over the same fixtures.
- **Resolution**: Globals vs Active Environment precedence, Disabled Rows dropped, every
  Undefined Variable reported, a value containing `&` stays one param.
- **URL ↔ Params**: typing keeps Disabled Rows, `{{name}}` is not encoded.

**`HTTPTransport.scripted` is what makes sending testable without a server.** `TabModel.send`
with a scripted transport proves: the spinner state, that an Undefined Variable sends
nothing (the transport recorded zero requests), that cancel leaves `.idle`, and that closing
a Tab cancels the send.

**`HTTPTransport.urlSession` gets its own tests against a local server**, because the open
questions (`open-questions.md`) are all about what URLSession adds or removes, and only a
server that echoes the raw request can answer them.

The test column lives in the `RaccoonTesting` target as `ScriptedTransport`,
`DictionaryFileReading`, `ManualFolderWatch`, `InMemorySecretStore`, `RecordingPasteboard` and
`FixedClock`. DataFolderStore and SessionStore have no fake: the live one over a temp dir is
the test implementation.

If a test needs anything other than this table to run, the design has a hidden dependency.
