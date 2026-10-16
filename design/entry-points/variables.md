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
  -> build the URL: base + percent-encoded params                   E: invalidURL
  -> ResolvedRequest
```

**Substitution is one pass and not recursive.** A value of `{{other}}` is sent as the text
`{{other}}`. Recursive resolution needs cycle detection and an answer for `a → b → a`, and
nothing in the design session asked for nested Variables.

**`{{ name }}` with spaces is the same as `{{name}}`.** Postman accepts both, and pasted
requests carry both.

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
  -> secret -> SecretStore.set(environment, name, value)              E: SecretError
               file stores { "name": …, "secret": true } and no value
  -> scope rebuilt, highlight pass re-runs
```

```
-> markSecret(entry) / unmarkSecret(entry)
  -> mark:   SecretStore.set(value), then rewrite the file without it
  -> unmark: rewrite the file with the value, then SecretStore.delete
```

**The Keychain write happens before the file write when marking.** If the order were reversed
and the Keychain write failed, the value would be gone from both. Unmarking reverses the order
for the same reason.

```
-> highlight(text, scope)                        every keystroke in a field that takes {{}}
  -> VariableTokens.ranges(text)                 pure: every {{…}} range and its name
  -> each range: defined -> accent, undefined -> red underline
  -> hover -> tooltip with the resolved value, or "Secret" for a .secret entry
```

## The Variables pane

```
-> variablesPane(tab, scope)                     the inspector, when it is open
  -> VariableTokens.ranges over the Tab          pure: which names this Tab uses, and where
  -> groups, in order:
     -> names the Tab uses that are not in scope -> "Not defined", with where (URL, Headers…)
     -> the Active Environment's enabled entries, the ones the Tab uses first
     -> Globals' enabled entries; one an Environment overrides is shown struck out
  -> a .secret entry shows "Secret", never a value    no Keychain read
  -> Edit Environments… -> the Environments sheet     the only place Variables are edited
```

**Read-only on purpose.** Editing stays in the Environments sheet so there is one path for
the Keychain-then-file order above, and so a Variable of an Environment that is not active
can still be reached.
