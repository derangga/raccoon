# §2 A — Curl

Curl Import from the URL bar, and Copy as Curl. Milestone M2.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

## Curl Import

```
-> pasteIntoURLBar(text, tab)
  -> CurlDetector.isCurl(text)                   pure: first word is `curl` after trimming
                                                 no -> an ordinary paste, this tree ends
  -> CurlImporter.import(text)                   pure        R: none
                                                 E: CurlImportError -> escape, Tab unchanged
    -> CurlLexer.commands(text)                  join `\`+newline (and `\`+spaces+newline,
                                                 and CRLF), split on unquoted `;` and newline
                                                 -> keep the first command that starts `curl`
    -> CurlLexer.tokens(command)                 POSIX shell words: '…', "…", $'…', \x
                                                 E: unterminatedQuote
    -> CurlLexer.expandShortFlags(tokens)        -fsSL is four flags, -XPOST is -X POST,
                                                 -H'a: b' is -H 'a: b'
    -> CurlFlags.collect(tokens)                 -> [flag: [value]] + positionals
                                                 unknown flags -> ignoredFlags, with their
                                                 value consumed if the table says they take one
    -> CurlMapping.definition(flags, positionals)
      -> url        --url, else first positional                E: noURL
      -> params     the URL's `?` part, then --url-query, then -d values when -G
      -> headers    -H / --header, in order; `Name;` is an empty header
      -> cookies    -b / --cookie `a=1; b=2` split into rows, plus any `Cookie:` header
                    split into rows and removed from headers
      -> auth       Authorization: Bearer x -> .bearer, header removed
                    Authorization: Basic b64 -> .basic if it decodes to `user:pass`,
                    else the header stays a header
                    -u user:pass -> .basic, unless an Authorization header won
      -> body       see the body table below
      -> method     -X / --request, else POST if there is a body, else GET
      -> settings   -k / --insecure, -L / --location, --compressed
  -> PasteTarget.for(tab)                        pure
     .currentTab   tab is a Draft, its definition equals the empty Draft, no Response
     .newDraftTab  anything else
  -> CurlImport.fileReferences non-empty?
    -> FileReading.read(path) for each           boundary    R: FileReading
                                                 E: unreadable -> escape per file, see §4
  -> apply to the target Tab                     one undo step on the current Tab
  -> ignoredFlags non-empty?
    -> a note under the URL bar: "Ignored: --retry, -s"
```

### The body table

The first matching row wins. `Content-Type` here means the header from `-H` after Auth and
Cookie extraction.

| curl | Body |
|---|---|
| `-F name=value`, `-F name=@path` | `.multipart`, a text or file Part per `-F` |
| `--data-raw` whose `Content-Type` is `multipart/form-data; boundary=…` | `.multipart`, parsed from the raw body (what Chrome's Copy as cURL produces) |
| `-d` / `--data` / `--data-urlencode` with no `Content-Type`, or `application/x-www-form-urlencoded` | `.formURLEncoded`, split at `&` then the first `=`, each value percent-decoded |
| `-d` / `--data-raw` / `--data-binary` with `Content-Type` json, xml or text | `.raw(kind, text)`, joined with `&` when there are several |
| `--data-binary @path` | `.raw(.text, contents)` when the file is UTF-8, else §4 |
| any other data | `.raw(.text, text)` |
| no data | `.none` |

`-G` moves every data value into `params` instead, and the body stays `.none`.

### Rules carried over from Yaak's importer

Yaak's importer (`yaak/plugins/importer-curl/src/index.ts`, MIT) records bugs it has already
fixed. Each one is a test case for `CurlImporter` from day one, ported from its 51 tests and
Bruno's 53 (`environment-facts.md`):

- `--data-urlencode` is one value. An `&` inside it is data, not a separator.
- A value with a stray `%` (`a=100%`) is not an error. Decode each valid `%XX` run and keep
  the rest.
- Only the first `=` splits a name from a value: `token=abc==` keeps its padding.
- Data that starts with dashes (`------WebKitFormBoundary`) is a value, not a flag.
- `$'…'` strings with `\'` and `\n` escapes, and a `\;` outside quotes, do not split commands.

### Where this differs from Yaak, deliberately

- **Cookies become Request Cookies rows, not one `Cookie` header.** Raccoon has a Cookies
  table (CONTEXT, Request Cookies), and a cookie a user wants to disable is one row.
- **Several pasted commands import only the first.** Yaak makes one request per command.
  A paste lands in one Tab, so the rest are listed in the ignored note as "2 more commands".
- **`--digest` is ignored, not mapped.** Auth has no Digest (CONTEXT, Auth). The `-u` value
  still becomes `.basic`, and the note says `--digest` was ignored so the user knows the
  scheme changed.
- **No GraphQL detection.** GraphQL is not a Body Type in v1, so a GraphQL body imports as
  `.raw(.json)`, which is what it is on the wire.

## Copy as Curl

```
-> copyAsCurl(tab or request, includeSecrets)   the context menu
  -> VariableResolver.resolve(definition, scope, secrets: includeSecrets)
                                                 pure        E: undefined -> escape, the
                                                 menu item says which Variable is missing
                                                 secrets off -> a Secret Variable stays
                                                 as {{name}} in the output
  -> CurlRenderer.render(resolved)               pure
     -> one flag per line, joined with ` \` + newline
     -> every value single-quoted, `'` written as `'\''`
     -> Auth rendered as -u or -H 'Authorization: Bearer …', cookies as -b
     -> settings as -k, -L, --compressed
  -> NSPasteboard.setString                      boundary    R: ClipboardWriter
```

**The round trip is the test.** `CurlImporter.import(CurlRenderer.render(r))` must give back
`r` for every fixture that holds no Variables, which is one property test that covers both
directions.

## The Curl pane

The inspector's Curl pane is Copy as Curl rendered live for the selected Tab.

```
-> curlPreview(tab)                              on every edit to the Tab, on Tab switch,
                                                 on pickActiveEnvironment
  -> VariableResolver.resolve(definition, scope, secrets: false)
                                                 pure        E: undefined -> escape: the pane
                                                 says which Variables are missing, Copy is
                                                 disabled
  -> CurlRenderer.render(resolved)               pure, the same renderer as Copy as Curl
-> copy(includeSecrets)                          the pane's Copy button
  -> copyAsCurl(tab, includeSecrets)             the tree above, unchanged
```

**The preview never holds a secret.** It always resolves with `secrets: false`, so a Secret
Variable stays `{{name}}` on screen and the Keychain is not read on every keystroke
(cardinality.md: secrets are read at send, at Copy as Curl and at hover). "Include secrets"
changes only what Copy puts on the pasteboard.
