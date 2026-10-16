# Environment facts

Part of the [Raccoon design graph](../DESIGN.md).

Established by inspection, not assumption. A row here was checked on this machine or read in
source; anything that was not belongs in [open-questions.md](./open-questions.md).

| | |
|---|---|
| Toolchain | macOS 27.0.1, Xcode 27.0, Swift 6.4 (`swift --version`, `xcodebuild -version`, 2026-10-16). Deployment target is macOS 15 (Sequoia), so `@Observable` and the macOS 14 inspector split item are available, and nothing newer than macOS 15 may be used without an availability check |
| Reference licenses | `yaak/LICENSE` and `bruno/license.md` are both MIT. Test inputs and ideas may be copied with attribution; the code is TypeScript and is not being ported line by line |
| Yaak curl importer | `yaak/plugins/importer-curl/src/index.ts`, 777 lines. Tokenises with the `shlex` npm package, expands short-flag clusters by a table of value-taking flags, maps `Authorization: Bearer/Basic` into auth, treats `-d` without `Content-Type` as form-urlencoded, moves data to the query on `-G`, parses Chrome's multipart `--data-raw`. Folds cookies into one `Cookie` header, which Raccoon does not (curl.md) |
| Yaak curl tests | `yaak/plugins/importer-curl/tests/index.test.ts`, 51 cases, plus 11 GraphQL cases Raccoon does not need |
| Bruno curl importer | `bruno/packages/bruno-app/src/utils/curl/parse-curl.js` (587 lines) and `curl-to-json.js`, with 53 cases in `parse-curl.spec.js` |
| Headers URLSession adds | With an empty Headers table a GET goes out with `Host`, `Accept: */*`, `Accept-Language` (from the system languages, e.g. `en-GB,en-US;q=0.9,en;q=0.8`), `Connection: keep-alive`, `Accept-Encoding: gzip, deflate` (`gzip, deflate, br` over TLS) and `User-Agent: <process> CFNetwork/3896.100.1.1.1 Darwin/27.0.0`. A body with no `Content-Type` row also gets `Content-Type: application/x-www-form-urlencoded`, even a raw text body. Wire order is URLSession's, not the table's, though the table's rows keep their order among themselves. Measured with `URLSessionTransport` against the echo server's raw bytes, GET and POST, HTTP and HTTPS, 2026-10-16 (`URLSessionFactsTests`) |
| Manual Cookie header | Sent as set: with `httpShouldSetCookies = false` and no cookie storage, a `Cookie: manual=1` row arrives as `Cookie: manual=1`. A reply with `Set-Cookie` adds nothing to the next request. Measured against the echo server, 2026-10-16 (`URLSessionFactsTests`) |
| Response headers | No wire order and no duplicates. Two `Set-Cookie` replies arrive as one value `a=1; Path=/, b=2; Path=/` from both `allHeaderFields` and `value(forHTTPHeaderField:)`; `allHeaderFields` is a dictionary, so `Z-Last` before `A-First` is not recoverable. macOS 15 has no public API with the ordered list. Measured with the echo server's `/headers`, 2026-10-16 (`URLSessionFactsTests`) |
| Compression | URLSession decodes a `Content-Encoding: gzip` reply whatever was asked: with no `Accept-Encoding` row (wire: `gzip, deflate`), with `identity` and with `gzip`, the body arrives as the decoded bytes. An `Accept-Encoding` row replaces the default on the wire; an empty one is sent empty, not removed. `Response.byteCount` is the decoded size (16 bytes for a 36-byte gzip body), and the reply's `Content-Length` and `Content-Encoding` headers are kept. So `requestsCompression` has nothing to switch: it is never off. Measured with the echo server's `/gzip`, 2026-10-16 (`URLSessionFactsTests`) |
| No shell lexer in Foundation | Swift has no `shlex` equivalent in the standard library or Foundation, so `CurlLexer` is written by hand. It is the riskiest pure code in the app, which is why M2 is second |
