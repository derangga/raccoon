# §2 A — Variables

Globals, Environments, the Active Environment, highlighting, and resolution. Milestone M5.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

## Resolution

```
-> VariableScope(active: Environment?, globals: Globals, secrets)   pure
  -> enabled Globals entries
  -> enabled Active Environment entries, overriding by name
  -> .secret entries take their value from `secrets: [VariableName: String]`
     a secret with no Keychain value is absent, so it is an Undefined Variable
-> VariableResolver.resolve(definition, scope)                      pure
  -> drop Disabled Rows
  -> substitute {{name}} in: url, params, headers, cookies, body text and
     form/multipart values, Auth fields, multipart file paths
  -> any name not in scope -> collect it, keep going
  -> collected non-empty -> throw ResolveError.undefined(all of them)
  -> Auth -> an Authorization header appended to headers, auth = .none
     Basic: base64 of user:password; Bearer: `Bearer <token>`
  -> build the URL: base + percent-encoded params    E: ResolveError.invalidURL
  -> ResolvedRequest
```

**Substitution is one pass and not recursive.** A value of `{{other}}` is sent as the text
`{{other}}`. Recursive resolution needs cycle detection and an answer for `a → b → a`, and
nothing in the design session asked for nested Variables.

**`{{ name }}` with spaces is the same as `{{name}}`.** Postman accepts both, and pasted
requests carry both.

**`{{…}}` whose inside is not a `VariableName` is not a Variable.** `{{$guid}}` or `{{a b}}` is
sent as written and not highlighted, because `ResolveError.undefined` can only name a
`VariableName`.

**An Active Environment secret with no Keychain value does not fall back to Globals.** It is
undefined. Falling back would send a Globals token, often a dev one, to the Environment the
user picked.

**Every Undefined Variable is reported, not the first.** A send that fails three times to
reveal three missing names is three round trips the user did not need.

## Entry points

```
-> pickActiveEnvironment(name?)                  the toolbar pop-up, ⌃E
  -> window.activeEnvironment = name             app-wide, not per Tab
  -> SessionWriter.schedule()
  -> every visible highlight pass re-runs        the selected Tab only (tabs.md)
```

**The Active Environment is per window, and there is one window.** It is not per Tab.
Switching to Prod must change what every Tab sends, because a Tab that silently stayed on Dev
is the mistake that sends a test payment to production, and the reverse.

```
-> editVariable(scope, entry)                    the Environments sheet
  -> plain  -> EnvironmentFile.encode -> DataFolderStore.write        E: unwritable
  -> secret -> SecretStore.set(environment, name, value) on leaving the secure field   E: SecretError
               -> escape: "Not saved. …" under the row; the file holds no value, so it is never touched
               file stores { "name": …, "secret": true } and no value
  -> scope rebuilt, highlight pass re-runs
```

```
-> editVariable also covers, in the sheet:
  -> name   -> VariableEdit.name(text, entries, replacing)    pure   E: invalidName / duplicate
               -> escape: the old name stays, a red line under the row, nothing written
  -> enable -> EnvironmentFile.encode -> write, at once
  -> delete -> write without the row, then SecretStore.delete if it was a secret
               E: unwritable -> escape: "Not saved. …" under the row   SecretError -> escape: log
  -> every write goes through the window (WriteLedger), never straight to the store, so the
     scan, the picker and the highlights follow and FolderWatch drops the echo

-> newEnvironment / renameEnvironment / deleteEnvironment                 the sheet's + , name field, −
  -> new:    environments/New Environment.json, empty (" 2", " 3"… when taken, ignoring case)
  -> rename: sanitised file name; E: nameTaken -> escape: reverts, red line under the field
             -> SecretStore get(old) / set(new) for every secret   E: SecretError -> copies undone,
                escape: red line, nothing changed
             -> move the file                                      E: unwritable -> copies undone
             -> SecretStore.delete(old)                            E: SecretError -> escape: log
             -> the Active Environment follows the new name
  -> delete: the file to the Trash; its Keychain items stay; No Environment if it was active

-> markSecret(entry) / unmarkSecret(entry)                                  the lock button on a row
  -> mark:   SecretStore.set(value), then rewrite the file without it
             E: SecretError -> escape: the row and the file stay as they were, a red line under the row
             E: unwritable  -> escape: the Keychain item is removed again, red line
             an empty value stores nothing and deletes any old item of that name (a missing item is no error;
             E: SecretError -> as for set), so the file gets "secret": true and "Not in the Keychain" until typed
  -> unmark: SecretStore.get (a secret the store cannot give becomes an empty value),
             rewrite the file with the value, then SecretStore.delete (not when nothing was read)
             E: unwritable  -> escape: red line, the Keychain item stays
             E: SecretError on delete -> escape: log

-> secretsMissing(set)                           when the sheet loads a set's rows
  -> SecretStore.get(environment, name) once per .secret entry   E: nil or SecretError -> "Not in the Keychain"
     only whether it answered is kept in the sheet, never the value or its length
```

**The Keychain write happens before the file write when marking.** If the order were reversed
and the Keychain write failed, the value would be gone from both. Unmarking reverses the order
for the same reason.

```
-> highlight(text, scope)                        every keystroke in a field that takes {{}}
  -> VariableTokens.ranges(text)                 pure: every {{…}} range and its name
  -> each range: defined -> accent, undefined -> red underline
  -> hover -> popover with the resolved value, or "Secret" for a .secret entry
```

```
-> hover(point)                                  pointer moves over a field that takes {{}}
  -> VariableHover.hit(point, TextLayout)        pure geometry: the token under the pointer, if any
     R: the field's TextKit 1 layout (editor while edited, the field's string laid out where
        its cell draws it at rest, the raw body's text view)
     -> VariableTokens.ranges over 512 units either side of the nearest character
  -> VariableKinds.tooltip(for: name)            pure: .defined(name, source, value) | .secret(name,
                                                 source) | .undefined(name, environment?)
     R: the kinds the field already holds (names, sources, plain values); no SecretStore
  -> VariableTooltipPanel.show                   after NSInitialToolTipDelay, at once while one is shown
     R: one shared borderless NSPanel (key only once its value is clicked, never main), a child
        of the field's window; a local NSEvent monitor for key, click and scroll, only while
        shown; `onReveal`, set at the composition root
     -> the value in a box five lines tall at most, then scrolling; source chip; the link
     E: pointer leaves the token -> hide after 0.3 s unless it is over the panel
     E: pointer leaves the panel; a key (⌘ inside the panel excepted); a click or scroll
        outside it; the field leaves its window -> hide (monitor removed with it)
-> reveal(name)                                  "Variables in request" in the popover
  -> panel hides
  -> onReveal(name)                              R: the app delegate
     -> the inspector opens (docked or overlaid), on Variables
     -> variablesPane selects the row of `name` that resolves and scrolls to it
```

A secret's popover says "Secret" and its source and nothing else: `VariableKinds` keeps no
secret value, so nothing a hover can reach holds one.

```
-> suggest(text, caret)                          typing in a field that takes {{}}
  -> VariableCompletion.query(text, caret)       pure: the `{{` + name characters that end at
                                                 the caret, if any; nil closes the list
  -> VariableKinds.suggestions(matching: prefix) pure: enabled names in scope, case-insensitive
                                                 substring, prefix matches first, then by name;
                                                 each with its source and whether it is secret
     R: the kinds the field already holds; no SecretStore
     empty -> no list
  -> VariableSuggestionPanel.show                R: one shared borderless NSPanel that cannot
                                                 become key, a child of the field's window
     -> ↑ ↓ move the selection; Return, Tab or a click inserts; Esc closes
        R: the editor's doCommand(by:), consumed only while the list is open
     E: caret leaves the `{{name`, a character that is not in a name, the field loses focus,
        a click outside the list, a scroll, ⌘ shortcut -> close
-> accept(name)
  -> VariableCompletion.insertion(name, query, text)   pure: replaces the typed name, any name
                                                 characters after the caret and a `}}` already
                                                 there with `name}}`; caret after the `}}`
  -> NSTextView.insertText(_, replacementRange:) one undo step; the field's highlight pass runs
```

**The list opens on typing, not on caret moves.** Clicking into an existing `{{na` does not
open it; only typing does. While it is open, moving the caret refilters it or closes it.

**A file that does not decode is not a Variable source and is never written.** The window keeps
it with its reason (`brokenEnvironments`, `globalsProblem`), the sheet lists it read-only, and
`write` refuses it, so no edit can overwrite what the user can still fix by hand.

## The Variables pane

```
-> variablesPane(tab, scope)                     the inspector, when it is open
  -> VariablesPane(definition, active, globals)  pure: R none
     -> VariableTokens.ranges over the Tab's enabled parts: which names it uses, and where
        (URL, Params, Headers, Body, Auth, Cookies); Disabled Rows are not sent, so not counted
     -> groups, in order:
        -> names the Tab uses that are not in scope -> "Not defined", with where
        -> the Active Environment's enabled entries, the ones the Tab uses first
        -> Globals' enabled entries; one an Environment overrides is shown struck out
  -> a .secret entry shows "Secret", never a value    no Keychain read
  -> re-renders when the selected Tab's definition, the Environments, Globals or the Active
     Environment change
  -> the selected name (reveal above): its resolving row, highlighted; a click on a row selects it
  -> Edit Environments… -> the Environments sheet     names, enabling, secrets, new and deleted

-> editPaneValue(row, text)                      one click on a value cell, then Return or click away
  -> unchanged -> nothing
  -> plain     -> WindowModel.setValue(text, at: row.index, in: set)       R: the window (WriteLedger)
                  -> EnvironmentFile.encode -> DataFolderStore.write       E: StoreError -> escape:
                     "Not saved. <reason>." under the row, the cell shows the file's value again
  -> secret    -> WindowModel.setSecretValue(text, at: row.index, in: set)  empty -> nothing
                  -> SecretStore.set                                       E: SecretError -> escape:
                     "Not saved. The Keychain refused the write (OSStatus …)." under the row
  -> undefined -> WindowModel.define(name, text, in: active ?? Globals)    appended, enabled
                  -> write                                                 E: StoreError -> escape
  -> the scan applies the write, so the pane, highlights and picker follow; FolderWatch drops the echo
```

**The pane edits values through the window, not around it.** The same `write` and
`setSecretValue` the Environments sheet calls do the work, so there is still one path for the
Keychain-then-file order and for refusing a file that does not decode. The pane edits values
only; names, enabling, marking secrets and deleting stay in the sheet, which also reaches an
Environment that is not active.
