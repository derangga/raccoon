# Open empirical questions

Part of the [Raccoon design graph](../DESIGN.md).

Claims the design leans on that nobody has measured. Each one gets answered by a test
against a local server that echoes the raw request bytes, and the answer moves to
[environment-facts.md](./environment-facts.md) with what was measured. Numbers stay as they
were, because other files cite them; Q1 to Q5 are answered there.

**Q6. Does URLSession send a body on GET?** curl does with `-X GET -d …`, and some APIs
(Elasticsearch) need it. If URLSession drops it, Curl Import must warn on GET with a body.

**Q7. How slow is `NSTextView` with a 5 MB pretty-printed JSON and per-token colours?** The 5
MB threshold for Pretty (sending.md) is a guess. Measure open, scroll and Tab-switch
times at 1, 5 and 20 MB, and move the threshold to wherever it stops feeling instant.

**Q8. What does a 500 MB response do to memory?** The body is read whole (cardinality.md).
If that is unacceptable, the fix is a cap with "Save to file…", which is a design change
and comes back to the user before it is built.
