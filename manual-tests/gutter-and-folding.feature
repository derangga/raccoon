# Manual acceptance: the Gutter and folding
#
# Run every Feature twice: macOS Appearance Light (Latte), then Dark (Mocha).
# Compare against board 02 (design/ui/mockups/02-get-200.html).
#
# Fixtures, in one terminal:
#   mkdir -p /tmp/rc && cd /tmp/rc
#   echo '{"id":1,"rating":{"rate":3.9,"count":120}}' > rating.json
#   printf '<a><b>x</b><c><d/></c></a>' > nested.xml
#   python3 -c "import json;print(json.dumps([{'id':i,'tags':['a','b']} for i in range(30000)]))" > many.json   # ~1 MB, 210,002 lines Pretty
#   python3 -c "import json;print(json.dumps([{'id':i,'tags':['a','b']} for i in range(140000)]))" > large.json  # ~4.8 MB
#   python3 -m http.server 8080
# Launch: swift run Raccoon


Feature: The Response Gutter
  Board 02

  Scenario: Pretty JSON is numbered, with a chevron on every line that opens a block
    Given a GET to "http://localhost:8080/rating.json" was sent
    Then the body reads, line by line:
      | {                   |
      |   "id": 1,          |
      |   "rating": {       |
      |     "rate": 3.9,    |
      |     "count": 120    |
      |   }                 |
      | }                   |
    And the Gutter numbers them 1 to 7 in textTertiary SF Mono, right-aligned, on the body's own background with no band or divider line
    And no chevron shows
    And a thin vertical guide in the border color runs from line 2 down to line 7 under "{", and from line 4 to line 6 under the quote of "rating"
    When I move the pointer over the Gutter
    Then a chevron pointing down appears right of 1 and of 3, between the number and the text, and nowhere else
    When I move the pointer back over the text
    Then both chevrons disappear
    And the Gutter is 50 pt wide

  Scenario: Raw is numbered and never folded
    Given the rating.json Response is shown
    When I pick "Raw"
    Then the body is the one line {"id":1,"rating":{"rate":3.9,"count":120}}
    And the Gutter shows "1" with no chevron
    And the body's context menu has no Fold items

  Scenario: XML folds by element
    Given a GET to "http://localhost:8080/nested.xml" was sent
    Then the lines read "<a>", "  <b>x</b>", "  <c>", "    <d/>", "  </c>", "</a>", numbered 1 to 6
    And chevrons sit beside 1 and 3 only
    When I hover the Gutter and click the chevron right of 3
    Then line 3 reads "  <c> … </c>" and the Gutter reads 1, 2, 3, 6

  Scenario: Many lines widen the Gutter
    Given a GET to "http://localhost:8080/many.json" was sent
    When I scroll to the end
    Then the last number is "210002", unclipped, and the Gutter is wider than 50 pt
    And scrolling stays smooth the whole way


Feature: Folding
  Board 02

  Scenario: The chevron folds a block onto its line
    Given the rating.json Response is shown in Pretty
    When I hover the Gutter and click the chevron right of 3
    Then line 3 reads   "rating": { … }
    And the "…" is textSecondary on the selection color, and the "}" keeps its punctuation color
    And the Gutter reads 1, 2, 3, 7, the chevron right of 3 pointing right, and it stays when the pointer leaves the Gutter
    And only the guide under "{" remains, running from line 2 to line 7
    And line 3 did not move on screen

  Scenario: Folding far down the body keeps the folded line where it was
    Given a GET to "http://localhost:8080/many.json" was sent and Pretty is on
    When I scroll down until the item with "id": 17 is in the middle of the view
    And I hover the Gutter and click the chevron right of that item's "{" (line 121)
    Then line 121 reads "  { … }," and has not moved on screen
    And the view did not jump to the top
    When I scroll right a little, then click the "…"
    Then the item is back, still in the same place, and the horizontal scroll is unchanged

  Scenario: Clicking the … unfolds it
    Given line 3 is folded
    When I click the "…"
    Then the seven lines are back, numbered 1 to 7, and both guides are back

  Scenario: Copy gives the whole body, folded lines included
    Given line 3 is folded
    When I click in the body, press ⌘A, then ⌘C, and paste into TextEdit
    Then TextEdit shows all seven lines, "rate" and "count" included
    When I select from "rating" through the "}" after the "…" and copy
    Then the paste is "rating": { followed by the rate and count lines and the closing }

  Scenario: Fold All and Unfold All
    Given the rating.json Response is shown in Pretty
    When I right-click the body
    Then the menu ends, after a separator, with "Fold ⌥⌘[", "Unfold ⌥⌘]", "Fold All", "Unfold All"
    When I pick "Fold All"
    Then the body is the one line "{ … }" and the Gutter reads "1" with the chevron pointing right
    When I pick "Unfold All" from the same menu
    Then the seven lines are back

  Scenario: ⌥⌘[ and ⌥⌘] fold and unfold around the caret
    Given the rating.json Response is shown in Pretty
    When I click inside "rate" on line 4 and press ⌥⌘[
    Then line 3 reads   "rating": { … }
    When I press ⌥⌘[ again
    Then the body is the one line "{ … }"
    When I press ⌥⌘]
    Then line 1 is "{" again and line 3 still reads   "rating": { … }
    When the URL field has the focus and I press ⌥⌘[
    Then the body does not change

  Scenario: Every send starts unfolded
    Given line 3 is folded
    When I press ⌘↩
    Then the new Response shows all seven lines
    When I fold line 3, pick "Raw", then pick "Pretty"
    Then all seven lines show

  Scenario: A large body stays responsive
    Given a GET to "http://localhost:8080/large.json" was sent and Pretty is on
    When I pick "Fold All", then click the chevron right of 1
    Then each item shows as one line "  { … }," within a blink
    When I scroll to the middle and then to the end
    Then nothing stalls
    When I pick "Unfold All"
    Then every line is back within a blink, and the line at the top stays at the top


Feature: The request body Gutter
  The Body editor

  Scenario: Numbers follow typing, with no chevrons
    Given the Body Type is raw JSON and the body is empty
    Then the Gutter shows "1"
    When I type {, Return, Return, }
    Then the Gutter reads 1, 2, 3 and no chevron is drawn
