# §2 A — Sending

Send a Tab's request, cancel it, and show what came back. Milestone M1.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

```
-> send(tab)                                     ⌘↩ or the Send button
  -> VariableScope(active, globals)              pure        R: none
  -> VariableResolver.resolve(definition, scope) pure        E: undefined -> escape: the
                                                             message line names them; the
                                                             last Response stays (board 04)
                                                             E: invalidURL -> escape:
                                                             .notSent, nothing is sent
  -> tab.response = .sending(now)                            R: InstantSource
  -> HTTPTransport.send(resolved)                boundary    R: HTTPTransport
    -> read every multipart file part            boundary    R: FileReading, given to
                                                             the transport's init
                                                             E: fileMissing -> escape,
                                                             before any byte goes out
    -> URLSession data(for:delegate:)                        E: SendError -> escape
                                                             never retried, see §4
  -> tab.response = .received(response)
```

**Path Variables are substituted inside `VariableResolver.resolve`, once, before the URL is
built.** The same tree runs for Copy as Curl and the Curl pane, so they show what is sent.

```
-> VariableResolver.resolve(definition, scope)   pure        the part that reads the URL
  -> PathVariables.tokens(in: definition.url)    pure        R: none: the typed text, so the
                                                 table and the send read the same tokens
  -> for each token, in text order
    -> value = definition.pathVariables[name]    none -> `:name` stays as typed
    -> substitute {{name}} in value              pure        one pass, as everywhere
                                                 E: undefined -> collected with the rest, so one
                                                 send names every missing Variable. The use is
                                                 "Params" (variables.md)
    -> resolved value == "" -> `:name` stays as typed
                                                 no block and no message: what was typed is
                                                 what is sent, as curl sends it
    -> else PathEncoding.segment(resolved value) pure        R: none
  -> the URL text = the typed text, each `{{name}}` substituted and each token replaced, one
     left-to-right pass                          a value's own text is never read again for
                                                 `{{` or `:name`
  -> URLComponents + percent-encoded params      E: invalidURL (unchanged)
```

**A Path Variable value is encoded the way Postman encodes it, so a pasted Postman request
sends the same bytes.** `PathEncoding.segment` percent-encodes the UTF-8 of every character
`CharacterSet.urlPathAllowed` does not allow (space, `"`, `<`, `>`, `?`, `#`, `{`, `}`, `[`,
`]`, `|`, `\`, `^`, backtick, controls, anything not ASCII), with two exceptions:

- **`/` is not encoded.** A value `a/b` is two segments, as in Postman. Postman's own encoder
  leaves `/` alone and inserts the value before encoding; Bruno's send does the same; Yaak
  alone writes `%2F` (environment-facts.md). The three disagree, and the design follows
  Postman. A user who wants one segment types `%2F` in the value.
- **A `%` that starts `%XX` is kept.** `a%2Fb` is sent as `a%2Fb`, which is how that
  workaround reaches the wire. Any other `%` becomes `%25`. Postman's handling of `%` was not
  seen, so this half is inferred from the `%2F` workaround; Bruno's send decodes then re-encodes
  a segment, so it agrees on that case.

`?` and `#` are encoded, so a value cannot start a query or a fragment. `:`, `@`, `,`, `;`,
`=`, `&` and `+` stay as typed: a path holds them.

A Secret Variable that Copy as Curl leaves as `{{name}}` (secrets off, variables.md) is written
as `{{name}}`, not as `%7B%7Bname%7D%7D`: the scope maps it to itself, and the encoder skips a
piece the scope put back.

**Every header sent is on screen, in Headers or as the Auth.** The one exception to "in
Headers" is the `Authorization` header Auth builds: it is no row, and the Auth pane's paragraph
says it is sent. URLSession adds `Host`, `Accept`, `Accept-Language`,
`Accept-Encoding`, `Connection` and `User-Agent`, and a `Content-Type` on any body without one
(environment-facts.md). None can be removed, only replaced, so the Headers table shows them as
automatic rows (`AutomaticHeaders.rows(resolved)`), and a row the user types with the same name
replaces one. The two whose system values cannot be known ahead, `User-Agent` and
`Accept-Language`, are set by the transport to `Raccoon/<version>` and `*`, so every automatic
row is exact before the send. `Content-Length` reads "calculated when sent", and multipart's
boundary is appended at send as editing.md says.

**Resolution runs before `.sending`.** A request with an Undefined Variable never shows a
spinner, because it was never going to be sent. The red highlight is already on screen
(`variables.md`), and the send only adds the message naming what is missing.

**An enabled Headers row named `Authorization` wins over Auth.** `VariableResolver` appends
one `Authorization` row for Basic or Bearer after the enabled rows
(`VariableResolver.swift:40`), and the transport adds every header with `URLRequest.addValue`
(`URLSessionTransport.swift:69-71`), which would join a repeated name into one value with `,`
(measured: `Bearer one` then `Basic two` is one header `Bearer one,Basic two`). So the resolver
does not append Auth's row when an enabled Headers row has the name `Authorization`, compared
case-insensitively, even when that row's value is empty. A Disabled Row never counts, so it
neither wins nor blocks Auth. The guard is in the resolver, where the row is appended, so Copy
as Curl and the Curl pane follow it with no change of their own: they go through the same
resolve. Curl Import moves an `Authorization` header into Auth and removes the row (curl.md),
and a Postman Request with both imports both (postman.md), so the clash only comes from a
row the user types or imports. The Auth pane says so instead of hiding it:

```
-> VariableResolver.resolve(definition, scope)   pure        the Auth step, after the enabled rows
  -> Auth .basic / .bearer, and no enabled row   append the Authorization row
     in headers named `Authorization`
     (case-insensitive, any value, empty too)
  -> Auth .none, or such a row is present        nothing appended: the Headers row is what is sent
```

```
-> showAuthPane(tab)                             when Auth is shown, and on an Auth or Headers edit
  -> AuthNote.text(auth, headers)                pure        R: none
     .none                                       "No Authorization header is added."
     .basic / .bearer                            the scheme's sentence, plus " An enabled
                                                 Authorization row in Headers is sent
                                                 instead." when the same test as the
                                                 resolver's finds such a row
```

**Files are read at send time, not at import or edit time.** A multipart part holds a path,
and a file that changed since it was picked is sent as it is now, which is what curl does.

```
-> cancel(tab)                                   the Send button while sending, or ⌘.
  -> the send's Task is cancelled                §8 owns the task
  -> tab.response = .idle                        not .failed: nothing went wrong
```

```
-> showResponse(response)                        when .received lands, and on Tab switch
  -> StatusLine(status, elapsed, byteCount)      pure
  -> ResponseBody.presentation(response)         pure
     .pretty(text, .json | .xml)                 byteCount ≤ 5 MB and it parses
     .raw(text)                                  > 5 MB, or not JSON/XML, or did not parse
     .binary(byteCount)                          not valid UTF-8
  -> Highlighter.ranges(text, kind)              pure, only for .pretty      R: none
  -> Theme colours applied to the ranges         R: ThemeChoice (theme.md)
```

**5 MB is measured, and so is the text engine.** The body views are `NSTextView`s on TextKit 1
with non-contiguous layout. On the default TextKit 2, scrolling to the end of a 20 MB body
takes 19 s plain and 36 s coloured; on TextKit 1 every step at 5 MB coloured stays at or under
129 ms, and 20 MB stays under 0.5 s coloured and 130 ms plain, so Raw above the threshold
stays usable (environment-facts.md).

**Pretty is decided by parsing the body, not by trusting `Content-Type`.** Servers send JSON
as `text/plain` and HTML as `application/json`. The header is a hint for which parser to try
first, and a parse failure is `.raw`, never an error.

**Headers cannot be shown in wire order.** Two `Set-Cookie` headers reach Raccoon as one value
joined with `, `, and `HTTPURLResponse` offers only a dictionary, so the order is gone too
(measured, `environment-facts.md`). The Headers view sorts them by name and says the system
merged them rather than claiming to be raw.
