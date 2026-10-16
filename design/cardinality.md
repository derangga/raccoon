# §3 Cardinality

Part of the [Raccoon design graph](../DESIGN.md).

```
Stream:   FolderWatch events     for the app's lifetime, or until the Data Folder changes.
                                 Coalesced (§7), filtered by the WriteLedger, ended by §8
          appearance changes     for the app's lifetime. KVO, no state of its own

Effect:   send · Curl Import · Copy as Curl · read or write one file · Keychain get/set ·
          Session write · Data Folder scan

Bounded:  VariableScope          valid for one send or one highlight pass. Rebuilt every
                                 time, never cached: it is a merge of two short lists, and a
                                 cache would need invalidating on every Environment edit,
                                 every Keychain write and every Active Environment switch
          Secret values          read from the Keychain at send, at Copy as Curl and at
                                 hover. Never held in a model, so never in a crash log or
                                 the Session
          Response               valid until the Tab sends again or closes. In memory only
                                 (CONTEXT, Response)
          ResponseBody presentation
                                 computed once per Response, kept with it. Pretty-printing a
                                 4 MB body on every Tab switch would be visible
          DataFolderIndex        valid until the next filesChanged
          highlight ranges       valid for one keystroke
```

**A send is one value, not a stream.** v1 reads the whole body and then shows it. Streaming
bodies (SSE, chunked progress) are a Stream on this graph when they arrive, and they are
outside the design session's scope. Reading whole costs about twice the body at peak
(environment-facts.md), accepted for v1: no size cap and no "Save to file…".

**The Session write is an Effect wrapped by §7.** Each change schedules it; the coalescing
is what turns "every keystroke" into "at most once a second".
