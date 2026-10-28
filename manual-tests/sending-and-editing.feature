# Manual acceptance: Sending and editing (M1)
#
# Run every Feature twice: macOS Appearance Light (Latte), then Dark (Mocha).
# Compare against the Raccoon UI canvas boards named in each Feature.
#
# Fixtures, in one terminal:
#   mkdir -p /tmp/rc && cd /tmp/rc
#   echo '{"a":1}' > small.json
#   printf '<a><b>x</b></a>' > small.xml
#   python3 -c "import json;print(json.dumps(['x'*100]*38000))" > under.json   # ~3.9 MB
#   python3 -c "import json;print(json.dumps(['x'*100]*60000))" > big.json     # ~6.2 MB
#   head -c 48200 /dev/urandom > bin.dat
#   : > empty.txt
#   echo receipt > ~/Desktop/receipt.pdf
#   python3 -m http.server 8080
# A server that never answers, in a second terminal (restart after each use):
#   nc -l 9000
# httpbin.org echoes what was sent; badssl.com serves a self-signed certificate.
# Launch: swift run Raccoon


Feature: URL bar
  Boards 01, 03, 04, 09, 10

  Scenario: The empty Draft
    Given a fresh window
    Then the method reads "GET" in the GET color
    And the URL field shows the placeholder "Enter a URL, or paste a curl command"
    And the URL field has the focus ring before any typing
    And the button reads "Send" on the accent fill, tooltip "Send (⌘↩)"

  Scenario: The method pop-up
    When I click the method
    Then the menu lists GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS and nothing else
    And each method is drawn in its own color, the current one checked
    When I pick "POST"
    Then the method reads "POST" in the POST color

  Scenario: Select all in the URL field
    Given the URL field holds "https://h/a?b=1" and has the focus
    When I press ⌘A
    Then the whole text is selected

  Scenario: Pasting a curl command
    Given an empty Draft
    When I paste a multi-line Chrome "Copy as cURL" command into the URL field
    Then the URL field shows only the URL and the text of the command is not in it
    And the method, the headers, the cookies, the Auth and the body are filled from the flags
    And the caret is at the end of the URL, nothing is selected
    And one ⌘Z puts the empty Draft back

  Scenario: Undo and Redo of a curl import, with the focus still in the field
    Given an empty Draft and the focus in the URL field
    When I paste "curl --retry 3 https://h/a -H 'x-one: 1'"
    Then the note under the URL bar reads "Ignored: --retry"
    When I press ⌘Z
    Then the URL field is empty, Headers is empty and the note is gone
    When I type one character in the URL field
    Then only that character is in the URL field
    When I press ⌘Z until the field is empty, then ⇧⌘Z
    Then the import comes back: URL "https://h/a", header "x-one", the note

  Scenario: Notes for extra commands and files
    When I paste two curl commands one under the other
    Then the note reads "1 more command"
    When I paste three, the note reads "2 more commands"
    When I paste "curl --data-binary @/tmp/rc/bin.dat https://h"
    Then the body is none and the note reads "/tmp/rc/bin.dat is not text, and binary bodies are not supported"
    When I paste a curl whose "@file" does not exist
    Then the note reads "<path> was not read"

  Scenario: A curl command that cannot be imported
    When I paste "curl 'https://h"
    Then the message line reads "Unterminated quote in this curl command, at character 6."
    And the request is unchanged and nothing is inserted into the URL field

  Scenario: Segmented controls
    When I look at Pretty | Raw, Body | Headers N and None | Basic | Bearer
    Then each is a bordered, rounded box of segments split by 1 pt rules
    And the selected segment is filled with the selection color and is semibold, the others are plain
    And a disabled segment is in the disabled text color

  Scenario: Rows in the key/value table
    Given a Headers table with a row "x-one: 1"
    When I click its checkbox
    Then the box is unchecked and the name and value turn to the disabled text color
    When I click the row outside the box
    Then the row is filled with the selection color and its text stays readable
    When I hover the row and click its minus button
    Then the row is removed
    And the automatic rows (Host, Accept, ...) come first, each with a checked, greyed-out checkbox, and cannot be selected
    And the empty Name / Value row is the last row
    And the only vertical line is between Name and Value on every row, with nothing to the right of Value

  Scenario: A long URL
    When I paste a 2,000-character URL and click elsewhere
    Then it stays on one line and fades over its last 32 pt

  Scenario: Invalid URL
    Given the URL "not a url"
    When I press ⌘↩
    Then the URL field is outlined in the error color
    And the status line reads "Not sent"
    And the Response pane reads "Invalid URL" and "After substitution the URL was not a url."
    And no spinner ever showed
    When I type one character in the URL field
    Then the error outline is gone


Feature: URL bar and Params stay in sync
  Board 02

  Scenario: Typing a query fills Params
    When I type "https://httpbin.org/get?a=1&b=2" in the URL field
    Then the Params table holds a=1 and b=2, and the section reads "Params 2"
    And after editing ends, "?", "=" and "&" are dimmed

  Scenario: Editing Params rewrites the URL
    When I change b's value in the Params table to "3"
    Then the URL field reads "https://httpbin.org/get?a=1&b=3"

  Scenario: A Disabled Row survives typing in the URL bar
    Given Params a=1 and b=2
    When I uncheck b
    Then the URL reads "https://httpbin.org/get?a=1"
    And b is drawn in the disabled color, still counted: "Params 2"
    When I fix a typo in the host by typing in the URL field
    Then b is still in Params, unchecked, at the same place

  Scenario: Encoding is decoded once and encoded once
    When I type "https://httpbin.org/get?q=a%20b&p=x+y" and send
    Then the Params value of q reads "a b"
    And httpbin's "args" shows q = "a b" and p = "x y" (the "+" went out as typed)

  Scenario: Variables pass through unencoded
    When I type "https://httpbin.org/get?id={{user_id}}"
    Then the Params value of id reads "{{user_id}}", not "%7B%7Buser_id%7D%7D"


Feature: Path Variables
  Board 17

  Scenario: A :name in the URL makes a Path Variables table
    Given a new Draft, GET, URL empty
    When I type "https://httpbin.org/anything/posts/:id/retry" in the URL field
    Then ":id" is drawn as a rounded token, filled and outlined, in the same colour as a Name cell
    And the Params section shows the label "Query Params" over a table with one empty row
    And under it a label "Path Variables" and a table with one row: Name "id", Value empty with the grey placeholder "Value"
    And that table has no checkbox, no delete button and no trailing empty row
    And the section bar reads "Params" with no count
    When I click the Name cell "id"
    Then nothing happens: it is not editable and not selected

  Scenario: A value is sent in place of :id, and Copy as Curl shows the same
    Given the URL "https://httpbin.org/anything/posts/:id/retry"
    When I click the Value cell (it shows its outline), type "689eba19be47b88f9d590367" and press ⌘↩
    Then httpbin's "url" reads "https://httpbin.org/anything/posts/689eba19be47b88f9d590367/retry"
    When I press ⇧⌘C and paste
    Then the curl command's URL is the same
    And the inspector's Curl pane shows the same URL

  Scenario: The value follows the URL
    Given the value "689eba19be47b88f9d590367" for :id
    When I change the host in the URL field
    Then the Path Variables row and its value are still there
    And if I was editing the Value cell, it keeps its outline and caret
    When I delete ":id" from the URL
    Then the "Path Variables" label and table disappear, and "Query Params" stays
    When I press ⌘Z in the URL field
    Then ":id" is back, with the value

  Scenario: A name typed letter by letter keeps no stray value
    Given the URL "https://httpbin.org/anything/:i" with the value "7" for i
    When I type "d" after ":i"
    Then the table shows "id" with an empty Value, and "i" is gone

  Scenario Outline: What is and is not a Path Variable
    When I type "<url>" in the URL field
    Then the Path Variables table <shows>

    Examples:
      | url                                       | shows                                       |
      | http://localhost:3061/posts               | is absent, and ":3061" is not a token       |
      | localhost:3061/x                          | is absent                                   |
      | {{host}}:8080/x                           | is absent                                   |
      | http://h/:                                | is absent                                   |
      | http://h/:id/:id                          | has one row, "id"                           |
      | http://h/:id.json                         | has one row, "id"; ".json" is not in the token |
      | http://h/:id:cancel                       | has one row, "id"                           |
      | http://h/:user-id/:user_id                | has two rows: "user-id", "user_id"          |
      | http://h/:{{x}}                           | is absent                                   |

  Scenario: Empty is sent as typed
    Given the URL "https://httpbin.org/anything/:id" and no value
    When I press ⌘↩
    Then httpbin's "url" reads "https://httpbin.org/anything/:id"
    And there is no message under the URL bar

  Scenario Outline: Encoding a value
    Given the URL "https://httpbin.org/anything/:id" and the value "<value>"
    When I press ⌘↩
    Then httpbin's "url" ends with "<sent>"

    Examples:
      | value     | sent        | why                                         |
      | a b       | /a%20b      | a space is encoded                          |
      | a/b       | /a/b        | "/" is not encoded: two segments, as in Postman |
      | a%2Fb     | /a%2Fb      | to send one segment, type %2F: it goes as typed |
      | 100%      | /100%25     | a lone % is encoded                         |
      | a?b#c     | /a%3Fb%23c  | a value cannot start a query or a fragment  |
      | a,b;c=d   | /a,b;c=d    | what a path can hold stays                  |

  Scenario: A Variable in a value
    Given an Environment with user_id = "42" is active, and the value of :id is "{{user_id}}"
    When I press ⌘↩
    Then the request goes to ".../anything/42"
    And "{{user_id}}" in the Value cell is blue

  Scenario: An Undefined Variable in a value blocks the send
    Given the value of :id is "{{missing}}", defined nowhere
    Then "{{missing}}" in the Value cell is red with a wavy underline
    And the section bar's "Params" is in the undefined colour, semibold, with no count (there is no Query Param row)
    When I add the Param page=1
    Then the label reads "Params 1" with the count, not the label, in the undefined colour
    When I press ⌘↩
    Then the message line reads "Not sent. missing is not defined in <Environment> or in Globals."
    And no request reached the server

  Scenario: A saved Request keeps its Path Variables
    Given a Request with the URL ".../:id" and the value "7"
    When I save it with ⌘S
    Then the file in the Data Folder has a "pathVariables" key: {"id": "7"}
    When I clear the value and save again
    Then the file has no "pathVariables" key
    And a Request that never had a value is saved with the same bytes as before this feature

  Scenario: A Dirty edit and a Draft survive a relaunch
    Given a Draft with the URL ".../:id" and the value "7"
    When I quit with ⌘Q and launch again
    Then the Draft is back with the value "7" in the Path Variables table

  Scenario: Pasting a curl command with :id (break-ui: two kinds of colon)
    When I paste "curl https://httpbin.org/anything/:id" into the URL field
    Then the URL reads "https://httpbin.org/anything/:id" and the table shows one row "id", empty

  Scenario: Many names and a long value (break-ui)
    When I type a URL with 30 names
    Then the pane scrolls as one, and no table header stays pinned
    And a 2,000-character value is end-truncated in its cell


Feature: Key/value table
  Boards 02, 05, 10 (Params, Headers, Cookies, form-urlencoded, multipart)

  Scenario: The trailing row
    Given the Params section
    Then there is one empty row with "Name" and "Value" placeholders, clearly fainter than a typed value
    When I click its Name cell
    Then the editing field fills the row less 2 pt, the text is centered vertically and 4 pt inside the ring
    When I type "limit"
    Then all five letters land in the same field, with no jump to another row
    And it becomes a row with a checked checkbox and a new empty row appears below
    When I hover that row
    Then its ⊖ delete button shows

  Scenario: Toggle and delete
    Given two Params rows
    When I select a row and press Space
    Then its checkbox flips and nothing else changes
    When I press Delete
    Then the row is gone
    When I hover a row
    Then a ⊖ delete button shows on it only
    And the trailing row cannot be toggled or deleted from the keyboard

  Scenario: Return edits
    When I select a row and press Return
    Then its name is in edit mode

  Scenario: Long values and many rows
    Given a header value longer than the column
    Then it ends in "…" and its tooltip shows the whole value
    Given 60 rows
    Then the table scrolls and its "Name / Value" header stays put
    And the section reads "Headers 60"


Feature: Request sections
  Boards 02, 03

  Scenario: Section bar
    Then the sections read Params · Headers · Body · Auth · Cookies · Settings, Params selected
    And a count follows each table name only when it has rows
    And Body shows no type, whatever its Body Type, and Auth reads "Auth" whatever its scheme

  Scenario: The editor/Response split
    When I drag the divider between the editor and the Response
    Then neither pane gets smaller than 160 pt


Feature: Every header sent is on screen, in Headers or as the Auth
  Headers section, automatic rows

  Scenario: Automatic rows
    Given the URL "https://httpbin.org/headers"
    When I open Headers
    Then before the trailing row, read-only rows in the tertiary color show:
      | Host            | httpbin.org       |
      | Accept          | */*               |
      | Accept-Language | *                 |
      | Accept-Encoding | gzip, deflate, br |
      | Connection      | keep-alive        |
      | User-Agent      | Raccoon/0.1       |
    And each has a checked, greyed-out checkbox that cannot be changed, tooltip "Always sent. Add a row with the same name to replace it."
    And they have no ⊖, cannot be selected, and the "Headers" count leaves them out
    And my own rows come after them and the empty Name / Value row is last
    And with an empty URL there are no automatic rows

  Scenario: A typed row replaces its automatic row
    When I add the header "Accept" = "application/json"
    Then the automatic Accept row is gone
    When I send
    Then httpbin's echo shows Accept "application/json", User-Agent "Raccoon/0.1", Accept-Language "*"

  Scenario: A Disabled header is not sent
    Given the header "X-Debug" = "1", unchecked
    When I send to "https://httpbin.org/headers"
    Then the echo has no X-Debug

  Scenario: Content-Length is calculated when sent
    Given a raw body
    Then the automatic "Content-Length" row reads "calculated when sent"


Feature: Request Cookies
  Cookies section

  Scenario: Cookies go out as one Cookie header
    Given Cookies a=1 and b=2
    When I send to "https://httpbin.org/headers"
    Then the echo shows one Cookie header "a=1; b=2"
    When I uncheck b and send again
    Then it shows "a=1"


Feature: Response viewer states
  Boards 01, 02, 09, 10

  Scenario: Idle
    Then the Response pane reads "Send a request to see the Response here." with a "⌘↩" key cap

  Scenario: A fast send never flashes the spinner
    When I send "http://localhost:8080/small.json"
    Then no spinner appears, and the status line reads "200 OK", the time, "·" and "8 B"

  Scenario: Sending
    Given "nc -l 9000" is running
    When I send "http://localhost:9000/"
    Then after about 150 ms a spinner shows, with "Sending…" and a live time ("1.4 s")
    And the body reads "Waiting for the server. ⌘. cancels."

  Scenario Outline: Status codes and their colors
    When I send "https://httpbin.org/status/<code>"
    Then the status line reads "<line>" in the <class> color

    Examples:
      | code | line                  | class |
      | 200  | 200 OK                | 2xx   |
      | 302  | 302 Found             | 3xx   |
      | 404  | 404 Not Found         | 4xx   |
      | 503  | 503 Service Unavailable | 5xx |

  Scenario: Only the reason truncates
    Given a "511 Network Authentication Required" Response in a narrow window
    Then the reason ends in "…", while the code, time and size stay whole

  Scenario: Pretty JSON and Raw
    When I send "http://localhost:8080/small.json"
    Then Pretty is selected and the body reads, colored:
      """
      {
        "a": 1
      }
      """
    When I click "Raw"
    Then it reads '{"a":1}' with no colors

  Scenario: Pretty XML
    When I send "http://localhost:8080/small.xml"
    Then the body is indented XML, with tags colored

  Scenario: A body that does not parse is Raw, not an error
    When I send "https://httpbin.org/html"
    Then Raw is selected, Pretty is disabled, and no error shows

  Scenario: Under the Pretty threshold
    When I send "http://localhost:8080/under.json"
    Then Pretty is available and no note shows

  Scenario: Over the Pretty threshold
    When I send "http://localhost:8080/big.json"
    Then Pretty is disabled, Raw is selected, and "Pretty is off above 5 MB" shows beside it
    And scrolling to the end of the body stays responsive

  Scenario: Binary body
    When I send "http://localhost:8080/bin.dat"
    Then the body reads "Binary body" and "48.2 KB that is not UTF-8 text. Raccoon shows text bodies only."

  Scenario: Empty body
    When I send "http://localhost:8080/empty.txt"
    Then the status line reads "200 OK" and "0 B", and the body reads "Empty body."


Feature: Response headers
  Board 09

  Scenario: Body | Headers
    Given a received "http://localhost:8080/small.json"
    Then the status line ends with "Body | Headers N", N being the header count
    When I click "Headers"
    Then two columns show name and value, sorted by name, names in a dimmer color
    And all names start at one left edge and all values at another, 220 pt to the right, none centered
    And under the last row: "macOS merges repeated headers and doesn't keep their order."
    And Pretty | Raw is hidden

  Scenario: Repeated headers are merged
    Given Settings › Follow redirects is unchecked
    When I send "https://httpbin.org/cookies/set?a=1&b=2" and open Headers
    Then there is one "Set-Cookie" row with both cookies joined by ", "

  Scenario: Long value
    Then a value wider than its column ends in "…" and its tooltip shows the whole value

  Scenario: The choice lasts across sends
    Given the Headers view is showing
    When I send again
    Then the Headers view is still showing


Feature: Cancel an in-flight send
  Board 09 "URL bar: sending, and Cancel"

  Scenario: Send becomes Cancel
    Given "nc -l 9000" is running
    When I send "http://localhost:9000/"
    Then the button reads "Cancel" with no accent fill and a border, tooltip "Cancel (⌘.)"
    And pressing ⌘↩ again does nothing

  Scenario Outline: Cancel returns to idle, not to a failure
    Given a send to "http://localhost:9000/" is in flight
    When I <action>
    Then the Response pane reads "Send a request to see the Response here."
    And the button reads "Send" again
    And the nc terminal shows the connection closed at once

    Examples:
      | action                                  |
      | click Cancel                            |
      | press ⌘.                                |
      | press ⌘. with the URL field focused     |

  Scenario: Send right after Cancel
    Given I just cancelled a send
    When I change the URL to "http://localhost:8080/small.json" and press ⌘↩ at once
    Then the Response shows "200 OK"


Feature: Send failures in the Response pane
  Boards 06, 09

  Scenario: Untrusted certificate
    When I send "https://self-signed.badssl.com/"
    Then the status line reads "Failed" and "after N ms" in the failed color
    And the pane shows a crossed-shield glyph, "Untrusted certificate",
      "The certificate for self-signed.badssl.com is not trusted by this Mac. It may be self-signed or expired."
    And a button "Allow insecure TLS for this request"
    When I click the button
    Then nothing is sent
    And Settings › "Allow insecure TLS" is now checked
    When I press ⌘↩
    Then the Response shows "200 OK"

  Scenario: Connection refused
    When I send "http://localhost:9/"
    Then the pane shows "Could not connect to the server"
      and "NSURLErrorCannotConnectToHost (−1004) · localhost:9"
    And no "Allow insecure TLS" button

  Scenario: Host not found
    When I send "http://nope.invalid/"
    Then the pane shows URLError's description, "NSURLError… (−100x)" and "nope.invalid"

  Scenario: Timed out
    Given "nc -l 9000" is running
    When I send "http://localhost:9000/" and wait 60 s
    Then the status line reads "Failed" and "after 60.0 s"
    And the pane shows "No response after 60 s"
      and "The server did not answer in time. Raccoon does not send again by itself."
    And no button, and the request was not sent twice (nc saw one connection)


Feature: Request Settings
  Board 06

  Scenario: Two checkboxes
    When I open Settings
    Then I see "Allow insecure TLS", with the hint
      "Accept certificates the system does not trust, for this Request only."
    And "Follow redirects"
    And there is no compression row

  Scenario: Follow redirects
    Given "Follow redirects" is unchecked
    When I send "https://httpbin.org/redirect/1"
    Then the Response is "302 Found"
    When I check "Follow redirects" and send again
    Then the Response is "200 OK"


Feature: Auth
  Boards 03, 05, 09, 11, 13, 15

  Scenario: None
    When I open Auth
    Then the section bar reads "Auth"
    And "Auth type" is a label, with a pop-up reading "None" under it
    And "No Authorization header is added." shows under the pop-up
    And the right column is empty
    And there is no reset button

  Scenario: The pop-up holds three items
    When I open the "Auth type" pop-up
    Then it lists "None", "Basic Auth" and "Bearer Token", with the current one checked

  Scenario: Basic
    When I choose "Basic Auth"
    Then the section bar still reads "Auth"
    And the right column shows the heading "Basic Auth" and the rows "Username" and "Password"
    And the paragraph reads "The Authorization header is generated from the username and password when you send the request."
    When I type Username "user" and Password "pass"
    Then the password shows as bullets
    And the Tab is Dirty
    When I send "https://httpbin.org/basic-auth/user/pass"
    Then the Response is "200 OK"

  Scenario: A password holding a Variable shows its name
    When I type the password "{{ops_password}}" and click elsewhere
    Then the field shows "{{ops_password}}" as text, not bullets

  Scenario: Bearer
    When I choose "Bearer Token"
    Then the heading reads "Bearer Token" and one row "Token" shows
    And the paragraph reads "The Authorization header is sent as Bearer followed by the token."
    When I type the Token "abc.def"
    And I send "https://httpbin.org/headers"
    Then the echo shows Authorization "Bearer abc.def"

  Scenario: An enabled Authorization row in Headers is sent instead of Auth's
    Given Auth is "Bearer Token" with the Token "abc.def"
    And Headers holds the enabled row "Authorization: Basic eHl6"
    When I open Auth
    Then the paragraph reads "The Authorization header is sent as Bearer followed by the token. An enabled Authorization row in Headers is sent instead."
    And the Token field is editable and looks as it does without the row
    When I send "https://httpbin.org/headers"
    Then the echo shows Authorization "Basic eHl6", not "Basic eHl6,Bearer abc.def"
    When I disable the Headers row and open Auth
    Then the paragraph reads "The Authorization header is sent as Bearer followed by the token."
    When I send "https://httpbin.org/headers"
    Then the echo shows Authorization "Bearer abc.def"

  Scenario: The row wins whatever its case or value
    Given Auth is "Basic Auth" with Username "ana" and Password "pw"
    And Headers holds the enabled row "authorization" with an empty value
    When I send "https://httpbin.org/headers"
    Then the echo shows no Authorization from Auth: not "Basic YW5hOnB3"
    And Copy as Curl and the Curl pane show the same Authorization header, or none, as the echo

  Scenario: Switching the scheme drops what was typed for the old one
    Given the Bearer token "abc.def"
    When I choose "None", then "Bearer Token"
    Then the Token field is empty
    When I press ⌘Z twice
    Then the pop-up reads "Bearer Token" and the Token reads "abc.def"

  Scenario: Another Tab does not inherit typed credentials
    Given Tab A has "Basic Auth" with Username "ana" and Password "pw"
    When I open Tab B, which has Auth "None", and choose "Basic Auth"
    Then Username and Password are empty

  Scenario: Choosing None is one undo step
    Given Auth is "Bearer Token" with the Token "abc.def"
    When I choose "None"
    Then the pop-up reads "None" and the right column is empty
    When I press ⌘Z
    Then the pop-up reads "Bearer Token" and the Token reads "abc.def"

  Scenario: A saved Request never puts the scheme in the section bar
    Given a Request opened from a saved file with Basic Auth
    Then the section bar reads "Auth", never "Auth Basic"
    And the Auth pane shows "Basic Auth" in the pop-up

  Scenario: A narrow editor stacks the pane
    Given the Auth pane is "Basic Auth"
    When the editor is 800 pt wide
    Then "Auth type" and its paragraph sit left of a vertical rule, and the fields right of it
    When I drag the editor narrower than 600 pt
    Then the left column sits above the right one, with a horizontal rule between them
    And the fields keep their labels and fill the width up to 320 pt


Feature: Body editor
  Boards 03, 05, 09, 10

  Scenario: none
    When I open Body
    Then "Body Type" reads "none" and the pane reads "This request has no body."

  Scenario: raw JSON
    When I pick Body Type "raw"
    Then a second pop-up reads "JSON" (JSON · text · XML)
    And Headers has a "Content-Type" row "application/json", and the section still reads "Body"
    And the editor has line numbers, SF Mono, no wrapping
    When I type '{"a": 1, "b": true}'
    Then keys, numbers and booleans take their syntax colors

  Scenario: raw text is not colored
    When I switch the kind to "text"
    Then the text stays and loses its colors, and Content-Type becomes "text/plain"

  Scenario: A Content-Type I typed is never rewritten
    Given I set the Content-Type row to "application/vnd.api+json"
    When I switch the kind to XML
    Then the Content-Type row still reads "application/vnd.api+json"

  Scenario: Undo a Body Type change
    Given raw JSON '{"a": 1}'
    When I pick "none"
    Then the text and the Content-Type row are gone
    When I pick "raw" again
    Then the editor is empty
    When I press ⌘Z twice
    Then the editor reads '{"a": 1}' and the Content-Type row is back

  Scenario: form-urlencoded
    When I pick "form-urlencoded"
    Then the key/value table shows, and Content-Type reads "application/x-www-form-urlencoded"
    When I add q = "a b" and send to "https://httpbin.org/post" as POST
    Then httpbin's "form" shows q = "a b"

  Scenario: form ↔ multipart keeps the text rows
    Given form rows a=1 and b=2
    When I pick "multipart", then "form-urlencoded"
    Then a=1 and b=2 are still there

  Scenario: Japanese and emoji (break-ui)
    When I paste '{"名前": "🦝 ラクーン"}' into a raw JSON body
    Then it renders, colors and edits normally, and the cursor moves one character at a time

  Scenario: The body is sent as typed
    Given raw JSON '{"amount": 2000}' and method POST
    When I send to "https://httpbin.org/post"
    Then httpbin's "json" shows amount 2000


Feature: Format the body
  Board 03

  Scenario: The button
    Given a raw JSON body
    Then a "Format" button with a list glyph sits at the end of the Body Type row
    And its tooltip reads "Format JSON (⇧⌥F)"
    And it is hidden for text, none, form-urlencoded and multipart

  Scenario: Format keeps keys, numbers and Variables
    Given the raw JSON '{"b":1.50,"a":{{amount}}}'
    When I click Format
    Then the body reads:
      """
      {
        "b": 1.50,
        "a": {{amount}}
      }
      """
    When I press ⌘Z once
    Then the original one-line text is back

  Scenario: The shortcut
    Given a raw XML body '<a><b>x</b></a>'
    When I press ⇧⌥F
    Then it is indented by two spaces

  Scenario: Format never runs by itself
    When I paste unformatted JSON into the body
    Then it stays as pasted

  Scenario: A body that does not parse
    Given the raw JSON:
      """
      {
        "amount": 2000,
        "currency" "usd",
      }
      """
    When I click Format
    Then the text is unchanged
    And a red line under the editor reads "Couldn't format: not valid JSON at line 3, column 14."
    When I type one character
    Then the line is gone


Feature: Multipart parts
  Board 09 "Body: multipart"

  Scenario: Text and file parts
    When I pick Body Type "multipart"
    Then the Value placeholder reads "Value or file"
    And Content-Type reads "multipart/form-data"

  Scenario Outline: A file part
    When I <how> "~/Desktop/receipt.pdf" on the trailing row
    Then the value is a 20 pt chip with a document glyph and "receipt.pdf"
    And its tooltip shows the full path

    Examples:
      | how                                        |
      | right-click › "Choose File…" and pick      |
      | drag from Finder and drop                  |

  Scenario: A file part is sent
    Given the part "file" = receipt.pdf and method POST
    When I send to "https://httpbin.org/post"
    Then httpbin's "files" shows "file"

  Scenario: A missing file stops the send
    Given a file part for "~/Desktop/receipt.pdf"
    When I delete that file in Finder and press ⌘↩
    Then the chip turns red, with a warning glyph
    And the message line under the URL reads "Not sent. ~/Desktop/receipt.pdf is missing."
    And nothing reached the server
    When I put the file back and press ⌘↩
    Then the chip is normal again and the message is gone

  Scenario: A long path shows the file name only (break-ui)
    Given a file part for "~/Documents/receipt-1042.pdf"
    Then the chip reads "receipt-1042.pdf", not a reordered path
