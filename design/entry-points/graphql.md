# §2 A — GraphQL

A GraphQL Body Type: a Query, its Variables as JSON and an optional Operation Name, sent as
one POST whose body is `{"query", "variables", "operationName"}`. Decided 2026-11-12.

One slice of [DESIGN.md](../../DESIGN.md) §2. Failures are read in
[§4](../e-where-it-breaks.md), requirements in [§5](../r-what-it-needs.md).

GraphQL is still exactly one HTTP request. Raccoon adds no schema, no introspection and no
completion: what the user typed is what goes out, encoded as JSON.

## Pick the GraphQL Body Type

```
-> pickBodyType(.graphql)                        editing.md, one more case
  -> BodyConversion.convert(body, to: .graphql)  pure
     raw json -> graphql                         parse the text; a top-level object lifts
                                                 `query` (string), `variables` (any JSON,
                                                 re-printed with 2-space indent) and
                                                 `operationName` (string). Anything else,
                                                 or text that does not parse: start empty
     graphql -> raw json                         GraphQLPayload.text(body): the JSON the send
                                                 would carry, before resolution
     graphql -> none                             keep nothing; the old body is in undo
     other pairs                                 start empty
  -> Headers.contentType(for: .graphql)          `application/json`, by the existing rule:
                                                 set only if the user has none, or it is the
                                                 one this rule set last time
  -> GraphQLMethod.forPick(method)               pure: GET or HEAD -> POST, anything else kept
  -> one undo step                               the body, the Content-Type row and the method
```

Setting GET by hand afterwards is allowed. The send then fails as any GET with a body does
(environment-facts.md, Body on GET), with the existing message.

## Edit

```
-> type in the Query editor                      TabModel.edit { body.query = text }
  -> Highlighter.ranges(text, .graphql)          pure, off the main actor as for JSON
                                                 R: none   E: none, total: text that does
                                                 not lex is drawn plain from that point
  -> VariableTokens.ranges(text)                 `{{name}}` highlighted on top, as everywhere
-> type in the Variables editor                  TabModel.edit { body.variables = text }
  -> Highlighter.ranges(text, .json)             the existing JSON colours
-> Format the Variables                          the Format button and ⇧⌥F act on Variables
                                                 when it has focus, through BodyFormatter
                                                 (.json); the Query has no formatter
-> type in Operation Name                        TabModel.edit { body.operationName = text }
```

## Send

```
-> VariableResolver.resolve(definition, scope)   variables.md
  -> substitute {{name}} in query, variables and operationName
                                                 every Undefined Variable in all three is
                                                 listed with the rest
  -> GraphQLPayload.encode(query:, variables:, operationName:)
                                                 pure        E: ResolveError.graphqlVariables
     -> variables trimmed empty                  -> omitted
     -> variables not a JSON object              -> throw .graphqlVariables(line, column)
                                                    escape: .notSent, nothing went out
     -> operationName trimmed empty              -> omitted
     -> {"query": <string>, "variables": <object>, "operationName": <string>}
                                                 keys in that order, no added whitespace
  -> the ResolvedRequest's body is .raw(.json, payload)
                                                 so the transport, AutomaticHeaders, Copy as
                                                 Curl and the Curl pane need no new case
```

**The resolver lowers GraphQL to raw JSON.** `ResolvedRequest` is what the transport sends and
Copy as Curl renders. Turning a GraphQL body into its JSON once, at resolution, means neither
of them learns a new Body case, and Copy as Curl shows exactly the bytes that go out.

**Variables must be a JSON object, checked after substitution.** `{"id": {{id}}}` is valid
only once `{{id}}` is a number, so the check runs on the resolved text. While editing, nothing
checks the Variables except Format, which reads `{{name}}` as one value as it does for a JSON
body (editing.md).

**`{{name}}` inside the Query is substituted as text.** GraphQL's own `$variables` are the
right tool, but a `{{baseFragment}}` in a query is the user's choice, and Raccoon resolves it
the same way it does everywhere else.

## Curl and Postman

```
-> Curl Import                                   unchanged: a {"query": …} body stays raw JSON
                                                 (the two Yaak GraphQL fixtures stay "Differs")
-> Postman Import, body mode `graphql`           postman.md
  -> .graphql(query, variables, operationName: "")
                                                 variables kept as text, as Postman stores it;
                                                 an object is re-printed with 2-space indent
  -> an empty query and empty variables          .none, as today
-> Postman Export, a .graphql body               postman-export.md
  -> {"mode": "graphql", "graphql": {"query", "variables"}}
                                                 variables as the text in the editor. Postman
                                                 has no operationName field: an Operation Name
                                                 is lost on export, and the Collection Export
                                                 sheet does not list it (it is never a
                                                 credential and the query still names it)
```

**No GraphQL detection on paste.** A pasted request is one request: guessing that a JSON body
is GraphQL would change what the editor shows for a body the user wrote as JSON. Switching the
Body Type by hand converts it, so nothing is retyped.
