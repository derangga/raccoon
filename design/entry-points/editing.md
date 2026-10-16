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
```

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
