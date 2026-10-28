# §2 A — Theme

Picking a Theme and its Flavors, and following the system appearance. Milestone M6.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

```
-> launch
  -> ThemeCatalog.load(bundle)                   boundary, but our own bytes
                                                 E: undecodable -> DIE, see §4
  -> ThemeChoice from UserDefaults               missing or unknown name ->
                                                 Catppuccin, Latte / Mocha
```

```
-> package                                       scripts/make-app.sh
  -> swift build -c release                      E: fails -> stop
  -> iconutil AppIcon.png -> AppIcon.icns        E: PNG missing -> stop
  -> Raccoon.app: binary, Raccoon_Raccoon.bundle, AppIcon.icns, Info.plist
  -> codesign --sign -                           E: fails -> stop
-> the Dock, ⌘Tab, Finder                        read CFBundleIconFile, in their own processes
-> an alert                                      AppKit loads the icon from the bundle
```

The icon is `design/ui/assets/icon/AppIcon.png`, built by `design/ui/assets/build.py` from the
untouched source next to it. Only `scripts/make-app.sh` reads it: it writes `AppIcon.icns` into
`Raccoon.app/Contents/Resources` and names it in Info.plist. The app never loads the icon at
launch, because an icon set through `NSApp.applicationIconImage` is decoded and kept in
Raccoon's own memory (32 MB for the 1024 pt PNG, measured). `swift run Raccoon` runs a bare
executable with no bundle, so it shows the generic executable icon.

Info.plist's `CFBundleIdentifier` is `Raccoon`, the UserDefaults domain `swift run` already
uses, so the `.app` and `swift run` share the Data Folder, the Workspaces and the ThemeChoice.

```
-> pickTheme(name) · pickFlavor(light: name) · pickFlavor(dark: name)   View ▸ Theme menu
  -> ThemeChoice updated, written to UserDefaults
  -> apply()
```

```
-> appearanceChanged                             NSApp.effectiveAppearance, KVO
  -> apply()
```

```
-> apply()
  -> flavor = choice.flavor(for: effectiveAppearance)    pure
  -> ThemeEnvironment.flavor = flavor                    one observable value, set only
                                                         when it differs
     -> editors, response viewer, tab strip re-read their colours
```

**Every colour read re-runs when the Flavor changes, one way.** A colour is read either
inside a view's `render()`, which already re-runs on any observed change, or inside
`theme.paint(owner) { owner, theme in … }`, which runs now and again on every Flavor
change while `owner` lives. A view that draws itself paints `needsDisplay = true`; a
coloured text storage or table recolours inside its paint. No view reads a colour once at
build time and keeps it.

**Content areas follow the Theme, chrome follows the system.** The sidebar, toolbar and
window use native materials (design session, Theme Q1). Because the light and dark Flavors
switch with the system appearance, content and chrome always agree on light or dark.

**Colours are named tokens, not hard-coded per view.** A Flavor maps tokens such as
`background`, `text`, `accent`, `jsonKey`, `jsonString`, `variableDefined` and
`variableUndefined` to colours. A view asks for a token, so a new Theme is a new JSON file
with the same keys, and a missing key is caught by a test over every bundled Flavor.
