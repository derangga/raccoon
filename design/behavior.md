# §7 Behavior — wraps without changing the graph

Part of the [Raccoon design graph](../DESIGN.md).

```
one-at-a-time    ⟳ send                      // per Tab. While sending, Send becomes
                                             //   Cancel; a second send cannot start, so
                                             //   no response can land on the wrong click
timeout 60s      ⟳ send                      // URLSessionConfiguration.timeoutIntervalForRequest.
                                             //   Fixed in v1, not a Request Setting
slow-only 150ms  ⟳ send                      // the spinner appears only after 150 ms, so a
                                             //   fast local API does not flash
coalesce 1s      ⟳ SessionWriter.schedule    // at most one session.json write a second,
                                             //   plus writeNow on quit
coalesce 300ms   ⟳ FolderWatch               // FSEvents latency; a git checkout of 200
                                             //   files is one filesChanged, not 200.
                                             //   FSEvents delivers a window in chunks of
                                             //   32 paths within ~1 ms; a 50 ms tail joins
                                             //   them into that one batch
ledger           ⟳ filesChanged              // WriteLedger: path + SHA-256 of the bytes
                                             //   Raccoon wrote. An event whose file still
                                             //   hashes to that is ours and is dropped.
                                             //   Comparing hashes, not timestamps, so a
                                             //   git checkout that restores identical
                                             //   bytes is also correctly a no-op
off-main         ⟳ ResponseBody.presentation // pretty-print and highlight on a background
                                             //   task; the Raw view shows first
undo grouping    ⟳ Curl Import               // one paste is one undo step on the
                                             //   current Tab, whatever it changed
```

**No retry wrapper exists anywhere.** §4 explains why a send is never retried; the folder
watch and the Keychain have no transient failures worth retrying, because a second attempt
a millisecond later sees the same disk and the same Keychain.

**No debounce on highlighting.** `VariableTokens.ranges` is a linear scan of one field, and
a debounce would show a red underline for 200 ms after the user finished typing a defined
name. If profiling a large body proves otherwise, the debounce goes here and the tree in
`variables.md` does not change.
