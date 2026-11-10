# Open empirical questions

Part of the [Raccoon design graph](../DESIGN.md).

Claims the design leans on that nobody has measured. Each one gets answered by a test
against a local server that echoes the raw request bytes, and the answer moves to
[environment-facts.md](./environment-facts.md) with what was measured. Numbers stay as they
were, because other files cite them; Q1 to Q12 and Q14 are answered there. Q9 to
Q12 are when the metrics arrive, how many transactions a redirect chain gives, what Wire
Size counts, and what a reused connection leaves out.

Open:

- **Q13.** On an uncompressed `Transfer-Encoding: chunked` reply, does
  `countOfResponseBodyBytesReceived` count the chunk framing? If it does, the Timeline shows
  "on the wire" for a body that was not compressed, and the "differs" rule needs the
  `Content-Encoding` header too.
