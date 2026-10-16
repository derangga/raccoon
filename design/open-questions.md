# Open empirical questions

Part of the [Raccoon design graph](../DESIGN.md).

Claims the design leans on that nobody has measured. Each one gets answered by a test
against a local server that echoes the raw request bytes, and the answer moves to
[environment-facts.md](./environment-facts.md) with what was measured.

1. **Which headers does URLSession add on its own?** It is believed to add `User-Agent`,
   `Accept`, `Accept-Language` and `Accept-Encoding: gzip, deflate, br` when the request
   does not set them. If so, the request on the wire is not the one in the table, which
   breaks "what you see is what Raccoon sends". Answers decide whether those headers are
   shown as greyed-out automatic rows, or overridden to match curl.

2. **Does `--compressed` mean anything under URLSession?** If URLSession always sends
   `Accept-Encoding` and always decompresses, `requestsCompression` is a setting that
   changes nothing. Then it is dropped from Request Settings, and Curl Import ignores the
   flag with a note, which also changes CONTEXT.md.

3. **Is a manual `Cookie` header sent when `httpShouldSetCookies` is false and there is no
   cookie storage?** Request Cookies depend on it. URLSession has reserved headers it
   documents as ignored, and `Cookie` is not in that list, but that is a reading, not a
   measurement.

4. **Can a Response keep duplicate headers in wire order?** `HTTPURLResponse.allHeaderFields`
   is a dictionary, so two `Set-Cookie` headers may arrive merged with a comma. macOS 12+
   has `value(forHTTPHeaderField:)` but no ordered list. If there is no API for it, the
   Headers view says "merged by the system" rather than claiming to be raw.

5. **Does cancelling the `Task` around `data(for:delegate:)` cancel the URLSessionTask
   immediately?** §8 depends on it. Measure: a server that delays 10 s, cancel at 1 s,
   check the server saw the connection close at about 1 s.

6. **Does URLSession send a body on GET?** curl does with `-X GET -d …`, and some APIs
   (Elasticsearch) need it. If URLSession drops it, Curl Import must warn on GET with a body.

7. **How slow is `NSTextView` with a 5 MB pretty-printed JSON and per-token colours?** The 5
   MB threshold for Pretty (sending.md) is a guess. Measure open, scroll and Tab-switch
   times at 1, 5 and 20 MB, and move the threshold to wherever it stops feeling instant.

8. **What does a 500 MB response do to memory?** The body is read whole (cardinality.md).
   If that is unacceptable, the fix is a cap with "Save to file…", which is a design change
   and comes back to the user before it is built.
