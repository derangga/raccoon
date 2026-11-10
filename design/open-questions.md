# Open empirical questions

Part of the [Raccoon design graph](../DESIGN.md).

Claims the design leans on that nobody has measured. Each one gets answered by a test
against a local server that echoes the raw request bytes, and the answer moves to
[environment-facts.md](./environment-facts.md) with what was measured. Numbers stay as they
were, because other files cite them; Q1 to Q8 are answered there.

Open, for Redirects and Timing (sending.md, "Redirects and Timing"):

- **Q9.** Does the per-task delegate's `urlSession(_:task:didFinishCollecting:)` run before
  `data(for:delegate:)` returns? It decides whether the transport has to wait for it.
- **Q10.** After N followed redirects, does `transactionMetrics` hold N + 1 entries, in send
  order, each with its `response`?
- **Q11.** On a gzip body, is `countOfResponseBodyBytesReceived` the encoded count, smaller
  than the body URLSession hands back?
- **Q12.** On a second send over a kept-alive connection, are the `domainLookup*`, `connect*`
  and `secureConnection*` marks nil, with `isReusedConnection` true?
