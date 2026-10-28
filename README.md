# Raccoon

Raccoon is a native macOS HTTP client written in Swift and AppKit, in the style of Postman. It turns what you type or paste (a URL, a curl command, a Postman export) into exactly one HTTP request, sends it, and shows the response. It does not add or hide anything from the request.

The code is split into three modules that depend in one direction, enforced by `Package.swift`:

- `RaccoonDomain` holds models, rules and port protocols. It does no I/O.
- `RaccoonData` implements every boundary: files, the network, the keychain.
- `Raccoon` is the AppKit app.

`RaccoonTesting` holds test implementations of the ports and is linked by test targets only.

## Requirements

- macOS 15 or later
- Swift 6.2 or later (the manifest uses `swift-tools-version: 6.2`). Xcode ships it, or install a toolchain from swift.org.

## Development

1. Clone the repository and `cd` into it.
2. Build all targets:

   ```sh
   swift build
   ```

3. Launch the app:

   ```sh
   swift run Raccoon
   ```

4. Run the tests:

   ```sh
   swift test                              # every test target
   swift test --filter LayeringTests       # one suite
   ```

## Where to read next

- [DESIGN.md](./DESIGN.md) indexes the design, one file per question under `design/`.
- [CONTEXT.md](./CONTEXT.md) defines the vocabulary used in type names and UI strings.
- [CLAUDE.md](./CLAUDE.md) describes how work on this repository is done.
