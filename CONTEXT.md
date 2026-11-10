# Raccoon

A native macOS HTTP client for building, sending and saving HTTP requests, in the style of Postman.

## Language

### Requests

**Request**:
A saved HTTP request definition (method, URL, headers, query params, Path Variable values, body, cookies, auth) that lives in a Collection.
_Avoid_: Call, endpoint, API

**Draft**:
An unsaved request definition that exists only in a Tab until the user saves it into a Collection.
_Avoid_: Scratch, untitled request

**Data Folder**:
The root folder on disk of one Workspace, holding its Collections, Environments and Globals.
_Avoid_: Vault, library

**Workspace**:
A Data Folder that Raccoon remembers, named by its folder; the window shows one at a time, and switching Workspaces swaps the sidebar, the Environments and the open Tabs together.
_Avoid_: Project, profile, account

**Collection**:
A named group of Requests and Folders, shown as a tree in the sidebar.
_Avoid_: Project

**Folder**:
A named group of Requests and Folders inside a Collection, nestable to any depth.
_Avoid_: Group, directory, section

**Body Type**:
The kind of request body: none, raw (JSON, text or XML), form-urlencoded, or multipart.
_Avoid_: Content mode, payload type

**Auth**:
The request's authentication scheme: none, Basic, or Bearer.
_Avoid_: authorization header

**Request Settings**:
Per-request transport options: allow insecure TLS, follow redirects, follow the original HTTP method, follow the Authorization header, the Redirect Limit and the Request Timeout.
_Avoid_: Options, flags

**Redirect Limit**:
How many redirects one send follows before it fails. 0 to 20, because URLSession stops at 20 itself.
_Avoid_: Max redirects, hops

**Request Timeout**:
The seconds one send allows to pass with no new bytes arriving, before it fails. Unset is 60.
_Avoid_: Deadline, TTL, total time

**Response**:
The result of the last send from a Tab, kept in memory only and lost when the Tab closes or Raccoon quits.
_Avoid_: Result, output, history entry

**Disabled Row**:
A header, query param, form field or Request Cookie that stays saved on the request but is not sent.
_Avoid_: Commented out, inactive, muted

**Curl Import**:
Turning a pasted `curl` command into the parts of a request definition, triggered by pasting into the URL bar.
_Avoid_: Curl parse, conversion

**Postman Import**:
Turning Postman Collection, Environment and Globals exports into Collections, Environments and Globals in the Data Folder, with everything Raccoon cannot represent listed before anything is written.
_Avoid_: Migration, sync, Postman converter

**Postman Export**:
Writing a Collection as a Postman Collection v2.1 file, or an Environment as a Postman Environment file, to a place the user picks outside the Data Folder. The file holds exactly what the Requests hold; Credentials found in a Collection are listed first, never removed. An Environment's Secret Variables are written empty unless the user asks for their values.
_Avoid_: Backup, share, publish, sync, Postman converter

**Credential**:
A literal token, password or key typed into a Request: a header, query param or Auth field whose name says what it holds and whose value is not a `{{name}}` reference. The Postman Export scan finds them and reports how many there are and in which Requests, never the values, so the user knows what the file will carry. It is not the Auth scheme (Auth), and not a Secret Variable, which is kept in the Keychain and never typed into a Request.
_Avoid_: Secret (Postman's word; a Secret Variable is a different thing), leak, password or token as the general word

**Copy as Curl**:
Turning a request definition into a `curl` command with Variables resolved, for sharing outside Raccoon.
_Avoid_: Curl export, generate code

**Request Cookies**:
The cookies stored on a Request and sent with it; responses never add to them.
_Avoid_: Cookie jar, session cookies

### Tabs

**Tab**:
An open editor for exactly one Request or Draft, holding its own editing state, inside the single main window. A Request is open in at most one Tab.
_Avoid_: Window, page

**Dirty**:
The state of a Tab whose edits to a saved Request have not been written back to its Collection.
_Avoid_: Modified, unsaved, changed

**Changed on Disk**:
The state of a Dirty Tab whose Request file was modified outside Raccoon, which the user resolves by reloading or keeping their edits.
_Avoid_: Conflict, out of sync, stale

**Session**:
The set of open Tabs of one Workspace, including Drafts and Dirty edits, that is restored when Raccoon relaunches. Switching away asks about Drafts and Dirty edits first, so switching back restores only Tabs with nothing to lose.
_Avoid_: State, snapshot

**Breadcrumb**:
The line above the URL bar that names where the Tab's Request lives, from its Collection down through its Folders to its own name; clicking a name selects that location in the sidebar. A Draft has no location, so its Breadcrumb is its Tab title alone.
_Avoid_: Path bar, location bar, trail

### Variables

**Variable**:
A named value referenced as `{{name}}` inside a request definition and substituted when the request is sent.
_Avoid_: Placeholder, param

**Globals**:
The set of Variables that apply regardless of which Environment is active.
_Avoid_: Global environment, defaults

**Environment**:
A named set of Variables (such as Dev, Staging, Prod) whose values override Globals while it is active.
_Avoid_: Profile, config, stage

**Active Environment**:
The single Environment currently used for substitution; there may be none.
_Avoid_: Selected environment, current env

**Secret Variable**:
A Variable whose value is kept in the macOS Keychain under its Workspace's id; only its name is written to the Data Folder.
_Avoid_: Hidden variable, sensitive value

**Undefined Variable**:
A `{{name}}` reference that neither the Active Environment nor Globals defines; a request containing one cannot be sent.
_Avoid_: Missing var, unresolved placeholder

**Path Variable**:
A `:name` segment in a Request's URL, replaced when the request is sent by a value kept on the Request. It is not a Variable: it has no `{{ }}`, belongs to no Environment, and the URL, not a table, says which names exist.
_Avoid_: URL param, route param, URL variable

### Response viewer

**Gutter**:
The column left of a body's text that holds its line numbers and, in a Pretty Response, a chevron on every line that opens a Fold Region.
_Avoid_: Ruler, margin, line-number bar

**Fold Region**:
A block of a Pretty Response body that opens on one line and closes on a later one, such as a JSON object or an XML element with children.
_Avoid_: Section, node, block

**Fold**:
To show a Fold Region on its opening line only, as `{ … }`; unfolding shows its lines again. The text keeps every line, so Copy and selection still see a folded one. Fold state is view state: every send starts unfolded and it is never saved.
_Avoid_: Collapse, expand, hide

**Redirect**:
One 3xx a send followed on its way to the Response: the URL that answered, the method sent to it, its status, its headers and the Location it pointed to. A redirect the send refused is not a Redirect; it is the Response.
_Avoid_: Hop, leg, bounce, transaction

**Timeline**:
The Response viewer's third section: each Redirect, then the Response, in the order they were sent, each with its Timing.
_Avoid_: Waterfall, trace, history

**Timing**:
How long one request of a send spent in each phase (DNS, Connect, TLS, Send, Waiting, Download), as URLSession measured it. A phase it skipped is absent, not 0.
_Avoid_: Metrics, latency, profile

**Wire Size**:
A Response body's byte count as it crossed the network, before URLSession undid its `Content-Encoding`.
_Avoid_: Transfer size, compressed size

**Hex view**:
A binary body drawn as `hexdump -C` draws it: offset, sixteen bytes in hex, then those bytes as ASCII.
_Avoid_: Hex editor, binary viewer

**Body toolbar**:
The row under the Response viewer's status line, in the Body section only: Pretty | Raw and its note on the leading edge, Search and Copy on the trailing edge.
_Avoid_: Action bar, response toolbar

**Find panel**:
The small panel that floats over a Response body's top-right corner to search it: a field, the match count, previous, next and close. It searches the whole body, folded lines included, and unfolds only the Fold Region a match is in.
_Avoid_: Search bar, find bar (the system's, which the Response body no longer uses)

**Save Response Body**:
Writing a received body's bytes, as the viewer holds them, to a file the user picks.
_Avoid_: Download, export (Export is Postman Export)

### Appearance

**Theme**:
A named family of color schemes for the content areas (editors, response viewer, tab strip), chosen from a menu; Catppuccin is the first.
_Avoid_: Skin, color mode

**Flavor**:
One color scheme within a Theme; the user picks one Flavor for light appearance and one for dark, and Raccoon follows the system setting.
_Avoid_: Variant, palette, mode
