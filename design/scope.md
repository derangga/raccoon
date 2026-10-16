# §8 Scope

Part of the [Raccoon design graph](../DESIGN.md).

```
withApp {                        // release: SessionWriter.writeNow, then everything below
  withDataFolder(root) {         // release: FolderWatch stream ends, the FSEventStream is
                                 //   stopped and invalidated. Changing the Data Folder in
                                 //   Settings releases this scope and opens a new one
  }
  withTab(id) {                  // release: cancel the in-flight send
    withSend { … }               // release: URLSessionTask.cancel(). One per Tab at most
  }
}
```

**An in-flight send is a resource the Tab owns, not a flag on it.** `TabModel` holds the
`Task` that runs the send. Close, quit and a second ⌘↩ (refused, §7) all reach the same
`Task`, so "a closed Tab has no send still running" is true because the Tab is the only
thing holding it. URLSession's async `data(for:delegate:)` is documented to cancel its data
task when the calling `Task` is cancelled, so cancelling the `Task` is the whole release:
the connection closes within milliseconds and the send throws `.transport(.cancelled)`
(measured, environment-facts.md).

**One URLSession for the app, a delegate per send.** The Request Settings differ per request,
but `URLSession.data(for:delegate:)` takes a per-task delegate, and that delegate answers the
redirect and the server-trust challenges from that request's settings. One session means no
session lifecycle to scope at all. It is configured once with no cookie storage, no URL cache
and no credential storage, because each of those is state the user cannot see (CONTEXT,
Request Cookies).

**The FSEventStream is scoped to the Data Folder, not the app.** It is the one resource in
Raccoon that leaks if forgotten: a stream left running after the folder changes delivers
events for the old folder into the new index. Tying it to `withDataFolder` makes the change
in Settings a release followed by an acquire.

**Quit writes the Session before releasing Tabs.** The snapshot is taken from the Tabs, so
the order matters in one direction: releasing first would still work (the Session holds no
Responses) but would let a cancelled send flip a Tab's state while the snapshot is read.
