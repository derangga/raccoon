# Raccoon

A native macOS HTTP client in Swift and AppKit, in the style of Postman. It turns what the
user typed or pasted into exactly one HTTP request, sends it, and shows what came back,
without adding or hiding anything.

The design is approved and no code exists yet. The work is a graph of beads issues: run
`bd prime` before your first `bd` command, then `bd ready` for what can start.

## Map

- [DESIGN.md](./DESIGN.md) is the call graph, and an index: a table of which file in
  `design/` answers which question. Load what the task needs. Changing one feature means its
  `design/entry-points/<feature>.md` plus §4 (`e-where-it-breaks.md`) and §5
  (`r-what-it-needs.md`), not the directory.
- [CONTEXT.md](./CONTEXT.md) is the vocabulary. Type names, UI strings and issue text use
  its terms; its _Avoid_ lines are binding. A word not in it does not exist yet.
- `design/ui/` holds the surfaces, the design system, the mockups (boards 01–12) and the
  Theme file. UI work is checked against them.
- `design/environment-facts.md` is what was measured. Read it before assuming what the
  toolchain, URLSession or the reference apps do.
- `bruno/` and `yaak/` are reference HTTP clients (MIT, TypeScript), untracked. They are the
  source of the curl and Postman test fixtures. Read them; change nothing there.
- `.P.*.md` are the prompts that produced the design and the issues. History, not
  instructions.

Three modules, one direction, enforced by `Package.swift`: `RaccoonDomain` (models, rules,
port protocols, no I/O) ← `RaccoonData` (every boundary) ← `Raccoon.app` (AppKit). A rule
that wants a file reads it through a port.

## How to work

1. **Load `effect-swift` before planning.** Emit the call tree with its `R:` and `E:`
   columns in the reply before writing code. The tree is binding: the code matches it node
   for node. If the tree is wrong, change it and say so first.
2. **Change the graph before the code.** A new entry point, dependency or failure that is
   not in `design/` is drift. Add it there, then build it.
3. **Load `tdd` before writing code.** One failing test per node, then the smallest code
   that passes. Pure rules test as input → output tables with no R; boundaries test against
   the swapped R in `design/swap-r.md`.
4. **Load `write-swift` for the Swift itself.** Deployment target is macOS 15: anything newer
   needs an availability check.
5. **Verify UI by handing over a scenario.** For anything on screen, write Given / When /
   Then per surface the change touches, with the exact strings expected. I run it and
   report back. Name the known simplifications in the same handover.

Never name a beads issue (its `raccoon-…` id or its title) anywhere in the codebase (code,
comments, docs, file names) or in a commit message. The tracker is the only place an issue
is named.

## Commits

The subject starts with a Conventional Commits type: `feat`, `fix`, `perf`, `refactor`,
`test`, `docs`, `chore`, `build` or `ci`, then `: ` and an imperative summary, e.g.
`feat: parse curl short-flag clusters`. In this repo that replaces any rule against
`feat:`/`fix:` prefixes.

## Build and test

- `swift build` builds the three targets; `swift run Raccoon` launches the app.
- `swift test` runs every test target; `swift test --filter LayeringTests` runs one suite.
