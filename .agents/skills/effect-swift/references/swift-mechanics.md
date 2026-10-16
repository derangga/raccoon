# Swift mechanics

The Swift code the method in `SKILL.md` compiles to. Verified against Swift 6.4
with `-swift-version 6`. Two helpers (`lift`, `retrying`) carry the whole error
channel; if the project already defines equivalents, use those instead.

## Typed throws needs explicit closure annotations

The compiler does not infer a typed error for a closure from its body. Passing
`{ try await http.get(path) }` to a parameter typed `() async throws(E) -> A`
fails with `invalid conversion of thrown error type 'any Error'`, or the type
checker times out on nested closures. Annotate every closure that crosses a
typed-throws parameter:

```swift
{ () async throws(HTTPError) in try await http.get("/orders") }
```

Write `do throws(E) { ... } catch { ... }` with the type spelled out. It makes
`error` inside `catch` the concrete enum, which the exhaustive `switch` needs.

## Lifting errors between layers

Each layer has its own error enum. A lower error enters it as an associated
value, `case transport(HTTPError)`, so the outer switch can still match the
inner case: `.transport(.status(404))`.

```swift
func lift<A, Inner: Error, Outer: Error>(
    _ wrap: (Inner) -> Outer,
    _ body: () async throws(Inner) -> A
) async throws(Outer) -> A {
    do throws(Inner) { return try await body() } catch { throw wrap(error) }
}

func lift<A, Inner: Error, Outer: Error>(
    _ wrap: (Inner) -> Outer,
    _ body: () throws(Inner) -> A
) throws(Outer) -> A {
    do throws(Inner) { return try body() } catch { throw wrap(error) }
}
```

The enum case is the `wrap` function: `lift(LoadOrdersError.transport) { ... }`.

## Retry as a wrapper

```swift
func retrying<A, E: Error>(
    times: Int,
    when isTransient: (E) -> Bool,
    _ body: () async throws(E) -> A
) async throws(E) -> A {
    var attempt = 0
    while true {
        do throws(E) { return try await body() }
        catch where attempt < times && isTransient(error) { attempt += 1 }
    }
}
```

Add backoff with `try? await Task.sleep(for:)` inside the catch when the
dependency needs it. The clock is R when tests must skip the wait.

## A node, end to end

```swift
enum HTTPError: Error, Equatable {
    case offline, timeout, status(Int), cancelled
    var isTransient: Bool { self == .offline || self == .timeout }
}
enum ParseError: Error { case missing(String) }
enum LoadOrdersError: Error { case transport(HTTPError), parse(ParseError) }

protocol HTTPClient: Sendable {
    func get(_ path: String) async throws(HTTPError) -> Data
}

struct LoadOrders: Sendable {
    let http: any HTTPClient                                   // R

    func callAsFunction() async throws(LoadOrdersError) -> [Order] {  // A, E
        let data = try await lift(LoadOrdersError.transport) { () async throws(HTTPError) in
            try await retrying(times: 2, when: \.isTransient) { () async throws(HTTPError) in
                try await http.get("/orders")
            }
        }
        return try lift(LoadOrdersError.parse) { () throws(ParseError) in
            try OrderPage.parse(data)
        }
    }
}
```

The decision point, where the graph's `E:` column becomes code:

```swift
do throws(LoadOrdersError) {
    state = .loaded(try await loadOrders())
} catch {
    switch error {
    case .transport(.cancelled): return
    case .transport(.status(404)): state = .empty
    case .transport(.offline), .transport(.timeout): state = .offline
    case .transport(.status), .parse: state = .failed
    }
}
```

The fake for tests conforms to the same protocol:

```swift
struct MemoryHTTP: HTTPClient {
    let result: Result<Data, HTTPError>
    func get(_ path: String) async throws(HTTPError) -> Data { try result.get() }
}
```

## Where a `do`/`catch` belongs inside the body

Only when two calls in the same body throw the same error type and the graph
gives them opposite treatment. Example: a failed history save escapes with a
log, while a failed send propagates. One switch at the decision point cannot
tell which call threw. Handle the escaping one inline, as narrowly as the call
itself, and leave the rest of the body as the happy path:

```swift
let response = try await lift(SendError.transport) { () async throws(HTTPError) in
    try await http.send(request)
}
do throws(StoreError) { try await store.saveHistory(response) }
catch { log.warning("history not saved: \(error)") }   // graph: E: .io -> escape, log
return response
```

The alternative, when both must reach the switch, is two distinct cases in the
outer enum (`.send(HTTPError)` and `.history(StoreError)`), which keeps the body
free of `do`/`catch`. Prefer that whenever the caller decides.

## Typed errors in streams

`AsyncThrowingStream<A, E>` only has initializers for `E == any Error`, so it
erases the error channel. Two shapes keep E typed:

- Return `some AsyncSequence<A, E>` from a type you write, conforming to
  `AsyncSequence` with `typealias Failure = E` and a `next()` that is
  `throws(E)`. Use it for paginated pulls, where each `next()` is one request.
- Yield `Result<A, E>` through an `AsyncStream<Result<A, E>>` when the producer
  is callback-based. The consumer's `switch` over `.failure` is the E
  enumeration, exhaustive like any other.

Release producer resources in `continuation.onTermination`, which runs on
finish, on cancellation, and when the consumer drops the stream.
