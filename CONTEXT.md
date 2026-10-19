# Raccoon

A native macOS HTTP client for building, sending and saving HTTP requests, in the style of Postman.

## Language

### Requests

**Request**:
A saved HTTP request definition (method, URL, headers, query params, body, cookies, auth) that lives in a Collection.
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
_Avoid_: Credentials, authorization header

**Request Settings**:
Per-request transport options: allow insecure TLS and follow redirects.
_Avoid_: Options, flags

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
The set of open Tabs of one Workspace, including Drafts and Dirty edits, that is restored when Raccoon relaunches or the user switches back to that Workspace.
_Avoid_: State, snapshot

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

### Appearance

**Theme**:
A named family of color schemes for the content areas (editors, response viewer, tab strip), chosen from a menu; Catppuccin is the first.
_Avoid_: Skin, color mode

**Flavor**:
One color scheme within a Theme; the user picks one Flavor for light appearance and one for dark, and Raccoon follows the system setting.
_Avoid_: Variant, palette, mode
