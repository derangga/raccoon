# §2 A — Mock Server

One local HTTP server per Collection that answers with that Collection's Examples
(examples.md). Started and stopped by hand, on 127.0.0.1 only. Decided 2026-11-12.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

The Mock Server is the one place Raccoon listens instead of sends. It serves what the
Examples hold, byte for byte, and adds only what HTTP framing needs and what the user switched
on (CORS), both listed below.

## Start and stop

The Collection row's menu has **Start Mock Server** (or **Stop Mock Server** while it runs)
and **Mock Server…**. The sheet is where the port and CORS are set and where the routes can be
read before anything starts. Decided 2026-11-20: a first start with no settings remembered opens
the sheet instead of starting blind.

```
-> startMock(collection)                         the menu's Start Mock Server, or Start in the sheet
  -> MockSettings for the Collection             raccoon.json `mocks.<Collection name>`:
                                                 {port, allowsCORS}; absent -> port nil,
                                                 allowsCORS true (workspaces.md, boundary.md)
     absent from raccoon.json (never started, never configured) and started from the menu
                                                 -> openMockSheet(collection) instead; nothing starts
  -> MockRoutes.build(requests)                  pure        R: none   E: none, total
     the Collection's decodable Requests, read through DataFolderStore by the window
  -> MockListening.listen(port: settings.port)   boundary    R: MockListening
                                                 nil -> the system picks a free port
                                                 E: .portInUse(port) -> escape: shown in the sheet
                                                    under the Port field ("Port <n> is in use.");
                                                    started from the menu, the sheet opens to show it
                                                 E: .failed(reason) -> escape: shown in the sheet
                                                    under the status line; the same rule from the menu
  -> remember the bound port                     raccoon.json, through WorkspaceFile.replacing
                                                 (reads the current bytes, keeps the id and the
                                                 other Collections' entries); a write
                                                 that fails is logged, the server still runs
  -> the window holds MockServer(collection, port, routes, task)
                                                 §8: inside withDataFolder
  -> the Collection row shows the mock indicator; the toolbar shows the Mock Server item
-> stopMock(collection)                          Stop Mock Server, Workspace switch, quit
  -> the listener cancelled                      open connections closed, pending delays
                                                 cancelled (§8)
```

Nothing restarts on relaunch. A Collection that is renamed keeps no settings: its name is its
key (shapes.md, IDs), so its next start picks a new port.

## The Mock Server sheet

A native sheet for one Collection, opened by **Mock Server…** in the Collection's menu, by the
toolbar item, and by a start that needs to show a problem. It configures; it is not where the
server is watched (the toolbar item and the row do that). Closing it never stops the server.

```
-> openMockSheet(collection)                     Mock Server… , the toolbar item, a failed start
  -> MockSettings for the Collection             the Port field and the CORS switch start from these
  -> MockRoutes.build(requests)                  pure: the route list is shown before the first Start,
                                                 and follows a running server's rebuilds
  -> editPort(text)                              every keystroke
    -> MockPort.parse(text)                      pure        R: none   E: none, total
                                                 "" -> .automatic; 1024...65535 -> .port(n);
                                                 anything else -> .invalid, which shows the
                                                 inline message and disables Start / Restart
    -> remembered when it parses                 raccoon.json, same write as the bound port;
                                                 a running server keeps its port until Restart
  -> setAllowsCORS(on)                           applies at once: no restart, the next reply
                                                 carries it; remembered
  -> Start Mock Server                           -> startMock(collection)
  -> Restart Mock Server                         only while running and the Port field differs from
                                                 the bound port: stopMock then startMock
  -> Stop Mock Server                            -> stopMock(collection)
  -> Done                                        closes the sheet; settings already remembered
```

The sheet's state is one enum, so every state is designed (design-graph §10):

```
MockSheetState   .stopped · .starting · .running(port) · .failed(.portInUse(port) | .failed(reason))
```

## What the sheet shows

Copy is plain and short. A control's label is its action.

| Place | Text |
|---|---|
| Heading, then the Collection's name under it, secondary | "Mock Server" |
| Status, stopped | "Not running" |
| Status, starting | "Starting…" |
| Status, running, with a Copy URL button | "Running at http://127.0.0.1:3000" |
| Port label | "Port" |
| Port hint | "Use a port from 1024 to 65535, or leave it empty and Raccoon picks one." |
| Port, a running server whose field was edited | "Restart to use port 3001." |
| Port, a running server whose field was cleared | "Restart to use any free port." |
| Port invalid | "Use a port from 1024 to 65535." |
| Port taken | "Port 3000 is in use. Choose another port, or" + a link button "use any free port" |
| Start failed for another reason | "Couldn't start the Mock Server: <reason>." |
| CORS switch label | "Allow browser requests (CORS)" |
| CORS hint | "Lets web pages on other sites call this server." |
| Routes heading | "Serving 3 of 4 Requests" |
| Route row | "GET /users/:id" and "2 Examples" (or "1 Example") |
| Route row, a Request with no Example | "GET /refunds" and "Add an Example to serve it." |
| Routes, none | "Nothing to serve yet. Save a Response as an Example to start." |
| Footer note | "It stops when you quit Raccoon or switch Workspace, and doesn't start again by itself." |
| Buttons, stopped | Cancel · **Start Mock Server** (default) |
| Buttons, running | Stop Mock Server · **Done** (default) |
| Buttons, running, port edited | Stop Mock Server · **Restart Mock Server** (default) · Done |

While running, Done is the default so Return cannot stop the server by accident. Starting
disables the button and shows the system spinner after 150 ms.

## Where it shows that it runs

```
Toolbar item        a green dot and "Mock Server :3000", before the Environment picker. Two or more
                    running: "2 Mock Servers". None running: not drawn. A click opens the sheet, or
                    a menu of the running Collections first when there are several.
                    Tooltip and accessibility label: "Mock Server running on http://127.0.0.1:3000.
                    Click to configure." and "2 Mock Servers running. Click to choose one."
Collection row      the 8 pt dot and the port in secondary SF Mono, before the More actions button;
                    tooltip "Mock Server running on http://127.0.0.1:3000"
```

No animation: the state changes on one frame (design-system §5).

## Answer a request

```
-> a connection                                  MockListening, off the main actor
  -> MockRequestHead.parse(bytes)                pure, boundary.md
                                                 request line, headers, then a body of
                                                 Content-Length bytes, read and dropped
                                                 E: malformed -> 400, connection closed
                                                 E: head over 64 KiB or body over 16 MiB
                                                    -> 413, connection closed
                                                 E: Transfer-Encoding on the request -> 501
                                                    (shortcut: chunked request bodies are not
                                                    read; upgrade when a client needs it)
  -> MockMatch.answer(routes, head, allowsCORS)  pure        R: none   E: none, total
     -> OPTIONS with Access-Control-Request-Method, allowsCORS
                                                 -> 204 with the CORS headers below
     -> candidates: routes whose method equals the request's and whose path matches
     -> pick by x-mock-response-name, then x-mock-response-code, else the first Example
        of the most specific route
     -> none                                     -> 404, JSON {"error": "No Example matches
                                                    GET /users/42"}, or 404 naming the header
                                                    value that matched nothing
  -> wait example.delayMilliseconds              Task.sleep; cancelled with the server
  -> MockReply.bytes(reply)                      pure: status line, the Example's headers in
                                                 their order, Content-Length, Connection:
                                                 close, and the CORS headers when on
  -> write, close                                one request per connection
```

## Matching

`MockRoutes.build` turns each Request with Examples into one route: its method and its URL
path as segments. The path is the URL text, before `?`, with the scheme and authority dropped:

- `https://api.example.com/users/:id` -> `users`, `:id`
- `{{baseUrl}}/users/:id` -> a leading `{{name}}` up to the first `/` is the authority, so
  `users`, `:id`
- `{{host}}/v1/{{version}}/items` -> `v1`, `{{version}}`, `items`

A `:name` segment and a segment that is wholly `{{name}}` match any one non-empty segment. Any
other segment matches its own text after percent-decoding, case-sensitively. Trailing `/` is
ignored on both sides. The query string is ignored.

**The most specific route wins.** Routes are compared segment by segment from the left: a
literal beats a wildcard at the first place they differ. `GET /users/me` beats
`GET /users/:id` for `/users/me`. A tie (two Requests with the same method and path shape)
goes to the first in sidebar order, the order the user sees.

**The headers pick, then the first Example.** `x-mock-response-name` picks the route's Example
of that name (the first, if names repeat); `x-mock-response-code` picks its first Example with
that status. Both are Postman's, so a client written against a Postman mock keeps working.
Without them the route's first Example answers.

**What is served is on disk.** Routes are rebuilt from the files on every `filesChanged` batch
and every write Raccoon makes in the Collection, so ⌘S on an Example changes the next reply.
A Dirty Tab's edits are not served.

**The Example's body is sent literally.** `{{name}}` in it is text: an Example is a recorded
reply, not a template, and resolving it would put Secret Variables on a socket.

## What the Mock Server adds

- `Content-Length`, computed from the body, and `Connection: close`. Save as Example drops the
  four framing headers a captured Response carries (examples.md); an Example edited by hand to
  hold `Content-Length` or `Connection` has them replaced, not doubled.
- With Allow Browser Requests on: `Access-Control-Allow-Origin: *`, and for a preflight
  `Access-Control-Allow-Methods` (the requested method), `Access-Control-Allow-Headers` (the
  requested headers) and `Access-Control-Max-Age: 600`. An Example that sets one of these
  keeps its own.

## Security

The listener binds to 127.0.0.1, never to all interfaces, so nothing off the machine can reach
it and macOS's firewall does not prompt. It reads no file outside the Data Folder, resolves no
Variable and runs no code: the worst a local caller gets is an Example the user saved.
