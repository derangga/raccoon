# §2 A — Sending

Send a Tab's request, cancel it, and show what came back. Milestone M1.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

```
-> send(tab)                                     ⌘↩ or the Send button
  -> VariableScope(active, globals)              pure        R: none
  -> VariableResolver.resolve(definition, scope) pure        E: ResolveError.undefined
                                                             -> escape, nothing is sent
  -> tab.response = .sending(now)                            R: Clock
  -> MultipartFiles.read(parts)                  boundary    R: FileReading
                                                             E: fileMissing -> escape
  -> HTTPTransport.send(resolved)                boundary    R: HTTPTransport
                                                             E: SendError -> escape
                                                             never retried, see §4
  -> tab.response = .received(response)
```

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

**Headers are shown in wire order with duplicates kept.** Two `Set-Cookie` headers are two
rows. `HTTPURLResponse.allHeaderFields` merges and reorders them, which is an open question
(`open-questions.md` Q4) before this view can claim it.
