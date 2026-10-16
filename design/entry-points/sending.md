# §2 A — Sending

Send a Tab's request, cancel it, and show what came back. Milestone M1.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

```
-> send(tab)                                     ⌘↩ or the Send button
  -> VariableScope(active, globals)              pure        R: none
  -> VariableResolver.resolve(definition, scope) pure        E: ResolveError -> escape:
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

**Every header sent is on screen.** URLSession adds `Host`, `Accept`, `Accept-Language`,
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

**Pretty is decided by parsing the body, not by trusting `Content-Type`.** Servers send JSON
as `text/plain` and HTML as `application/json`. The header is a hint for which parser to try
first, and a parse failure is `.raw`, never an error.

**Headers cannot be shown in wire order.** Two `Set-Cookie` headers reach Raccoon as one value
joined with `, `, and `HTTPURLResponse` offers only a dictionary, so the order is gone too
(measured, `environment-facts.md`). The Headers view says the system merged them rather than
claiming to be raw.
