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
The single root folder on disk that holds every Collection, the Environments and Globals.
_Avoid_: Workspace, vault, library

**Collection**:
A named group of Requests and Folders, shown as a tree in the sidebar.
_Avoid_: Workspace, project

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
Per-request transport options: allow insecure TLS, follow redirects, and request compressed responses.
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
The set of open Tabs, including Drafts and Dirty edits, that is restored when Raccoon relaunches.
_Avoid_: Workspace, state, snapshot

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
A Variable whose value is kept in the macOS Keychain; only its name is written to the Data Folder.
_Avoid_: Hidden variable, sensitive value

**Undefined Variable**:
A `{{name}}` reference that neither the Active Environment nor Globals defines; a request containing one cannot be sent.
_Avoid_: Missing var, unresolved placeholder

### Appearance

**Theme**:
A named family of color schemes for the content areas (editors, response viewer, tab strip), chosen from a menu; Catppuccin is the first.
_Avoid_: Skin, color mode

**Flavor**:
One color scheme within a Theme; the user picks one Flavor for light appearance and one for dark, and Raccoon follows the system setting.
_Avoid_: Variant, palette, mode
