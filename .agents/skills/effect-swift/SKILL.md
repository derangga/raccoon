---
name: effect-swift
description: The design pass that runs before Swift code. Name the shapes, draw the call graph, annotate A/E/R, then emit it. Use when designing a Swift function or workflow, deciding retry/escape/die for a typed `throws(E)`, choosing one value vs AsyncSequence, parsing untrusted data at a boundary, injecting dependencies, or tying acquire/release to a scope; for interface work reach references/design-graph.md.
---

# Effect Swift

```
X → Graph → func node(...) async throws(E) -> A      // R = what the type stores
│              │                         │       │
│              │                         │       └─ what flows through nodes  (§2)
│              │                         └───────── where the graph breaks    (§4)
│              └─ nodes = functions, edges = data flow
│                 R = the dependencies `init` demands (§5)
│
└─ the problem: what you're trying to build

§1  Shapes       the nouns: structs, ID newtypes, enums, error enums
§2  A            happy path as call graph
§3  Cardinality  one value (async func) or many (AsyncSequence)
§4  E            break points: retry, escape, die
§5  R            dependencies: `init` is the compile-time proof
§6  Boundary     parse: Data / Any / String → trusted type at edges
§7  Behavior     wrappers change how a node runs, never what it does
§8  Scope        acquire/release tied to a lexical or task scope
§9  Test         swap R, same graph shape
§10 Code         `do` body = A, `catch` switch = E
```

This is the Effect `A, E, R` method written in plain Swift. It needs no
framework: the language already has the three channels. A is the return type, E
is the typed `throws(E)`, and R is the set of stored dependencies a type demands
in its `init`. The method fits any Swift target: app, CLI, server or package.

Read the problem. Draw the data flow as a call graph. Write code that IS the
graph. If the code doesn't match the graph, something is wrong.

For how to write the Swift itself (concurrency, Sendable, generics, Swift
Testing), use the `write-swift` skill. For the error-channel mechanics this
method depends on (lifting errors between layers, retry wrappers, typed streams,
typed-throws inference), read [references/swift-mechanics.md](references/swift-mechanics.md)
before writing the code.

## How much of this to run

The ten sections are not equal. **Four carry the method.** Run them on every
change that writes code, however small:

| §   | always run                  | because                                                              |
| --- | --------------------------- | -------------------------------------------------------------------- |
| §4  | **E**, retry/escape/die     | the decision code skips by default; everything becomes catch-and-log |
| §5  | **R**, what it needs        | the difference between a dependency and a hidden one                 |
| §9  | **swap R**                  | you can see whether it is testable before writing a test             |
| §10 | **do = A, catch switch = E** | the only one you can check by looking at the finished code          |

Two are prerequisites. You cannot annotate a graph you have not drawn, but
drawing it is rarely where the insight is. Do them fast:

- **§1 shapes** and **§2 A** are usually already answered by the existing code.

Four fire on a trigger. No trigger, skip it:

| §   | fires when                                       |
| --- | ------------------------------------------------ |
| §3  | a node might emit more than once, or over time   |
| §6  | untrusted data crosses into the graph            |
| §7  | a node needs retry, timeout, logging, or caching |
| §8  | a node acquires something that must be released  |

**This is a priority order, not permission to skip.** Skipping one of those four
is a claim that its trigger is absent. If you cannot say why §6 does not apply,
it applies.

### Depth per change

| the change                                           | run                                                                   |
| ---------------------------------------------------- | --------------------------------------------------------------------- |
| introduces shapes or failure modes that didn't exist | §1–§2 to draw it, the four to annotate it, plus triggers              |
| only adds call sites for shapes that already exist   | the four, §1–§2 are already answered by the code                      |
| doesn't touch data flow, only what a person is shown | `references/design-graph.md`, the same method turned on the interface |

Torn between two depths, run the deeper one. The pass is cheap; a graph
discovered halfway through the code is not.

A host project may map these onto its own triage vocabulary; the mapping belongs
in that project's instructions, not here.

## 1. Name the shapes

What are the things? Before drawing a graph, define the domain language. In
Swift every shape is a value type unless identity is the point.

- **Records.** `struct`s that flow through nodes. A User, a Request, an Order.
  `Sendable`, `Equatable` where tests compare them.
- **IDs.** A newtype per identity: `struct OrderID: Hashable, Sendable { let
  rawValue: String }`. Two IDs of different things never share a type, so the
  compiler rejects swapping them.
- **Variants.** An `enum` with associated values for each internal state. A
  step is `.continue(State)` or `.finished(Result)`. A status is `.pending`,
  `.active`, or `.cancelled`. One enum replaces a cluster of optionals and
  bools that can disagree.
- **Errors.** One `enum ...Error: Error` per layer, each case named for a
  failure mode and carrying its context as associated values:
  `case notFound(OrderID)`, `case status(Int, body: Data)`. A failure is a
  case, so a `switch` can enumerate every one.

These are the nouns. The graph is the verbs. You cannot draw the graph until you
know what flows through it.

## 2. Think A first

Map the happy path as a call graph before writing any code. What goes in, what
comes out, what transforms happen in between. This graph IS the program
structure. The code follows it, not the other way round.

Each node becomes one function or method whose return type is the A on that
node. A node that returns `A?` has hidden a failure in A: the `nil` carries no
reason. Return `A` and put the reason in E.

## 3. One or many?

Is each node one-shot or a flow?

- **One value.** The node runs, produces A, done. This is
  `func f() async throws(E) -> A`.
- **Many values over time.** The node emits A repeatedly. Events,
  subscriptions, paginated pulls, file watchers. This is
  `some AsyncSequence<A, E>`. To keep E typed, read the stream section in
  `references/swift-mechanics.md`: `AsyncThrowingStream` erases E to
  `any Error`.
- **Time-bounded.** The result is valid for a window. Cache it in an `actor`,
  and share one in-flight `Task` between concurrent callers for the same key.

Same three channels in all cases, different cardinality. Mark it on the graph so
the code matches.

## 4. Think E second

Mark where the graph can break. Each break point is one of three things:

- **Retry.** Transient failure, try again. Timeout, offline, rate limit,
  connection reset. Give the error enum an `isTransient` property so the retry
  wrapper (§7) asks the error, not the call site.
- **Escape hatch.** Recoverable, return an alternative. Fallback value, cached
  result, default, empty state. `try?` is an escape that discards the reason.
  Use it only where the graph marks escape-to-default and no caller needs the
  reason.
- **Die.** A bug in your own code, not a failure of the world. The program
  assumed something that turned out false. Use `preconditionFailure("why")`.
  This is NOT a case in E, and a malformed server payload is not a die: the
  world sent it, so it is E.

Errors are VALUES in the E channel until you truly cannot handle them. Each
function declares `throws(E)` with its own layer's enum, never untyped `throws`.
At each node you decide: retry, escape, or let it propagate. Only die when the
program's assumptions are violated.

Cancellation is a fourth mark on the graph, and it is not a failure. Annotate it
`cancel -> propagate`: no retry, no error UI, no log at error level. A layer
that observes cancellation (`CancellationError`, `URLError.cancelled`) maps it
to a dedicated `.cancelled` case so the top-level switch can skip it.

## 5. Think R third

Mark what each node needs to exist. "We cannot do X if we don't have Y."

In Swift, R is the stored properties of the type that owns the node, and the
`init` that demands them is the compile-time proof. A node whose type has no
stored dependencies is a pure function. A missing dependency is a compile error
at the construction site, naming the parameter.

- Every dependency arrives through `init`: an HTTP client, a store, a clock, a
  UUID source, a file system, settings. Declare it as a protocol
  (`let http: any HTTPClient`) or a struct of closures.
- A singleton reached from inside a node (`URLSession.shared`,
  `FileManager.default`, `UserDefaults.standard`, `Date()`, `UUID()`) is a
  hidden R. It belongs at the composition root, passed in.
- The composition root is the single place that builds the production graph:
  the `@main` entry, the app's root, the server's bootstrap. R resolves to
  concrete types there, and nowhere else.

## 6. Trust at boundary

Where does untrusted data enter the graph? HTTP responses, file reads, the
pasteboard, environment variables, `UserDefaults`, user input, URLs, third-party
payloads.

Parse at the edges. The boundary type is a `Decodable` DTO that mirrors the wire
exactly; a `static func parse(_:) throws(ParseError) -> Domain` turns it into
the domain shape from §1 and enforces every constraint (non-empty, in range,
known enum value). One definition gives the type, the validator and the
transform. The DTO never leaves the file that parses it.

Trust nothing at the boundary. Trust everything inside. The boundary is the only
place you parse; after that the types guarantee shape, so inner code carries no
`guard` re-checking what parse already proved.

## 7. Layer behavior

What wraps a node without changing what it does? Retry policies, timeouts,
logging, signposts, caching.

These wrap the call as higher-order functions (`retrying(times:when:_:)`,
`withTimeout`) or as a decorator type that conforms to the same protocol as the
dependency it wraps (`struct LoggingHTTPClient: HTTPClient`). The node's own
body holds no retry loop and no logging. Each wrapper can be added or removed on
its own: the graph says WHAT happens, the wrappers say HOW it behaves under
pressure.

## 8. Scope resources

What nodes acquire something that must be released? Connections, file handles,
security-scoped URLs, observers, subscriptions, child processes, tasks.

Tie release to a scope the compiler sees:

- `defer` releases at the end of the lexical scope, on return and on throw.
- A `with...` function (`withOpenFile(at:) { handle in ... }`) owns acquire and
  release, so the caller never holds the resource past the closure.
- `withTaskGroup` / `async let` bind child work to the parent; cancelling the
  parent cancels them. An unstructured `Task {}` is a leak unless something
  stores it and cancels it.
- An `AsyncStream` producer releases in `continuation.onTermination`.
- `~Copyable` with `deinit` gives a resource exactly one owner.

Cleanup is structural, even on error, even on cancellation. A release that a
caller must remember to call is a TODO.

## 9. Swap R to prove it

The call graph doesn't change between production and tests. Only R changes.

The test constructs the same type through the same `init` with in-memory
dependencies: a fake HTTP client returning fixed `Data`, a fixed clock, an
in-memory store. Same graph shape, same A flowing through, same E possible,
different values behind R. Each `E:` annotation on the graph becomes one test
that makes the fake fail that way and asserts with
`#expect(throws: LoadOrdersError.notFound(id))`.

If the graph can't run with a test R, the design has hidden dependencies. If you
have to fake the world to test one node, the node is doing too much.

## 10. `do` body is A, `catch` switch is E

§2 and §4 map directly onto code structure:

- **The node's function body** is the happy path. One `try` per node of the
  graph, top to bottom, with lower-layer errors lifted into this layer's enum on
  the same line. No `do`/`catch` inside.
- **The `do throws(E) { } catch { switch error { } }` at the decision point** is
  the complete E enumeration. Read the actual enum of every call before writing
  it. The `switch` names every case, with no `default:`, so a new failure mode
  is a compile error at every place that must decide about it.

This is not a stylistic preference. Error handling inside the body tangles the A
path and the E path, and the happy path stops being readable. The body IS the
call graph from §2; the switch IS the error annotation from §4.

The mechanics (lifting errors between layers, the one case where a `do`/`catch`
belongs inside the body, closure annotations typed throws needs) are in
`references/swift-mechanics.md`. This section fixes only _why_ the split exists.

## Emit the graph before the code

The answers get **written into the reply** before any code exists. A graph that
was only thought is unverifiable. Neither you nor the reader can tell a design
pass from a claim of one.

Notation: steps at the left margin prefixed `->`, nodes indented beneath the step
they belong to, `R:` and `E:` riding the node line they annotate. Horizontal
chains (`F1(A) -> F2(A) -> F3(A)`) are banned. They wrap badly in a terminal.
The graph grows down the page, not across it.

```
shapes: OrderID (newtype), Order, OrderPage (DTO),
        LoadOrdersError { transport(HTTPError), parse(ParseError), cancelled }

-> load order list
  -> http.get("/orders")         R: HTTPClient   E: .transport(.timeout) -> retry x2
                                                 E: .transport(.status(404)) -> escape: empty
                                                 E: .cancelled -> propagate
  -> OrderPage.parse(data)                       E: .parse -> escape: error state
-> render
  -> list surface                                E: .transport(.offline) -> escape: offline banner
```

The sketch is what the first failing test asserts against. The `E:` column
enumerates the failure tests, the shapes give the parse tests. It lives in the
reply only; never commit it as a comment header, where it rots the moment the
code moves.

### Call graphs of existing code

**One notation, two uses.** The same `->` sketch traces code that already
exists: architecture summaries, project overviews, explaining a flow. Keep the
`R:` and `E:` columns: a bare tree of names says only what calls what, while the
annotations say what each node needs and how it breaks.

Production and tests get separate sections when they differ. The contrast is §9
made visible, the same graph shape with a different R behind it:

```
production

-> send request                 R: RequestSender
  -> RequestSender.send         R: HTTPClient(URLSession)  E: .transport -> surface
    -> Store.saveHistory        R: Store(FileSystem)       E: .io -> escape, log
```

```
tests: same graph, R swapped

-> send request                 R: RequestSender
  -> RequestSender.send         R: HTTPClient(MemoryHTTP)
    -> Store.saveHistory        R: Store(MemoryFileSystem)
```

If the two graphs differ by anything except what sits behind `R:`, the design
has a hidden dependency. That is §9 failing, reported as a drawing.

Plain text only, no rendered diagrams.

## The Pipeline

```
PROBLEM
  -> "What are the shapes?"                         -> structs, ID newtypes, enums, error enums
  -> "What is the happy path?"                      -> draw the call graph (A)
  -> "Is each node one-shot or a flow?"             -> async func or AsyncSequence
  -> "Where can it break?"                          -> annotate throws(E) cases on the graph
  -> "What does each node need?"                    -> annotate R; it becomes the init
  -> "Where does untrusted data enter?"             -> parse DTO → domain at the edge
  -> "What wraps nodes without changing them?"      -> wrapper function or decorator
  -> "What resources need cleanup?"                 -> defer, with..., structured tasks
  -> "Can I swap R and the graph still works?"      -> same init, in-memory dependencies
  -> "Does my code separate A from E structurally?" -> body = A, catch switch = E
  -> CODE                                           -> the code IS the graph
```

**If the code doesn't match the call graph, the implementation is wrong.**
