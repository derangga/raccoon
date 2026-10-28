# Raccoon — Design

Domain vocabulary is in [CONTEXT.md](./CONTEXT.md). UI work follows
[.P.DESIGN.UI.md](./.P.DESIGN.UI.md).

```
Raccoon → Graph → A / E / R
│          │      │   │  │
│          │      │   │  └─ what each node needs        §5
│          │      │   └──── where the graph breaks      §4
│          │      └──────── what flows through nodes    §2
│          └─ nodes = functions, edges = data flow
└─ the problem: turn what the user typed or pasted into exactly one HTTP request,
   send it, and show what came back, without the app adding or hiding anything
```

This file is an index. Nothing is defined here. Every section lives in `design/`, so a task
loads the two or three readings it needs instead of all of them.

## The graph, one file per reading

| Read this | When |
|---|---|
| [§1 Shapes](design/shapes.md) | Adding a type, or wondering why one is an enum and not a Bool |
| [§2 A — entry points](#2-a--the-happy-path) | Adding or changing an entry point. `design/entry-points/`, indexed below |
| [§3 Cardinality](design/cardinality.md) | Asking how long a value is good for, and what invalidates it |
| [§4 E — where it breaks](design/e-where-it-breaks.md) | Deciding `escape` / `RETRY` / `DIE` for a new failure |
| [§5 R — what each node needs](design/r-what-it-needs.md) | Deciding whether something is a rule, a port, or a boundary |
| [§6 Boundary](design/boundary.md) | Anything crossing `unknown → trusted`: pasted text, a file, a socket |
| [§7 Behavior](design/behavior.md) | Debounce, coalescing, timeouts: wrappers that change no tree |
| [§8 Scope](design/scope.md) | Acquire/release: in-flight sends, the folder watch, the Session file |
| [§9 Swap R to prove it](design/swap-r.md) | Writing a test, and asking which R to swap for it |
| [Environment facts](design/environment-facts.md) | Before assuming what the toolchain, URLSession or the references do |
| [Open empirical questions](design/open-questions.md) | Before trusting a claim nobody measured |

Working on one feature means its entry-points file plus §4 and §5.

## §2 A — the happy path

Every entry point as a call tree, one file per feature.

| File | Entry points | Milestone |
|---|---|---|
| [sending](design/entry-points/sending.md) | Send · Cancel · Show the Response | M1 |
| [editing](design/entry-points/editing.md) | Type in the URL bar · Edit a Params row · Edit a Path Variable value · Toggle a Disabled Row · Pick a Body Type · Format the body | M1 |
| [curl](design/entry-points/curl.md) | Paste into the URL bar · Copy as Curl · The Curl pane | M2 |
| [tabs](design/entry-points/tabs.md) | New Tab · Switch · Close · Always Discard Unsaved Changes · The empty state · Quit · Relaunch · Restore the inspector | M3 |
| [collections](design/entry-points/collections.md) | Load the Data Folder · Open a Request · Save · Save a Draft · Changed on Disk · Filter the sidebar · Select a location from the Breadcrumb | M4 |
| [variables](design/entry-points/variables.md) | Pick the Active Environment · Edit a Variable · Highlight `{{name}}` · Resolve on send · The Variables pane | M5 |
| [postman](design/entry-points/postman.md) | Import Postman Collections, Environments and Globals | M7 |
| [workspaces](design/entry-points/workspaces.md) | Switch Workspace · New Workspace · Open Workspace · Remove from List | M8 |
| [folding](design/entry-points/folding.md) | The Gutter · Fold · Unfold · Fold All | — |
| [theme](design/entry-points/theme.md) | Pick a Theme or Flavor · System appearance changes · Set the app icon | M6 |

A new entry point is a new row here and a tree in one of those files, plus its failures in
§4 and its rules in §5. A tree that exists in neither place is drift.

## The layering

```
RaccoonDomain  ← RaccoonData  ← Raccoon.app (AppKit)
  models, rules,   every boundary:    windows, views, view models,
  port protocols   URLSession, files,  wiring of ports to rules
  no I/O           Keychain, FSEvents
       ↑
RaccoonTesting     the §9 test implementations of the ports; linked by test targets only,
                   so no fake ships in the app
```

Enforced by `Package.swift`, not by convention: `RaccoonDomain` may import Foundation for
value types (`URL`, `Data`, `Date`) and must not touch `FileManager`, `URLSession`,
`Security` or `CoreServices`. A rule that wants a file reads it through a port.

## The method

The graph is built with the `effect-swift` skill (`.agents/skills/effect-swift/`): A is the
return value, E a typed `throws(E)` with one enum per layer, R the ports a type is
initialised with. Load it before planning a change. Its `references/swift-mechanics.md`
holds the code shapes, including the one case where a `catch` belongs inside the happy path.
