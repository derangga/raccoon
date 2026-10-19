# Manual acceptance: Curl (M2)
#
# Run every Feature twice: macOS Appearance Light (Latte), then Dark (Mocha).
# Compare against the Raccoon UI canvas boards named in each Feature.
#
# Fixtures, in one terminal:
#   mkdir -p /tmp/rc && cd /tmp/rc
#   echo '{"a":1}' > small.json
#   head -c 48200 /dev/urandom > bin.dat
# httpbin.org echoes what was sent.
# Launch: swift run Raccoon
#
# Every paste lands in the current Tab: Tabs cannot be opened yet, so a paste over a Tab that
# already holds a request replaces it instead of opening a new Draft Tab.
# To paste a command below, copy it from this file without the leading spaces. A command
# shown on several lines is pasted as one block.


Feature: Curl Import fills the Tab
  Board 03

  Scenario: The board 03 command
    Given a fresh window
    When I paste into the URL field:
      curl --retry 3 -s -X POST 'https://api.payments.example.com/v1/charges' -H 'Authorization: Bearer sk_test_123' -H 'Content-Type: application/json' -b 'session=abc; theme=dark' --data-raw '{"amount":1200,"currency":"usd"}'
    Then the method reads "POST" in the POST color
    And the URL field reads "https://api.payments.example.com/v1/charges", with the caret at the end and nothing selected
    And the note under the URL bar reads "Ignored: --retry, -s", with an info glyph and a ✕
    And the sections read "Params", "Headers 1", "Body", "Auth Bearer", "Cookies 2", "Settings"
    And Headers holds "Content-Type: application/json" and no Authorization row
    And Auth is Bearer with the Token "sk_test_123"
    And Cookies holds "session = abc" and "theme = dark", both checked
    And Body is raw JSON reading {"amount":1200,"currency":"usd"}
    And the whole window matches board 03

  Scenario: The note goes away
    Given the board 03 note is showing
    When I click its ✕
    Then the note is gone
    When I paste the board 03 command again and type one character in the URL field
    Then the note is gone

  Scenario: A Chrome "Copy as cURL" command
    Given a fresh window
    When I open any page in Chrome, right-click a request in DevTools ▸ Network, pick Copy ▸ Copy as cURL, and paste it into the URL field
    Then the URL field shows only the URL, and none of the command's text is in it
    And Headers lists the command's -H headers in the order they were written
    And a Cookie header, if the command had one, is in Cookies as rows and not in Headers
    When I press ⌘↩
    Then the request is sent and a status shows

  Scenario: Basic Auth and the two settings
    When I paste "curl -u alice:s3cret -L -k https://httpbin.org/basic-auth/alice/s3cret"
    Then Auth is Basic with Username "alice" and Password "s3cret"
    And Settings has "Allow insecure TLS" and "Follow redirects" both checked
    And there is no note
    When I press ⌘↩
    Then the status is 200 and the body holds "authenticated": true

  Scenario: -G moves data into Params
    When I paste "curl -G -d q=raccoon -d page=2 https://httpbin.org/get"
    Then the method is GET and the Body is none
    And the URL field reads "https://httpbin.org/get?q=raccoon&page=2" and the section reads "Params 2"

  Scenario: Form data is decoded into rows
    When I paste "curl -d 'name=Ada%20L&token=abc==' https://httpbin.org/post"
    Then the method is POST and the Body is form-urlencoded with "name = Ada L" and "token = abc=="
    And Headers shows Content-Type only as an automatic, greyed-out row
    When I press ⌘↩
    Then the response's "form" holds "name": "Ada L" and "token": "abc=="

  Scenario: --json adds its two headers
    When I paste "curl --json '{"a":1}' https://httpbin.org/post"
    Then Headers holds "Content-Type: application/json" then "Accept: application/json"
    And Body is raw JSON reading {"a":1}

  Scenario: Multipart parts
    When I paste "curl -F name=Ada -F doc=@/tmp/rc/small.json https://httpbin.org/post"
    Then Body is multipart with a text part "name" = "Ada" and a file part "doc" with a chip for "small.json"
    When I press ⌘↩
    Then the response's "files" holds "doc" and its "form" holds "name": "Ada"

  Scenario: A URL with no scheme
    When I paste "curl httpbin.org/get"
    Then the URL field reads "http://httpbin.org/get"

  Scenario: An empty header
    When I paste "curl -H 'X-Empty;' https://httpbin.org/headers"
    Then Headers holds "X-Empty" with an empty value


Feature: Curl Import notes
  The message line under the URL bar, design-system §6

  Scenario: Flags Raccoon does not use
    When I paste "curl --compressed -b cookies.txt https://httpbin.org/get"
    Then the note reads "Ignored: --compressed, --cookie" and Cookies is empty
    When I paste "curl --digest -u alice:s3cret https://httpbin.org/get"
    Then Auth is Basic with Username "alice" and the note reads "Ignored: --digest"

  Scenario: More than one command
    When I paste, as one block:
      curl https://httpbin.org/get?n=1
      curl https://httpbin.org/get?n=2
    Then the URL field reads "https://httpbin.org/get?n=1" and the note reads "1 more command"
    When I paste the same block with a third line "curl https://httpbin.org/get?n=3"
    Then the note reads "2 more commands"
    When I paste "curl --retry 3 -s https://h/a" followed by two more curl lines, as one block
    Then the note reads "Ignored: --retry, -s. 2 more commands"

  Scenario: A data file is read as the body
    When I paste "curl -H 'Content-Type: application/json' --data-binary @/tmp/rc/small.json https://httpbin.org/post"
    Then Body is raw JSON reading {"a":1} and there is no note

  Scenario: A data file that cannot be used
    When I paste "curl --data-binary @/tmp/rc/bin.dat https://h"
    Then Body is none and the note reads "/tmp/rc/bin.dat is not text, and binary bodies are not supported"
    When I paste "curl --data-binary @/tmp/rc/gone.json https://h"
    Then Body is none and the note reads "/tmp/rc/gone.json was not read"

  Scenario: A multipart file that is missing keeps its path
    When I paste "curl -F doc=@/tmp/rc/gone.pdf https://httpbin.org/post"
    Then Body is multipart with a file part "doc" for "gone.pdf", and there is no note
    When I press ⌘↩
    Then the message line reads "Not sent. /tmp/rc/gone.pdf is missing." in the error color
    And the "gone.pdf" chip is marked in the error color

  Scenario: A GET with a body
    When I paste "curl -X GET -d a=1 https://httpbin.org/get"
    Then the method is GET and the Body is form-urlencoded with "a = 1"
    And the note reads "A GET with a body won't send: macOS refuses it. Change the method or remove the body."
    When I paste "curl -X DELETE -d a=1 https://httpbin.org/delete"
    Then there is no note
    When I paste "curl -G -d a=1 https://httpbin.org/get"
    Then there is no note and the section reads "Params 1"


Feature: Curl Import errors
  design/e-where-it-breaks.md §Curl Import

  Scenario: An unterminated quote
    Given the URL field holds "https://httpbin.org/get"
    When I paste "curl 'https://h"
    Then the message line reads "Unterminated quote in this curl command, at character 6." in the error color, with no ✕
    And the URL field still reads "https://httpbin.org/get" and nothing was inserted

  Scenario: No URL
    When I paste "curl -s"
    Then the message line reads "No URL in this curl command."
    And the request is unchanged

  Scenario: The error clears on the next send or paste
    Given the message line shows "No URL in this curl command."
    When I type in the URL field
    Then the error stays
    When I paste "curl https://httpbin.org/get"
    Then the error is gone

  Scenario: Text that is not curl
    When I paste "https://httpbin.org/get?a=1" into the URL field
    Then it is inserted as text at the caret, and the section reads "Params 1"


Feature: Undo of a Curl Import
  design/behavior.md §7

  Scenario: One ⌘Z undoes the whole import
    Given a fresh window and the focus in the URL field
    When I paste the board 03 command
    And I press ⌘Z once
    Then the method is GET, the URL field is empty, every section is empty and the note is gone
    When I press ⇧⌘Z
    Then the board 03 request and its note are back

  Scenario: Undo after a failed paste
    Given the URL field holds "https://httpbin.org/get" typed by hand
    When I paste "curl -s" and press ⌘Z
    Then the undo takes back my typing, not an import: the request was never changed by the paste


Feature: Copy as Curl
  Board 11 (the command's layout); Edit menu and the URL bar's menus

  Scenario: The menu item
    Given a fresh window with the focus in the URL field
    When I open the Edit menu
    Then it ends with a separator and "Copy as Curl", shortcut ⇧⌘C, disabled
    When I type "https://httpbin.org/get?b=1"
    Then Edit ▸ Copy as Curl is enabled

  Scenario: Copying a simple GET
    Given the URL field reads "https://httpbin.org/get?b=1"
    When I press ⇧⌘C
    Then pasting into TextEdit gives exactly:
      curl 'https://httpbin.org/get?b=1'

  Scenario: Copying the board 03 request
    Given I pasted the board 03 command
    When I pick Edit ▸ Copy as Curl
    Then pasting into TextEdit gives exactly:
      curl -X POST 'https://api.payments.example.com/v1/charges' \
        -H 'Content-Type: application/json' \
        -H 'Authorization: Bearer sk_test_123' \
        -b 'session=abc; theme=dark' \
        --data-raw '{"amount":1200,"currency":"usd"}'
    And the ignored flags --retry and -s are not in it

  Scenario: Basic Auth, settings, form rows and multipart
    When I paste "curl -u alice:s3cret -L -k https://httpbin.org/basic-auth/alice/s3cret" and press ⇧⌘C
    Then the copied text is:
      curl 'https://httpbin.org/basic-auth/alice/s3cret' \
        -H 'Authorization: Basic YWxpY2U6czNjcmV0' \
        -k \
        -L
    When I paste "curl -d 'name=Ada%20L&token=abc==' https://httpbin.org/post" and press ⇧⌘C
    Then the copied text is:
      curl -X POST 'https://httpbin.org/post' \
        --data-urlencode 'name=Ada L' \
        --data-urlencode 'token=abc=='
    When I paste "curl -F name=Ada -F doc=@/tmp/rc/small.json https://httpbin.org/post" and press ⇧⌘C
    Then the copied text is:
      curl -X POST 'https://httpbin.org/post' \
        -F 'name=Ada' \
        -F 'doc=@/tmp/rc/small.json'

  Scenario: Disabled rows are left out
    Given the board 03 request
    When I uncheck the "theme" cookie and the Content-Type header, then press ⇧⌘C
    Then the copied text has "-b 'session=abc'" and no Content-Type line

  Scenario: The copied command runs in Terminal
    Given the form-urlencoded request above was copied
    When I paste it into Terminal and press Return
    Then httpbin answers with "form": {"name": "Ada L", "token": "abc=="}

  Scenario: The round trip
    Given the board 03 request and I pressed ⇧⌘C
    When I paste the copied text back into the URL field
    Then every section reads as it did before the copy, and there is no note

  Scenario: The URL bar's menus
    When I right-click inside the URL field
    Then the text menu ends with a separator and "Copy as Curl"
    When I right-click an empty part of the URL bar, outside the field and the buttons
    Then a menu with "Copy as Curl" opens
    And both items copy the same text as ⇧⌘C

  Scenario: Nothing to copy
    Given a fresh window
    Then Copy as Curl is disabled in the Edit menu and in the URL field's menu
    When I type "not a url"
    Then it is still disabled

  Scenario: Copy as Curl never touches the request
    Given the board 03 request
    When I press ⇧⌘C
    Then no section changed, and ⌘Z takes back the import, not the copy
