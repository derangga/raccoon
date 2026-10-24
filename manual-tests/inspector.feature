# Manual acceptance: the inspector's frame, header and pane switch (M5)
#
# Run every Feature twice: macOS Appearance Light (Latte), then Dark (Mocha).
# Compare against board 11 "Inspector and sidebar filter" (design/ui/mockups/11-inspector-filter.html)
# and board 04 "Blocked by Undefined Variables" (04-undefined.html), the right-hand inspector.
#
# The Data Folder is a copy of manual-tests/collections.datafolder in /tmp, passed as a launch
# argument, so ~/Raccoon is never touched:
#   D=/tmp/raccoon-inspector
#   rm -rf "$D" && cp -R manual-tests/collections.datafolder "$D"
#   swift run Raccoon -DataFolder "$D"
# Quit with ⌘Q while the Raccoon window is in front.
#
# The Curl pane is not built yet, so its segment is disabled: board 11's Curl-selected header
# cannot be reached here. Only the Variables-selected header (board 11's right-hand card, and
# board 04) is checked.
#
# Accessibility checks use Accessibility Inspector (Xcode ▸ Open Developer Tool).


Feature: The inspector's frame and header
  Boards 04 and 11, in Latte and in Mocha

  Background:
    Given Raccoon is running on /tmp/raccoon-inspector, the window at least 1,200 pt wide

  Scenario: 1. The inspector opens on the right, on its own background
    Then the inspector is closed: the content reaches the window's right edge
    When I click the inspector toggle at the right end of the toolbar
    Then a pane about 280 pt wide opens on the right of the content
    And its background is the same shade as the Response pane's, not the request editor's
    And a 1 pt line in the border colour runs the full height of its left edge, down to the window's bottom

  Scenario: 2. The header lines up with the tab strip
    Given the inspector is open
    Then its header is 34 pt tall, its bottom rule level with the bottom of the tab strip on its left
    And on the left of the header "Variables" reads in 12 pt semibold, in the text colour
    And on the right of the header is a two-segment control, 8 pt in from the edge:
      | segment | glyph                | state                                                 |
      | 1       | curly braces { }     | selected: a filled selection background, glyph in text colour |
      | 2       | terminal >_          | disabled: glyph in the disabled (faint) colour, no fill |
    And each segment is 30 pt wide, inside one box with a 1 pt border and rounded corners
    And a 1 pt rule splits the two segments

  Scenario: 3. Each segment names its pane
    Given the inspector is open
    When I rest the pointer on the curly-braces segment
    Then a tooltip reads "Variables"
    When I rest the pointer on the terminal segment
    Then a tooltip reads "Curl"
    When I inspect the control with Accessibility Inspector
    Then it is a radio group labelled "Inspector pane" with two radio buttons, labelled "Variables" and "Curl"
    And "Variables" is selected and enabled, and "Curl" is not selected and not enabled

  Scenario: 4. The Curl segment waits for its pane
    Given the inspector is open
    When I click the terminal segment
    Then nothing changes: the header still reads "Variables", the curly braces stay selected
    And the Variables pane and its "Edit Environments…" button stay where they were

  Scenario: 5. The toggle closes it again
    Given the inspector is open
    When I click the inspector toggle
    Then the inspector closes and the content reaches the window's right edge again
