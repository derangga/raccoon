# §2 A — Examples

Saved replies that belong to a Request: a name, a status, headers, a body and a delay. Made
from a Response or from scratch, listed under their Request in the sidebar, edited in a Tab
of their own, and served by the Mock Server (mock-server.md). Decided 2026-11-12.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

## Where they live

An optional `examples` array in the Request file, beside the definition, never inside it
(boundary.md). `Request` gains `examples: [Example]`; `RequestDefinition` does not. So:

- a Request Tab never holds Examples. Its Dirty, Undo, Session and Changed on Disk are about
  the definition only, as before;
- every write of a Request file is a **read-modify-write**: the file on disk is read and
  decoded, the one part being saved is replaced, and the rest is kept as the disk had it.
  A Request Tab's ⌘S keeps the file's Examples; an Example's ⌘S keeps the file's definition
  and its other Examples;
- a file with no Examples omits the key and stays byte-identical.

```
Example               id ExampleID, name, status Int (100...599), headers [Row],
                      body ExampleBody, delayMilliseconds Int (0...60000, 0 by default)
ExampleBody           .text(String) · .bytes(Data)
```

## Save as Example

```
-> saveAsExample(tab)                            the Body toolbar's "Save as Example" button,
                                                 and Response ▸ Save as Example (⌥⌘E). Enabled
                                                 on a Request Tab with .received(Response);
                                                 disabled on a Draft, which has no file
  -> Example.from(response, id: ExampleID())     pure        R: none   E: none, total
     -> name = "<status> <reason>"               "200 OK"; HTTPURLResponse's reason phrase
     -> status = response.status
     -> headers = response.headers minus Content-Encoding, Content-Length,
        Transfer-Encoding and Connection     the body was decoded by URLSession and the
                                                 Mock Server frames its own reply, so those
                                                 four would lie (mock-server.md)
     -> body = .text when the bytes are UTF-8, else .bytes
     -> only the final Response: its Redirects are not kept
  -> window.addExample(example, to: requestID)
     -> index path, DataFolderStore.read, RequestFile.decode
                                                 E: unreadable or undecodable -> escape: the
                                                 Body toolbar's note "Couldn't save the
                                                 Example: <reason>." Nothing written
     -> request.examples.append(example)
     -> RequestFile.encode, DataFolderStore.write    E: unwritable -> escape: the same note
     -> WriteLedger.record(path, hash)           our own write
     -> the index's TreeNode gains the Example   the Request row shows a disclosure triangle,
                                                 expanded, the new row selected
  -> the Request Tab is not touched              a Dirty Tab stays Dirty, its edits intact
```

## New Example, Rename, Duplicate, Delete

```
-> New Example                                   a Request row's menu
  -> Example(name: "New Example", status: 200, headers: [], body: .text(""))
  -> window.addExample, then openExample         as above
-> Rename…                                       an Example row's menu; the shared name sheet
  -> window.updateExample(requestID, id) { $0.name = name }
                                                 read-modify-write. A name may repeat: the
                                                 ExampleID is the identity
-> Duplicate                                     an Example row's menu: a copy with a new id and
                                                 " 2" on the name, inserted after it
-> Delete…                                       an Example row's menu, and ⌫ on the row
  -> confirm "Delete the Example “<name>”?"      an Example has no file of its own, so there
                                                 is no Trash to undo it; Cancel is the default
  -> window.removeExample(requestID, id)         read-modify-write
  -> an open Example Tab for it                  becomes "Deleted on disk", as below
```

## Open and edit an Example

```
-> openExample(requestID, exampleID)             click or Return on an Example row
  -> window.tab(showing: .example(requestID, exampleID))?  found -> select it, end
  -> read and decode the Request file            E: as openRequest (collections.md)
  -> Tab(source: .example(requestID, exampleID), content: .example(example),
         baseline: .example(example))            inserted after the selected Tab, selected
-> edit name, status, delay, a header, the body  TabModel.edit, one undo step per edit,
                                                 Dirty when content differs from baseline
-> ⌘S on an Example Tab
  -> window.updateExample(requestID, id) { $0 = tab's example }
                                                 read-modify-write; the Request Tab, if open,
                                                 is untouched
                                                 E: the Request file is gone -> escape: stays
                                                 Dirty, "Not saved. Its Request was deleted."
                                                 E: the Example is gone from the file ->
                                                 appended again with the same id
  -> baseline = content
```

**An Example Tab is a Tab.** CONTEXT.md's Tab is "an open editor for exactly one Request,
Draft or Example". One Tab per Example, as one Tab per Request. Close asks about unsaved
changes, Force Close does not, and the Session restores it. It has no URL bar, no Send and no
Response viewer: the editor is the Example Pane (design-system.md §6). Its Breadcrumb is the
Request's, then the Example's name.

**A binary body is shown, not edited.** `.bytes` draws as the Hex view, read-only, with
"Replace from File…" and "Save Body…" buttons; `.text` is a text editor coloured by the
Example's own `Content-Type` header (JSON, XML, else plain). "Replace from File…" reads the
file through FileReading and sets `.text` or `.bytes` by the same UTF-8 rule.

## Changes on disk

```
-> filesChanged(paths)                           collections.md, one more step
  -> the index's TreeNodes carry each Request's Examples (id, name, status)
  -> for each open Example Tab whose Request file changed
    -> the Request or the Example is gone        banner "Deleted on disk"; ⌘S appends it
                                                 again while the Request exists
    -> the Example differs, the Tab not Dirty    content = baseline = disk, silently
    -> the Example differs, the Tab Dirty        banner Reload · Keep Mine, as for a Request
```

A Request Tab compares the file's **definition** with its baseline, as before, so a change to
the file's Examples alone never raises Changed on Disk on the Request's Tab.

## Postman

```
-> Postman Import: an item's `response` array    postman.md
  -> each entry -> Example                       name, `code` as status (a missing or
                                                 out-of-range code is 200), `header` rows,
                                                 `body` as .text; `originalRequest`,
                                                 `_postman_previewlanguage`, `cookie` and
                                                 `responseTime` dropped, without a note: none
                                                 of them is served
  -> .examplesDropped is no longer a note kind
-> Postman Export                                postman-export.md
  -> each Example -> a `response` entry          `name`, `code`, `status` (the reason phrase
                                                 for the code), `header`, `body` (.text as is,
                                                 .bytes as base64 text, counted in the
                                                 sheet's summary as "binary Example bodies
                                                 written as base64"), no `originalRequest`
```
