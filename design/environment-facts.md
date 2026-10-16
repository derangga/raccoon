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
| No shell lexer in Foundation | Swift has no `shlex` equivalent in the standard library or Foundation, so `CurlLexer` is written by hand. It is the riskiest pure code in the app, which is why M2 is second |
