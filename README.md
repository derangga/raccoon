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

   `swift run` starts a bare executable, so the Dock shows a generic icon. See [Release app](#release-app) for the app with its icon.

4. Run the tests:

   ```sh
   swift test                              # every test target
   swift test --filter LayeringTests       # one suite
   ```

## Release app

1. Build `.build/Raccoon.app`. The script does a release build, adds the icon as `AppIcon.icns` and ad-hoc signs the app:

   ```sh
   scripts/make-app.sh
   ```

2. Quit Raccoon if it's running, then copy the app to `/Applications`:

   ```sh
   rm -rf /Applications/Raccoon.app
   ditto .build/Raccoon.app /Applications/Raccoon.app
   ```

   `ditto` keeps the bundle's code signature, permissions and extended attributes. It merges into a folder that already exists, so remove the old copy first or files from it stay behind.

3. Open it from Launchpad, Spotlight or `open /Applications/Raccoon.app`.

The app is ad-hoc signed, so it runs on the Mac that built it. Another Mac needs a copy signed with a Developer ID and notarized.

The app and `swift run` share one set of settings (the UserDefaults domain `Raccoon`), so both open the same Data Folder, Workspaces and Theme.

## Where to read next

- [DESIGN.md](./DESIGN.md) indexes the design, one file per question under `design/`.
- [CONTEXT.md](./CONTEXT.md) defines the vocabulary used in type names and UI strings.
- [CLAUDE.md](./CLAUDE.md) describes how work on this repository is done.
