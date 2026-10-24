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
    -> CurlLexer.commands(text)                  one pass: POSIX shell words ('…', "…", $'…',
                                                 \x), `\`+newline joined (and `\`+spaces+newline,
                                                 and CRLF), split on unquoted `;` and newline
                                                 -> the words of the first command that starts
                                                 `curl`, and how many other curl commands
                                                 E: unterminatedQuote(position in the pasted text)
    -> CurlLexer.expandShortFlags(tokens)        -fsSL is four flags, -XPOST is -X POST,
                                                 -H'a: b' is -H 'a: b'; a word that is a flag's
                                                 value is never expanded (-d '-abc')
    -> CurlFlags.collect(tokens)                 -> [flag: [value]] + positionals
                                                 unknown flags -> ignoredFlags, with their
                                                 value consumed if the table says they take one
    -> CurlMapping.definition(flags, positionals)
      -> url        --url, else first positional; with no `://`, `http://` is
                    prefixed, as curl does                     E: noURL
      -> params     the URL's `?` part, then --url-query, then -d values when -G
      -> headers    -H / --header, and -A / --user-agent as `User-Agent`, in order;
                    `Name;` is an empty header. --json adds `Content-Type` and
                    `Accept: application/json` after them unless -H set either
      -> cookies    -b / --cookie `a=1; b=2` split into rows, plus any `Cookie:` header
                    (a part with no `=`, like `secure`, is not a cookie and is dropped)
                    split into rows and removed from headers; a -b value with no `=` is
                    a cookie file curl would read, so --cookie goes to ignoredFlags
      -> auth       Authorization: Bearer x -> .bearer, header removed
                    Authorization: Basic b64 -> .basic if it decodes to `user:pass`,
                    else the header stays a header
                    -u user:pass -> .basic, unless an Authorization header won
      -> body       see the body table below
      -> method     -X / --request, else HEAD with -I / --head, else POST if there
                    is a body, else GET
      -> settings   -k / --insecure, -L / --location
  -> PasteTarget.for(tab)                        pure
     .currentTab   tab is a Draft, its definition equals the empty Draft, no Response
     .newDraftTab  anything else
  -> CurlImport.fileReferences non-empty?
    -> FileReading.read(path) for each           boundary    R: FileReading
                                                 E: unreadable -> escape per file, see §4
  -> method is GET and the body is not .none?   pure, after the reads
    -> a note: "A GET with a body won't send: macOS refuses it. Change the method or
       remove the body." (URLSession fails the send, environment-facts.md Q6)
  -> apply to the target Tab                     one undo step on the current Tab
  -> ignoredFlags non-empty?
    -> a note under the URL bar: "Ignored: --retry, -s"
```

### The body table

The first matching row wins. `Content-Type` here means the header from `-H` after Auth and
Cookie extraction.

| curl | Body |
|---|---|
| `-F name=value`, `-F name=@path` | `.multipart`, a text or file Part per `-F`; a `;type=…` after the path is dropped |
| `--data-raw` whose `Content-Type` is `multipart/form-data; boundary=…` | `.multipart`, parsed from the raw body (what Chrome's Copy as cURL produces) |
| `-d` / `--data` / `--data-ascii` / `--data-binary` / `--json` `@path` | `.raw(kind, contents)`, the kind from a json, xml or text `Content-Type`, else `.text`, when the file is UTF-8, else §4. `--data-raw @x` is the text `@x`, as in curl |
| `-d` / `--data` / `--data-urlencode` with no `Content-Type`, or `application/x-www-form-urlencoded` | `.formURLEncoded`, split at `&` then the first `=`, each value percent-decoded |
| `-d` / `--data-raw` / `--data-binary` / `--json` with `Content-Type` json, xml or text | `.raw(kind, text)`, joined with `&` when there are several |
| any other data | `.raw(.text, text)` |
| no data | `.none` |

`--data-raw` and `--data-binary` with no `Content-Type` are raw text, not form rows: they
mean "send these bytes", and raw text keeps them exact. The wire is the same either way,
because URLSession adds `application/x-www-form-urlencoded` to a body with no `Content-Type`
(environment-facts.md).

`--json` is `--data-binary` plus its two headers (above), so it lands on the json row, or
the `@path` row for `--json @file`.

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

Splitting commands and splitting words is one pass, not two. Two passes track quotes twice,
and every place they disagree is a command split inside a quote.

### Where this differs from Yaak, deliberately

- **Cookies become Request Cookies rows, not one `Cookie` header.** Raccoon has a Cookies
  table (CONTEXT, Request Cookies), and a cookie a user wants to disable is one row.
- **Several pasted commands import only the first.** Yaak makes one request per command.
  A paste lands in one Tab, so the rest are listed in the ignored note as "2 more commands".
- **`--digest` and `--ntlm` are ignored, not mapped.** Auth has no Digest or NTLM (CONTEXT,
  Auth). The `-u` value still becomes `.basic`, and the note says the flag was ignored so the
  user knows the scheme changed.
- **`--compressed` is ignored.** URLSession always asks for gzip and decodes it
  (environment-facts.md), so there is no setting to turn on and the note lists it.
- **No Content-Type row is added.** Yaak adds one for `-d` and `-F`. Raccoon keeps only the
  headers the command has; with none, the Headers table shows the `Content-Type` URLSession
  adds as an automatic row (AutomaticHeaders), which is what curl sends too.
- **Headers keep command order across `-H` and `--header`.** Yaak lists `--header` first.
- **`-L` sets Follow redirects and `-k` Allow insecure TLS.** Yaak ignores both.
- **No GraphQL detection.** GraphQL is not a Body Type in v1, so a GraphQL body imports as
  `.raw(.json)`, which is what it is on the wire.

## Copy as Curl

```
-> copyAsCurl(tab or request, includeSecrets)   the context menu; until the Tab strip exists,
                                                 Edit ▸ Copy as Curl (⇧⌘C) and the URL bar's
                                                 menu, both on the selected Tab
                                                 E: invalidURL -> the item is disabled
  -> VariableResolver.resolve(definition, scope, secrets: includeSecrets)
                                                 pure        E: undefined -> escape, the
                                                 menu item says which Variable is missing
                                                 secrets off -> a Secret Variable stays
                                                 as {{name}} in the output: the scope maps
                                                 it to its own `{{name}}`, which the
                                                 one-pass resolver leaves as written
  -> CurlRenderer.render(resolved)               pure
     -> the first line is `curl`, `-X METHOD` unless it is a GET with no body, and
        the URL (board 11)
     -> then one flag per line, joined with ` \` + newline + two spaces
     -> every value single-quoted, `'` written as `'\''`; the method only when it
        is not all letters
     -> Auth is already an Authorization header (variables.md), rendered as -H, and
        an empty header as -H 'Name;'; cookies as one -b
     -> body: raw as --data-raw, form-urlencoded as --data-urlencode per row (curl
        encodes the value as the transport does), multipart as -F name=value or
        -F name=@path
     -> settings as -k, -L
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
