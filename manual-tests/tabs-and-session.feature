# Manual acceptance: Tabs and Session (M3)
#
# Run every Feature twice: macOS Appearance Light (Latte), then Dark (Mocha).
# Compare against the Raccoon UI canvas boards named in each Feature.
#
# The Session file is ~/Library/Application Support/Raccoon/session.json.
#   S=~/Library/Application\ Support/Raccoon
# Before each Feature, quit Raccoon (⌘Q) and reset it as the Feature's Background says.
# Launch: swift run Raccoon
#
# Nothing opens a Request Tab yet (that is the Collections epic), so a Dirty Tab only exists
# when a Session says so. manual-tests/tabs-and-session.session.json is that Session: a clean
# Request Tab, a Dirty one, a Draft (selected) and a Draft on a slow URL.
#   cp manual-tests/tabs-and-session.session.json "$S/session.json"
#
# Accessibility checks use Accessibility Inspector (Xcode ▸ Open Developer Tool).
# Log checks: log show --last 5m --predicate 'subsystem == "Raccoon"' --style compact


Feature: The tab strip
  Board 05 "Several Tabs", in Latte and in Mocha

  Background:
    Given Raccoon is quit and the fixture Session is copied to session.json
    And Raccoon is launched in a 1200 × 760 window

  Scenario: Rest, selected, Dirty and Draft
    Then the strip is 34 pt tall, over the URL bar, in backgroundRecessed with a 1 pt border under it
    And it shows four Tabs, left to right:
      | badge | name                     | slot                       |
      | GET   | /anything/charges        | empty                      |
      | POST  | /anything/charges/create | an 8 pt dot in dirtyDot    |
      | POST  | /anything/v1/webhooks    | empty, the name in italic  |
      | HEAD  | /delay/8                 | empty, the name in italic  |
    And the third and fourth Tabs have a 6 pt accent dot before the badge, and the first two have none
    And a + button sits right after the last Tab
    And each Tab is 196 pt wide with a 1 pt border on its right
    And the third Tab is selected: background, name in text, a 2 pt accent rule on top, no border under it
    And the others have their names in textSecondary
    And each badge is SF Mono bold 10 pt in its method's color, as on board 05
    And the URL bar shows the selected Tab: POST and "https://httpbin.org/anything/v1/webhooks"

  Scenario: Hover
    When I move the pointer over the second Tab
    Then its background is rowHover and its dot is replaced by a ✕ on a selection-colored square
    When I move the pointer over the first Tab
    Then the second Tab shows its dot again, and the first shows a ✕
    When I move the pointer off the strip
    Then no Tab shows a ✕

  Scenario: Selecting a Tab
    When I click the first Tab
    Then it is selected and the URL bar reads GET "https://httpbin.org/anything/charges"
    When I press ⌘3
    Then the third Tab is selected again, with its editor section, scroll and selection as I left them

  Scenario: Sending shows the spinner after 150 ms
    When I select the fourth Tab and press ⌘↩
    Then after about 150 ms its HEAD badge is replaced by a small spinner that fades in
    And the name "/delay/8" stays where it was
    When I press ⌘.
    Then the spinner is gone and the HEAD badge is back
    When I select the first Tab, set the URL to "http://localhost:9" and press ⌘↩
    Then the send fails at once and no spinner ever shows

  Scenario: New Tab from the + button
    When I click +
    Then a fifth Tab appears right after the selected one, with the accent dot, badge GET and the italic name "Draft"
    And it is selected, and the URL field is empty
    And no Tab moved with an animation

  Scenario: Accessibility
    When I inspect the strip in Accessibility Inspector
    Then it is a tab group labelled "Tabs" holding four tab buttons
    And their titles and values are:
      | title                         | value  |
      | GET /anything/charges         |        |
      | POST /anything/charges/create | Edited |
      | POST /anything/v1/webhooks    | Draft  |
      | HEAD /delay/8                 | Draft  |
    And the third is the selected one
    When I send from the fourth Tab and inspect it again while it sends
    Then its value reads "Draft, Sending"

  Scenario: The Flavor follows the appearance
    When I switch macOS between Light and Dark while Raccoon is open
    Then the strip, every Tab, the dot, the ✕ square, the accent rule and the badges change to the other Flavor at once
    And no color from the old Flavor is left anywhere on the strip


Feature: Many Tabs and long names
  Board 10 "break-ui: worst case", in Latte and in Mocha

  Background:
    Given Raccoon is quit and session.json is deleted
    And Raccoon is launched in a 1200 × 760 window

  Scenario: 30 Tabs scroll
    When I press ⌘T 29 times
    Then there are 30 Tabs, each 104 pt wide except the selected last one, which is 168 pt
    And the strip scrolls sideways with a two-finger swipe, and the + stays pinned at its right end
    And both ends of the strip fade out over 24 pt
    And the selected 30th Tab is fully in view
    When I press ⌘1
    Then the strip scrolls so the first Tab is fully in view, and it is selected
    When I press ⌃⇧⇥
    Then the strip scrolls back so the 30th Tab is fully in view

  Scenario: Shrinking before scrolling
    Given there are 6 Tabs
    When I drag the window narrower
    Then the Tabs shrink together from 196 pt, the selected one stopping at 168 pt and the others at 104 pt
    And only once they cannot shrink further does the strip start to scroll and fade

  Scenario: A Japanese and emoji name
    When I type "https://api.example.com/請求書の一覧を取得する/🦝 Webhooks テスト 🚀" into the URL field
    Then the Tab's name is the path, ending in "…" where it no longer fits, still in italic
    And the accent dot before the badge marks it as a Draft, though the Japanese has no italic
    And hovering the Tab shows a tooltip with the whole path "/請求書の一覧を取得する/🦝 Webhooks テスト 🚀"


Feature: The close prompt
  surfaces.md §8 CloseConfirm, design-system.md §6 Close confirmation

  Background:
    Given Raccoon is quit and the fixture Session is copied to session.json
    And Raccoon is launched

  Scenario: An empty Draft closes without asking
    Given the third Tab is selected
    When I press ⌘T and then ⌘W
    Then the new Tab is gone with no prompt
    And the Tab that was after it, "/delay/8", is selected

  Scenario: A non-empty Draft asks, and Cancel keeps it
    Given the third Tab is selected and I click into the URL field
    When I press ⌘W
    Then a sheet slides down from the window's title bar, not a separate window
    And it reads "Close “/anything/v1/webhooks” without saving?"
    And under it "This Draft hasn't been saved. Its request will be lost."
    And its buttons read "Don't Save" in red, then "Cancel", and there is no Save button
    When I press Return
    Then nothing happens
    When I press Esc
    Then the sheet is gone, the Tab is still open and selected, and the caret is back in the URL field
    When I press ⌘W again and click Cancel
    Then the same happens

  Scenario: Don't Save closes and selects the neighbour
    Given the third Tab is selected
    When I press ⌘W and then ⌘D
    Then the third Tab is gone with no animation
    And the fourth Tab, "/delay/8", which was after it, is selected

  Scenario: A Dirty Tab asks; a clean one does not
    When I hover the second Tab and click its ✕
    Then the sheet asks "Close “/anything/charges/create” without saving?"
    And under it "Your edits to this Request haven't been saved and will be lost."
    When I click Don't Save
    Then that Tab is gone
    When I hover the first Tab and click its ✕
    Then it closes with no prompt

  Scenario: Closing a sending Tab stops the send
    Given the fourth Tab, "/delay/8", is selected
    When I press ⌘↩, wait until the spinner shows, then press ⌘W and ⌘D
    Then the Tab is gone, and nothing appears later in any other Tab's Response

  Scenario: One prompt at a time
    Given the prompt is showing
    When I press ⌘W again
    Then no second sheet appears


Feature: Closing the last Tab
  Open UI Q1 (decided): it opens an empty Draft

  Scenario: The last Tab becomes an empty Draft
    Given Raccoon is quit, session.json is deleted, and Raccoon is launched
    And I type "https://httpbin.org/get" into the URL field
    When I press ⌘W, then ⌘D
    Then one Tab remains, with the accent dot, badge GET, the italic name "Draft", selected
    And the URL field is empty and the Response reads "Send a request to see the Response here."
    And the window stays open


Feature: Quit and relaunch with Drafts
  tabs.md §quit and §relaunch

  Scenario: Three Drafts come back as they were
    Given Raccoon is quit, session.json is deleted, and Raccoon is launched
    When I type "https://httpbin.org/anything/one" into the URL field
    And I press ⌘T and type "https://httpbin.org/anything/two"
    And I press ⌘T and type "https://httpbin.org/anything/three"
    And I press ⌘2
    And I press ⌘Q within one second of the last keystroke
    Then Raccoon quits with no prompt
    When I launch Raccoon again
    Then the strip shows "/anything/one", "/anything/two", "/anything/three", all italic, in that order
    And "/anything/two" is selected and its URL field reads "https://httpbin.org/anything/two"
    And every Response reads "Send a request to see the Response here."

  Scenario: A Dirty Tab survives quit without a prompt
    Given Raccoon is quit, the fixture Session is copied to session.json, and Raccoon is launched
    When I select the first Tab, change its URL to "https://httpbin.org/anything/charges?limit=5", and press ⌘Q at once
    Then Raccoon quits with no prompt
    When I launch Raccoon again
    Then the first Tab shows the dirtyDot and its URL field reads "https://httpbin.org/anything/charges?limit=5"
    And the second Tab still shows its dot and the badge POST

  Scenario: An unwritable Session does not stop quit
    Given Raccoon is open
    When I run: chmod 500 "$S" && rm -f "$S/session.json"
    And I press ⌘Q
    Then Raccoon quits at once
    And the log has a line with "Session not written on quit to" and the session.json path
    And afterwards I run: chmod 755 "$S"


Feature: A corrupt session.json
  Open UI Q7 (decided): silent; e-where-it-breaks.md §Session

  Scenario: Renamed, not deleted, and nothing on screen
    Given Raccoon is quit
    When I run: printf '{ not json' > "$S/session.json"
    And I launch Raccoon
    Then the window looks like board 01: one Tab, the accent dot, GET, the italic name "Draft", selected
    And no banner, alert or message says anything about the Session
    And ls "$S" shows a file named like "session.corrupt-2026-10-19T091500Z.json" holding "{ not json"
    And the log has "is undecodable" and "Session set aside as" with that path
    When I type a URL and quit
    Then a new session.json holds that Draft, and the corrupt file is still there


Feature: No session.json
  Board 01 "First launch", in Latte and in Mocha

  Scenario: First launch
    Given Raccoon is quit and session.json is deleted
    When I launch Raccoon
    Then the strip shows one 196 pt Tab, selected: the accent dot, badge GET in the GET color, the italic name "Draft", empty slot
    And a + button sits right after it
    And the URL field is empty, the Response reads "Send a request to see the Response here." with ⌘↩
    And the window matches board 01
    And no session.json exists until I change something
