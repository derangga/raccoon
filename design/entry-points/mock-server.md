# §2 A — Mock Server

One local HTTP server per Collection that answers with that Collection's Examples
(examples.md). Started and stopped by hand, on 127.0.0.1 only. Decided 2026-11-12.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

The Mock Server is the one place Raccoon listens instead of sends. It serves what the
Examples hold, byte for byte, and adds only what HTTP framing needs and what the user switched
on (CORS), both listed below.

## Start and stop

```
-> startMock(collection)                         the Collection row's menu: Start Mock Server.
                                                 A running one's menu has Stop Mock Server,
                                                 Copy Mock URL, and Allow Browser Requests
                                                 (CORS), checkable
  -> MockSettings for the Collection             raccoon.json `mocks.<Collection name>`:
                                                 {port, allowsCORS}; absent -> port nil,
                                                 allowsCORS true (workspaces.md, boundary.md)
  -> MockRoutes.build(requests)                  pure        R: none   E: none, total
     the Collection's decodable Requests, read through DataFolderStore by the window
  -> MockListening.listen(port: settings.port)   boundary    R: MockListening
                                                 nil -> the system picks a free port
                                                 E: .portInUse(port) -> escape: alert "Port
                                                 <n> is in use.", buttons Use Another Port
                                                 (listen(port: nil)) and Cancel
                                                 E: .failed(reason) -> escape: alert
  -> remember the bound port                     raccoon.json, through WorkspaceFile; a write
                                                 that fails is logged, the server still runs
  -> the window holds MockServer(collection, port, routes, task)
                                                 §8: inside withDataFolder
  -> the Collection row shows the mock indicator, tooltip "Mock Server on
     http://127.0.0.1:<port>"
-> stopMock(collection)                          Stop Mock Server, Workspace switch, quit
  -> the listener cancelled                      open connections closed, pending delays
                                                 cancelled (§8)
```

Nothing restarts on relaunch. A Collection that is renamed keeps no settings: its name is its
key (shapes.md, IDs), so its next start picks a new port.

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
