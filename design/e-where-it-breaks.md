# §4 E — where it breaks

Part of the [Raccoon design graph](../DESIGN.md).

Each break is one of three verdicts: `RETRY` (transient, try again), `escape` (recoverable,
return an alternative and tell the user), `DIE` (our own assumption was false: a bug, not a
failure of the world). Raccoon has no `RETRY`, and the first entry says why.

```
send
  ⚠ any SendError        → escape: the Response pane shows the error. NEVER retried.
                           Raccoon cannot know whether a POST that timed out was applied,
                           and an HTTP client that retries a payment request on its own is
                           the one thing the user cannot undo. Send again is one key
  ⚠ cancelled            → not an error: .idle. The user asked for it
  ⚠ timedOut(seconds)    → escape: "No response after <n> s", the Request Timeout the send
                           used: the request's own, or 60 when it has none
  ⚠ tooManyRedirects(n)  → escape: "Too many redirects". The Redirect Limit was reached, so
                           the delegate refused the next one. It cannot throw from inside the
                           delegate: refusing makes data(for:) SUCCEED with the 3xx
                           (environment-facts.md), so the transport records the refusal and
                           throws once the call returns
  ⚠ untrustedCertificate → escape: the message names the host and offers "Allow insecure
                           TLS for this request", which flips the Request Setting. It is
                           never flipped automatically
  ⚠ fileMissing(path)    → escape: the multipart row is marked and the send stops before
                           any byte goes out
  ⚠ transport(code)      → escape: URLError's own description, plus the code and host
resolve
  ⚠ undefined(names)     → escape: every name listed, red underlines already on screen,
                           nothing sent, no spinner
  ⚠ undefined(names) in a Path Variable value
                         → escape: the same path as above, not a new one. The name is listed
                           with the rest, the red wavy underline is already in the Value cell,
                           the Params count is drawn in the undefined colour, and the
                           Variables pane names the use as "Params"
  ⚠ a Path Variable with an empty value → not an error and no message: `:id` is sent as
                           typed, as curl sends it. Nothing blocks, because an empty value
                           is a choice the user can see in the table and the URL
  ⚠ a Path Variable value holding `/`, `?`, `#` or `%` → not an error: `/` adds a segment, as
                           in Postman; `?` and `#` are encoded so a value cannot start a
                           query or a fragment; a `%XX` is kept and a lone `%` is `%25`
                           (sending.md)
  ⚠ invalidURL           → escape: .notSent. The URL bar is outlined, the message quotes
                           the URL after substitution, because that is the one that failed
  ⚠ Keychain unreadable  → becomes undefined for that secret. One path, not two: the user
                           sees "token is not defined" and the Environments sheet shows
                           why
showResponse
  ⚠ body not UTF-8       → not an error: .binary(byteCount)
  ⚠ image/* that does not decode (NSImage nil)
                         → not an error: the same binary state as above
  ⚠ JSON did not parse   → not an error: .raw. A server that says json and sends HTML
                           is the server's fact
  ⚠ body does not nest   → not an error: no Fold Regions, no chevrons
  ⚠ metrics absent, or more transactions than Redirects + 1
                         → escape: every Timing is nil, the Timeline says "Timing was not
                           reported for this send.", the Redirects stay
  ⚠ fewer transactions than Redirects + 1 (URLSession keeps the last 20, environment-facts.md)
                         → not an error: paired from the end, the earliest Redirects have
                           no Timing
  ⚠ a Timing mark missing, or an end before its start (marks are wall-clock Dates)
                         → escape: that phase is nil, never negative. elapsed is
                           ContinuousClock and is not touched
Save Response Body
  ⚠ Content-Disposition name empty, ".", "..", or holding "/", ":" or a control
    character            → escape: the next source (URL, then "response")
  ⚠ panel cancelled      → not an error: nothing is written
  ⚠ unwritable(path)     → escape: an alert on the window, "Couldn't save the Response
                           body." with the path. FileWriting is atomic, so the target is
                           whole or untouched
Folding
  ⚠ a Folded region past the end of the body → DIE. Regions and body come from the
                           same Presented text; a mismatch is our bug
Curl Import
  ⚠ unterminatedQuote    → escape: a message under the URL bar with the position. The
                           Tab is unchanged and the pasted text is not inserted, because a
                           half-curl in the URL bar is not a URL either
  ⚠ noURL                → escape: same place, "No URL in this curl command"
  ⚠ unknown flag         → not an error: the ignored note
  ⚠ @file unreadable     → escape, per file: a multipart part keeps the path (send will
                           fail with fileMissing if it is still gone); a --data-binary
                           body becomes .none and the note says which file
  ⚠ @file not UTF-8      → escape: same as unreadable, "binary bodies are not supported"
  ⚠ two commands pasted  → not an error: the first is imported, the note says how many
                           were skipped
  ⚠ GET with a body      → not an error: imported as pasted, and the note says it won't
                           send, because URLSession fails it with dataLengthExceedsMaximum
                           and sends nothing (environment-facts.md Q6)
Curl pane
  ⚠ blank URL            → escape: "Type a URL to see the curl command.", Copy disabled
  ⚠ undefined(names)     → escape: "No curl command yet" and every name, Copy disabled
  ⚠ invalidURL           → escape: "No curl command yet" and the URL after substitution,
                           Copy disabled. Nothing is outlined: nothing was sent
  ⚠ Keychain unreadable  → the preview never reads it. With Include secrets, Copy resolves
                           it as undefined and copies nothing
Postman Import
  ⚠ file not JSON, or not a v2 Collection / Environment / Globals export
                         → escape: that file's row on the Import sheet says "Not a Postman
                           export Raccoon reads"; the other files still import
  ⚠ file unreadable      → escape: same row, disabled: "Can't be read: <reason>"
  ⚠ something Raccoon cannot represent (scripts, OAuth, binary body, dynamic variables)
                         → not an error: an ImportNote, shown on the sheet before Import
  ⚠ Data Folder not writable → escape: the sheet says so and Import is disabled
  ⚠ a Collection fails to write → escape: written to a temp folder and renamed, so it lands
                           whole or not at all; the sheet's result names it, the others land
  ⚠ SecretStore.set fails for an imported secret → escape: the Variable is written as a
                           secret with no value (undefined until set) and noted. Never
                           written in clear
  ⚠ an Environment file or globals.json fails to write → escape: the result names it, the
                           secrets just stored for it are deleted again, the rest lands
Postman Export
  ⚠ the save panel cancelled → not an error: back on the Export sheet, nothing written, and no
                           Keychain read has happened (an Environment's are read after the panel)
  ⚠ the target not writable, or the write fails → escape: the sheet stays with a red line, "Not
                           exported. <reason>.", and Export… still works for another place. The
                           write is atomic (temp file, then replace): the old file at that url
                           is as it was, and nothing half-written is left. Any secret values
                           already read are dropped. NEVER retried: the user picks again
  ⚠ a Request file that does not decode (an .unreadable node, or a file that no longer decodes
                           when read) → escape: skipped, counted on the sheet and its file name listed (names
                           only, the reason is the tooltip of that line), and never blocks the
                           export. The file on disk is untouched
  ⚠ a Request file can't be read, or the Data Folder fails mid-read → escape: the same row: that
                           file is skipped, counted and listed by file name like the rest
  ⚠ the Collection gone from the index when the sheet should open (renamed or trashed outside
                           Raccoon) → escape: nothing opens
  ⚠ a Request that is Dirty in a Tab → not an error: an info line, "N Requests have edits
                           in a Tab. Export uses what is saved."; the file holds the saved Request
  ⚠ a Request changed on disk while the Export sheet is open → not an error: the file holds
                           what the sheet counted and scanned (the plan is computed once)
  ⚠ credentials found     → not an error: a warning with the count and the Request names;
                           Export… is still enabled and the file holds them as typed
  ⚠ Include secret values, SecretStore.get throws → escape: that one Secret Variable is exported
                           empty, the others are still read, and the result names it after the
                           write. Never a failed export: the file is on disk
  ⚠ the target is a symlink → not an error: the atomic replace writes a regular file where the link
                           was, and the file it pointed to is unchanged. The save panel named the
                           link, so the link's path is what holds the export
  ⚠ Include secret values, a Secret Variable has no Keychain item → not an error: exported empty,
                           not named. It was never typed, and Raccoon resolves it as undefined too
  ⚠ Include secret values off → not an error: every Secret Variable is written `type: "secret"`
                           with an empty value, and the Keychain is not read
  ⚠ Export on Globals, or on an Environment that does not decode → no such item: neither row has
                           an Export… (variables.md)
  ⚠ the file saved inside the Data Folder → not an error: the watch sees an outside change, and a
                           `.json` in a Collection that is not a Request is an .unreadable row
  ⚠ Import from Postman… in the Environments sheet, Cancel in the open panel → not an error: no
                           sheet is open, since the Environments sheet closed first
Data Folder
  ⚠ root not writable    → escape: banner with Open Workspace…, sidebar empty, Drafts and
                           sending still work. A missing Data Folder must not stop the
                           app from being an HTTP client
  ⚠ file undecodable     → escape: an .unreadable row, the file kept byte-for-byte, never
                           rewritten. This includes a `pathVariables` that is not an object
                           or holds a non-string value (boundary.md)
  ⚠ duplicate RequestID  → escape: the second by path order is .unreadable
  ⚠ write failed         → escape: banner, Tab stays Dirty. Nothing on screen claims a
                           save that did not land
  ⚠ file deleted under a Tab → escape: the Tab becomes a Draft with its content
  ⚠ globals.json or an Environment file undecodable → escape: its Variables are undefined
                           until the file is fixed; logged. The Environments sheet lists it
                           read-only with the reason, the picker does not, and nothing
                           rewrites it (− can still trash an Environment's)
  ⚠ a secret entry carries a "value" → escape: the value is dropped and the name logged
Session
  ⚠ undecodable          → escape: start with one empty Tab; the bad file is renamed
                           <key>.corrupt-<date>.json, not deleted, and logged only
                           (Open UI Q7)
  ⚠ unreadable           → escape: start with one empty Tab and log it
  ⚠ rename fails         → escape: log it. The next Session write replaces the bad file,
                           which loses only what was already lost
  ⚠ unwritable on quit   → escape: quit anyway and log it. Blocking quit on a cache file
                           is worse than losing Drafts once
  ⚠ snapshot names a Request that is gone → escape: restored as a Draft
  ⚠ its Data Folder can't be read → escape: the Session is not read and not written,
                           so it survives until the folder is back (workspaces.md)
  ⚠ Active Environment file gone → escape: none active
Secrets
  ⚠ SecretStore.set fails → escape: the Variable stays unsaved in the sheet with the
                           OSStatus message; the file is not touched (variables.md order).
                           Marking, and typing a secret's value, both end here
  ⚠ mark: file write fails after the Keychain took the value → escape: the item is removed
                           again, "Not saved. <reason>." under the row
  ⚠ unmark: the secret cannot be read → escape: the file gets an empty value, nothing is deleted
  ⚠ hover over a secret → not an error: the popover says "Secret" and the source; no Keychain
                           read exists on that path, nor on the inspector's selected row
  ⚠ "Variables in request" for a name no longer in the pane (edited away meanwhile) → not an
                           error: the inspector opens with nothing selected
  ⚠ a value edited in the Variables pane is not written (StoreError, or the file does not
                           decode) → escape: "Not saved. <reason>." under the row; the cell shows
                           the file's value again; nothing else changes
  ⚠ a secret typed in the Variables pane is refused by the Keychain → escape: "Not saved. The
                           Keychain refused the write (OSStatus …)." under the row; the file is
                           not touched
  ⚠ a secret in the suggestion list → not an error: its row says "Secret" and the source,
                           and accepting it writes only {{name}}; no Keychain read
  ⚠ Environment renamed  → not an error: its secrets move with it, Keychain first, file
                           second (copied, file moved, old items deleted: a failure before
                           the file moves leaves the old name whole)
  ⚠ rename to a name another Environment has → escape: refused, the field reverts, a red
                           line under it; nothing moves
  ⚠ Variable name invalid or repeated → escape: refused, the old name stays, a red line under
                           the row; nothing written
  ⚠ Environment deleted  → not an error: the file goes to the Trash, its Keychain items stay
  ⚠ Keychain item of a deleted row, or of a renamed Environment, not deleted → escape: log
  ⚠ a sheet write fails  → escape: "Not saved. <reason>." under the row or the name field;
                           the cell reverts
Workspaces
  ⚠ remembered folder missing or unreadable → escape: the not-readable banner with Open
                           Workspace… and Remove from List; never created, never dropped
                           from the list on its own
  ⚠ raccoon.json undecodable → escape: never rewritten; that Workspace's secrets are
                           undefined and setting one fails with "raccoon.json can't be
                           read", in the Environments sheet row
  ⚠ raccoon.json can't be written → escape: the not-writable banner, as for any write
  ⚠ New Workspace… names a folder that exists → escape: alert, nothing written
  ⚠ New Workspace… can't create the folder → escape: alert sheet with the reason
  ⚠ a send in flight on switch → not an error: cancelled, as Close cancels it
  ⚠ switching with a Dirty Tab or a non-empty Draft, Cancel or Esc in the Leave sheet
                           → escape: the switch ends, every Tab stays as it was; removing
                           the open Workspace removes nothing
  ⚠ Save All, a write did not land or Cancel in the Save Request sheet → escape: the
                           switch ends there; Tabs saved so far stay saved, the rest stay open
  ⚠ Don't Save → not an error: the Tabs with something to lose are closed, and the Session
                           written for the Workspace holds none of it
  ⚠ confirmLeave never set → escape: refuses, so the switch never happens. The safe side of
                           a closure that can discard work
  ⚠ Session file of a removed Workspace can't be deleted → escape: log only
Theme
  ⚠ bundled theme JSON undecodable or missing a token → DIE. The file ships inside the
                           app; a bad one is our bug, and a test over every bundled Flavor
                           fails before it can ship
  ⚠ stored ThemeChoice names an unknown Theme → escape: Catppuccin Latte / Mocha
  ⚠ AppIcon.png missing or unreadable when packaging → make-app.sh stops: no Raccoon.app
                           is written. The app itself never reads the icon
Close (UserDefaults)
  ⚠ stored AlwaysDiscardOnClose not a Bool → escape: off, so closing asks. The safe side of
                           a preference that discards work is the prompt
  ⚠ Close Other Tabs or Close All Tabs, one Tab answered Cancel or its Save did not land
                           → escape: the batch stops there; the rest stay open
  ⚠ Force Close All Tabs, Cancel in the confirmation → escape: nothing closes
  ⚠ Duplicate Tab on a Tab that closed meanwhile → escape: nothing happens
  ⚠ always discarding is on → not an error: a Dirty Tab or a non-empty Draft closes with no
                           sheet and its edits are gone. File ▸ Always Discard Unsaved
                           Changes, checked, turns it off (tabs.md)
Inspector (UserDefaults)
  ⚠ stored width not a number          → escape: 280 pt
  ⚠ stored width outside 240–400       → escape: clamped to the nearer bound
  ⚠ stored pane names no pane          → escape: Variables
  ⚠ restored open in a window too narrow to dock it → not an error: overlaid (Q2)
Breadcrumb
  ⚠ the index has no entry for the Tab's RequestID (its file is unreadable now, or a rescan has
                           not landed) → escape: the last known segments stay, so nothing
                           flickers; with none ever shown, the Tab's title alone as a Draft's.
                           Not shown as an error: the Request is still the one in the Tab, and a
                           file deleted outright makes the Tab a Draft instead
  ⚠ a segment's path has no row in the sidebar (last-known segments after a Folder was renamed
                           or removed) → escape: the sidebar shows and nothing is selected. Never
                           an alert: the next derivation replaces the segments
  ⚠ too narrow for every segment → not an error: the middle collapses into "…", then the last
                           name end-truncates, then the first; tooltips hold the full text
Docs
  ⚠ markdown that does not parse as the user meant → not an error: DocsStyle.ranges is total;
                           unmatched marks are drawn as text and only matched marks are hidden.
                           The characters are never changed by drawing
  ⚠ a format command that does not apply (Delete at the start of a plain line, Return on a
                           plain line) → not an error: DocsEdit.apply returns nil and the editor
                           does its own Delete or Return; an inline toggle on plain text wraps it
GraphQL
  ⚠ Variables not a JSON object after substitution → escape: .notSent(.graphqlVariables), the
                           message "Not sent. Variables is not a JSON object: line 3, column 14."
                           Nothing went out
  ⚠ GraphQL body on a GET set by hand → the existing Body on GET failure, not a new one
  ⚠ the server answers 200 with an `errors` array → not an error: it is the Response, shown
                           as JSON like any other
  ⚠ Postman Export of an Operation Name → not an error: Postman has no field for it, it is
                           left out (graphql.md)
Examples
  ⚠ Save as Example, the Request file unreadable, undecodable or unwritable → escape: the Body
                           toolbar's note "Couldn't save the Example: <reason>." Nothing written,
                           a file Raccoon failed to read is never rewritten (collections.md)
  ⚠ a Request ⌘S whose file has Examples → not an error: read-modify-write keeps them. The file
                           unreadable now -> the existing "Not saved" path
  ⚠ an Example ⌘S, its Request file gone → escape: stays Dirty, "Not saved. Its Request was
                           deleted."
  ⚠ an Example ⌘S, the Example gone from the file → not an error: appended again, same id
  ⚠ an `examples` entry that does not decode (no id, a status that is not a number, a body
                           with neither text nor base64) → the whole file is .unreadable, as for
                           any wrong key: one format, no half-read Request
  ⚠ two Examples with one id in a file → the file is .unreadable("duplicate Example id")
  ⚠ status outside 100...599, delay outside 0...60000 → not an error: clamped by the init
Mock Server
  ⚠ the remembered port is taken  → escape: alert "Port <n> is in use." Use Another Port
                           binds a free one and remembers it; Cancel starts nothing
  ⚠ NWListener fails for any other reason → escape: alert "Couldn't start the Mock Server:
                           <reason>."
  ⚠ raccoon.json unwritable when remembering the port → escape: logged; the server runs, the
                           port is not remembered
  ⚠ a request head that does not parse → not an error of Raccoon's: 400, connection closed.
                           Never retried, never shown
  ⚠ head over 64 KiB or body over 16 MiB → 413, connection closed
  ⚠ Transfer-Encoding on the request → 501, connection closed (mock-server.md, shortcut)
  ⚠ no route or no Example matches → 404 with a JSON reason; not an error
  ⚠ the client goes away during the delay or the write → not an error: the connection closes
  ⚠ a Collection renamed or trashed while its Mock Server runs → escape: the server stops and
                           the row's indicator goes; a renamed one starts again by hand
  ⚠ a Request file in the Collection unreadable → not an error: it has no route, as it has no
                           Tab
Sending loader
  ⚠ the JSON missing from the bundle, or Lottie cannot decode it → escape: no loader. The
                           sending state is the status row's spinner and the text, as before
                           the loader. No alert, no banner, nothing shown. Read once, on the
                           first send that needs it; the result, nil included, is kept
  ⚠ the body area under 296 pt high → not an error: the loader is hidden, the text stays
  ⚠ a bitmap added to the JSON (an image asset or layer) → DIE at test time, not at run time:
                           SendingLoaderAssetTests fails, because a bitmap would blur when scaled
  ⚠ the state is anything but .sending (Cancel, failure, time-out, a received Response) → not
                           an error: the view is removed on that frame, mid-loop
  ⚠ the selected Tab changes → not an error: the one player rebinds; a Tab that is not
                           selected has no player, and the new Tab's own 150 ms applies
  ⚠ the window is occluded or miniaturised → not an error: paused; it plays from frame 0 when
                           the window is visible again
  ⚠ Reduce Motion changes while sending → not an error: the next 100 ms redraw swaps the loop
                           for the still pose, or the still for the loop from frame 0
Invariants
  ⚠ two Tabs with the same .request(id)    → DIE (assertion). openRequest and relaunch
                           are the only ways in and both check
  ⚠ ResolvedRequest built outside the resolver → impossible: no public init (shapes.md)
```

**Every escape says what happened in the place it happened.** A send error is in the
Response pane, a curl error under the URL bar, a file error on the sidebar row. A global
alert is used only for the Data Folder itself, because that is the one failure with no
smaller place to show it.
