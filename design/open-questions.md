# Open empirical questions

Part of the [Raccoon design graph](../DESIGN.md).

Claims the design leans on that nobody has measured. Each one gets answered by a test
against a local server that echoes the raw request bytes, and the answer moves to
[environment-facts.md](./environment-facts.md) with what was measured. Numbers stay as they
were, because other files cite them; Q1 to Q5, Q7 and Q8 are answered there.

**Q6. Does URLSession send a body on GET?** curl does with `-X GET -d …`, and some APIs
(Elasticsearch) need it. If URLSession drops it, Curl Import must warn on GET with a body.
