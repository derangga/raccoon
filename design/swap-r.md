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
SessionStore(appSupport, root)         SessionStore(temp dir, root)
ClipboardWriter.general                ClipboardWriter.recording → keeps the last string
InstantSource.continuous               InstantSource.fixed
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
- **Path Variables**: the token table in editing.md as `PathVariables.tokens` input → names;
  prune and setValue as input → output; `PathEncoding.segment` as value → bytes; resolution
  with a value, none, an empty one, `{{x}}` in a value, an undefined one, and `/:{{x}}`;
  `RequestFile` and `SessionFile` round trips with and without the key. The server-side
  facts (`/` and `%2F` reach the echo server as typed) are one `URLSessionFactsTests` case.

**`HTTPTransport.scripted` is what makes sending testable without a server.** `TabModel.send`
with a scripted transport proves: the spinner state, that an Undefined Variable sends
nothing (the transport recorded zero requests), that cancel leaves `.idle`, and that closing
a Tab cancels the send.

**`HTTPTransport.urlSession` gets its own tests against a local server**, because the open
questions (`open-questions.md`) are all about what URLSession adds or removes, and only a
server that echoes the raw request can answer them.
That server is `withEchoServer(tls:)` in `Tests/RaccoonDataTests`: a fresh localhost port per
test, `/echo`, `/delay/<ms>`, `/redirect` and `/bytes/<n>`, and a self-signed `localhost`
certificate from `Fixtures/localhost.p12` (password `raccoon`, imported in memory only).

The test column lives in the `RaccoonTesting` target as `ScriptedTransport`,
`DictionaryFileReading`, `ManualFolderWatch`, `InMemorySecretStore`,
`RecordingClipboardWriter` and `FixedInstantSource`. The production column lives in
`RaccoonData`, named the same way (`DiskFileReading`, `SystemClipboardWriter`,
`ContinuousInstantSource`, …). DataFolderStore and SessionStore have no fake: the live one
over a temp dir is the test implementation.

InspectorMemory is not a port: the composition root backs its remember closures with
UserDefaults, and a test passes the values it wants, or a UserDefaults suite of its own,
cleared first, to prove the round trip across a relaunch.

If a test needs anything other than this table to run, the design has a hidden dependency.
