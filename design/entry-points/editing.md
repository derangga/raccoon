# §2 A — Editing

The URL bar, the Params table, Disabled Rows and Body Types. Milestone M1.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

## The URL bar and the Params table

The Params table is the source of truth for the query string (shapes.md). The URL bar shows
`url` plus the enabled params, and typing in it is parsed back into both.

```
-> typeInURLBar(text)                            every keystroke
  -> URLText.split(text)                         pure        R: none
     -> (base, [query pairs])                    split at the first `?`, pairs at `&`,
                                                 name and value at the first `=`
  -> Params.merge(pairs, into: params)           pure
     -> enabled rows replaced by the typed pairs, in order
     -> Disabled Rows kept, at their old index
  -> definition.url = base
  -> PathVariables.prune(pathVariables, to: url) pure: a value whose `:name` left the URL goes;
                                                 same undo step as the text edit
  -> message.afterURLEdit                        pure: a note goes, an error stays
```

The URL field is not rewritten while the user types in it: the typed text is the source until
editing ends, then it shows `URLText.join` again, so a cursor never jumps under a keystroke.

**Disabled Rows survive typing in the URL bar.** They are not in the text, so the text cannot
delete them. Without this rule, toggling a param off and then fixing a typo in the host would
silently lose the param.

**`{{name}}` passes through untouched.** `URLText.split` does not percent-decode inside
`{{…}}`, so `?id={{user_id}}` stays a Variable reference and not `%7B%7Buser_id%7D%7D`.

**Values are stored decoded and encoded once, at send.** Typing `?q=a%20b` stores `a b`.
`VariableResolver` builds the final URL with `URLComponents.percentEncodedQueryItems` after
substitution, so a Variable whose value holds `&` is encoded and cannot split into two params.

**What the URL bar shows is what is sent.** `URLText.join` and the resolver encode a value the
same way: only what a query cannot hold, plus `&` (and `=` in a name). `+` stays `+`, as curl
and Postman send it, so `?q=a+b` goes out exactly as typed. An empty value renders `name=`, so
a typed `?flag` is sent as `?flag=`.

```
-> editParamRow(index, name | value)
  -> params[index] = row                         pure
  -> URLText.join(url, params.enabled)           pure: the URL bar re-renders
```

```
-> toggleRow(table, index)                       Headers, Params, form fields, Cookies
  -> Rows.toggle(at: index, in: rows)            pure: isEnabled flips, nothing else
  -> URLText.join                                only for Params
```

Every key/value table keeps one trailing empty row after its rows, at index `rows.count`.

```
-> editRow(table, index, name | value)          every key/value table
  -> Rows.setName / Rows.setValue                pure: at rows.count, typing appends a row
                                                 and a new trailing row appears
  -> URLText.join                                only for Params
-> deleteRow(table, index)                       the ⊖ on hover, or Delete on the selected row
  -> Rows.delete(at: index, in: rows)            pure: the trailing row has nothing to delete
```

## Path Variables

A `:name` segment in the URL, and the value the Request keeps for it. The inverse of Params:
**the URL text is the source of truth for which names exist, in order of first appearance,
and the table holds only values.** Params is the other way round, where the table is the
source and the URL bar is rendered from it. So there is no row to add or delete, no enabled
flag, and a Path Variable cannot be created from the table.

```
-> PathVariables.tokens(in: url)                 pure        R: none      E: none, any text is
                                                 a URL to read, and no match is the empty list
  -> skip the authority: scanning starts at the first `/` that is not part of `://`
  -> stop at the first `#`                       the rest is a fragment, never sent
  -> skip every `{{name}}` Variable token        VariableTokens.ranges, so a Variable is never
                                                 read as part of a Path Variable
  -> a `:` straight after a `/`, then a run of name characters, at least one: a Path Variable
     name characters: letters and digits of any script, `_` and `-`. Nothing else, so the name
     ends at the first `.`, `:`, `{`, `(` or any other character, and what follows is literal
  -> [PathVariableToken] in text order; a name seen again is not listed again by .names

-> PathVariables.prune(values, to: url)          pure        values whose name is not in the URL go
-> PathVariables.setValue(text, for: name, in:)  pure        "" removes the key, else it is stored
```

| `url` | Path Variables |
|---|---|
| `http://localhost:3061/posts` | none. `:3061` follows `localhost`, not `/` |
| `localhost:3061/x` · `{{host}}:8080/x` | none, for the same reason |
| `http://localhost:3061/posts/:id/retry-share-social-media` | `id` |
| `/:` · `/:/x` | none: at least one name character |
| `/:id/:id` | `id`, once |
| `/:id/:other/:id` | `id`, `other` |
| `http://h/a:id` | none: `:` is not straight after `/` |
| `http://:id` | none: the authority is not scanned |
| `http://h/:{{x}}` | none. `{` is not a name character, and `{{x}}` is a Variable as ever. The send writes `:` then the value of `x` |
| `http://h/:id{{x}}` | `id`; `{{x}}` stays a Variable after it |
| `http://h/{{base}}/:id` | `id` |
| `http://h/:id.json` | `id`; `.json` is literal text after the value. Postman reads the name the same way (environment-facts.md) |
| `http://h/:id:cancel` | `id`; `:cancel` is literal (Yaak's custom-method case) |
| `/:user-id` · `/:user_id` · `/:ünï` | `user-id` · `user_id` · `ünï` |
| `/:Id/:id` | `Id`, `id`: names are case-sensitive |
| `http://h/a#/:id` | none: after the `#` |

**Names are read from the text as typed, never from the text after `{{name}}` substitution.**
A Variable whose value is `/:x` does not create a Path Variable at send that the table does not
show. The table and the send read the same tokens from the same text.

**A name that leaves the URL loses its value.** Typing `:i` and then `:id` leaves no `i` behind.
The alternative, hidden orphans kept in the file, writes junk to git. Undo covers a typo
because the prune and the text edit are one step. A hand-edited file may still carry an orphan:
decoding does not prune (boundary.md), so it is inert until the next URL edit removes it.

**An empty value is no value.** Clearing the cell removes the key, so a Request whose value was
typed and deleted equals the saved one, and no `"id": ""` reaches the file.

```
-> editPathVariableValue(name, text)             the Value cell of the Path Variables table;
                                                 the Name cell is read-only
  -> PathVariables.setValue(text, for: name, in: definition.pathVariables)
                                                 pure        R: none      E: none, every string
                                                 is a valid value
     -> text == "" -> the key is removed; else stored as typed: not trimmed, not decoded,
        not encoded (sending.md encodes once, at send)
     -> a name not in `url` -> no change, the row was leaving under the edit
  -> definition.pathVariables changed            Dirty, the Session, the Curl pane and the
                                                 highlight follow, as for any edit (tabs.md)

-> pathVariablesTable(definition)                every render of the Params pane
  -> PathVariables.tokens(in: definition.url)    pure        R: none
  -> none -> no header, no table, nothing
  -> else a "Path Variables" header and one row per name: Name read-only, Value
     definition.pathVariables[name] ?? ""        a row appears and goes with the URL, and the
                                                 cell being edited keeps its focus and caret
                                                 when another row comes or goes
  -> the URL field paints each token's range     paint only: the text, the caret and the
                                                 selection are untouched
```

**Values take `{{name}}`.** The Value cell highlights and suggests Variables like any cell
(variables.md), and the highlight pass reads `pathVariables` as one more place Variables live,
so a Path Variable value holding an Undefined Variable is coloured red like any other.

## Body Type

```
-> pickBodyType(newType)
  -> BodyConversion.convert(body, to: newType)   pure
     raw → raw          keep the text, change RawKind
     form ↔ multipart   keep the rows, text parts only
     anything → none    keep nothing, but the old body is in undo
     other pairs        start empty
  -> Headers.contentType(for: newType)           pure
     -> set Content-Type only if the user has not set one, or the one there was
        the one this rule set last time
     -> "set last time" is read, not stored: an enabled row whose value is what this
        rule writes for the old Body Type. Switching to none removes that row
```

**Raccoon writes `Content-Type` as a visible header row, never invisibly.** Request Cookies
were chosen over a cookie jar so that what you see is what Raccoon sends, and the same rule
means a header that goes out has to be in the table. Multipart's boundary is the one exception, because the user cannot
know it: the row shows `multipart/form-data` and the transport appends `; boundary=…`.

## Format the body

```
-> formatBody(tab)                               the Format button, ⇧⌥F; raw JSON or XML only
  -> BodyFormatter.format(text, kind)            pure        R: none
     -> each {{name}} is read as one value token by Raccoon's own lexer, so
        `"amount": {{amount}}` formats instead of failing as invalid JSON
     -> JSON: 2-space indent, key order kept; XML: 2-space indent, attributes kept as written
                                                 E: FormatError.notValid(line, column)
                                                 -> escape: one line under the
                                                 body editor with the line and column; the text
                                                 is unchanged
  -> body text replaced                          one undo step
```

**Format never reorders and never changes values.** Keys keep their order, numbers keep their
spelling (`1.50` stays `1.50`, which a decode and re-encode through `JSONSerialization` would
not), and a Variable stays exactly as typed. It only changes whitespace, so Dirty, the saved file
and the bytes sent change by whitespace only.
