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
  ⚠ timedOut             → escape: "No response after 60 s"
  ⚠ untrustedCertificate → escape: the message names the host and offers "Allow insecure
                           TLS for this request", which flips the Request Setting. It is
                           never flipped automatically
  ⚠ fileMissing(path)    → escape: the multipart row is marked and the send stops before
                           any byte goes out
  ⚠ transport(code)      → escape: URLError's own description, plus the code and host
resolve
  ⚠ undefined(names)     → escape: every name listed, red underlines already on screen,
                           nothing sent, no spinner
  ⚠ invalidURL           → escape: .notSent. The URL bar is outlined, the message quotes
                           the URL after substitution, because that is the one that failed
  ⚠ Keychain unreadable  → becomes undefined for that secret. One path, not two: the user
                           sees "token is not defined" and the Environments sheet shows
                           why
showResponse
  ⚠ body not UTF-8       → not an error: .binary(byteCount)
  ⚠ JSON did not parse   → not an error: .raw. A server that says json and sends HTML
                           is the server's fact
  ⚠ body does not nest   → not an error: no Fold Regions, no chevrons
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
  ⚠ file unreadable      → escape: same row, with the reason
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
Data Folder
  ⚠ root not writable    → escape: banner with Open Workspace…, sidebar empty, Drafts and
                           sending still work. A missing Data Folder must not stop the
                           app from being an HTTP client
  ⚠ file undecodable     → escape: an .unreadable row, the file kept byte-for-byte, never
                           rewritten
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
  ⚠ Session file of a removed Workspace can't be deleted → escape: log only
Theme
  ⚠ bundled theme JSON undecodable or missing a token → DIE. The file ships inside the
                           app; a bad one is our bug, and a test over every bundled Flavor
                           fails before it can ship
  ⚠ stored ThemeChoice names an unknown Theme → escape: Catppuccin Latte / Mocha
Inspector (UserDefaults)
  ⚠ stored width not a number          → escape: 280 pt
  ⚠ stored width outside 240–400       → escape: clamped to the nearer bound
  ⚠ stored pane names no pane          → escape: Variables
  ⚠ restored open in a window too narrow to dock it → not an error: overlaid (Q2)
Invariants
  ⚠ two Tabs with the same .request(id)    → DIE (assertion). openRequest and relaunch
                           are the only ways in and both check
  ⚠ ResolvedRequest built outside the resolver → impossible: no public init (shapes.md)
```

**Every escape says what happened in the place it happened.** A send error is in the
Response pane, a curl error under the URL bar, a file error on the sidebar row. A global
alert is used only for the Data Folder itself, because that is the one failure with no
smaller place to show it.
