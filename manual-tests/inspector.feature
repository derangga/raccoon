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

# Variables pane
#
# Boards 04 ("Blocked by Undefined Variables") and 11 ("Inspector and sidebar filter"):
#   open design/ui/mockups/04-undefined.html design/ui/mockups/11-inspector-filter.html
# Run the whole section twice: once with macOS Appearance set to Light (System Settings ▸
# Appearance ▸ Light), which is Latte, and once with Dark, which is Mocha. Compare with the
# board's Latte column on the first run and its Mocha column on the second. Do "Before you
# start" before each run.
#
# The colours, as the Theme names them:
#   red, wavy line     a name nothing defines (variableUndefined)
#   mauve, lock        a Secret Variable (variableSecret)
#   grey, struck out   a Global the Active Environment overrides (textDisabled)
#
# ─── How launching works ──────────────────────────────────────────────────────────────────
#
# In Terminal A, inside the project folder:
#   cd ~/Documents/playground/raccoon
#   swift run Raccoon -DataFolder /tmp/raccoon-inspector
# Quit with ⌘Q while the Raccoon window is in front.
#
# ─── Before you start (once per run) ──────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder (the commands work in fish, zsh and bash):
#   cd ~/Documents/playground/raccoon
#   swift build
#   rm -rf /tmp/raccoon-inspector
#   mkdir -p /tmp/raccoon-inspector/environments
#   echo '{"version": 1, "variables": [{"name": "host", "value": "http://localhost:4000"}, {"name": "user_agent", "value": "Raccoon/1.0"}]}' > /tmp/raccoon-inspector/globals.json
#   echo '{"version": 1, "variables": [{"name": "host", "value": "https://api.staging.payments.example.com"}, {"name": "api_key", "secret": true}, {"name": "region", "value": "eu-central-1"}, {"name": "old", "value": "gone", "isEnabled": false}]}' > /tmp/raccoon-inspector/environments/Staging.json
#   python3 -c 'import json; v=[{"name": "var_%03d" % i, "value": "value %d" % i} for i in range(200)]; v[0]["value"]="https://api.staging.payments.example.com/" + "segment/"*40; print(json.dumps({"version": 1, "variables": v}))' > /tmp/raccoon-inspector/environments/Load.json
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/353066d416b9f07d.json
# "swift build" should end with "Build complete!". The other commands print nothing.
#
# ─── When you are done ────────────────────────────────────────────────────────────────────
#
# Quit Raccoon. In Terminal B:
#   rm -rf /tmp/raccoon-inspector
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/353066d416b9f07d*

Feature: The Variables pane
  Boards 04 and 11

  Background:
    Given Raccoon is running on /tmp/raccoon-inspector (see "How launching works")

  Scenario: 1. Board 04: Not defined first, then Staging, then Globals with the overridden one struck out
    Given I chose "Staging" from the Environment pop-up
    When I type in the URL field: {{host}}/v1/charges/{{charge_id}}
    And in the Headers table I add a row named X-Tenant with the value {{tenant_id}}
    And I click the "Show Inspector" button at the right end of the toolbar
    Then the inspector opens on the right, its header reads "Variables", and the Variables segment of its switch is on
    And the Curl segment is greyed out
    And the pane reads, top to bottom:
      | group title                                        | name       | value                                    |
      | (error glyph) Not defined · used by this Tab        | charge_id  | URL                                      |
      |                                                    | tenant_id  | Headers                                  |
      | Staging · Active Environment                       | host       | https://api.staging.payments.example.com |
      |                                                    | api_key    | (lock) Secret                            |
      |                                                    | region     | eu-central-1                             |
      | Globals                                            | host       | http://localhost:4000                    |
      |                                                    | user_agent | Raccoon/1.0                              |
    And under the table, in small grey text: A struck-out Global is overridden by Staging. Disabled Variables are not listed.
    And "old" is not listed anywhere
    And the "Not defined · used by this Tab" title, its glyph, charge_id, tenant_id, "URL" and "Headers" are red
    And charge_id and tenant_id each have a red wavy line under them
    And api_key's value is a lock and "Secret" in mauve, with no dots or characters of a value
    And the Globals row "host" is grey, with a line through both its name and its value
    And holding the pointer over that struck-out "host" name shows the tooltip "Overridden by Staging"
    And the footer holds one button, "Edit Environments…", at the right
    And colours and layout match board 04's inspector in this run's column (Latte or Mocha)

  Scenario: 2. Board 11: No Environment points at the toolbar
    Given the pane from scenario 1 is open
    When I choose "No Environment" from the Environment pop-up
    Then the first title still reads "Not defined · used by this Tab" with charge_id and tenant_id
    And the next title reads "No Environment · pick one in the toolbar", with no rows under it
    And the Globals rows "host" (http://localhost:4000) and "user_agent" (Raccoon/1.0) are no longer struck out
    And the line "A struck-out Global is overridden by …" is gone
    When I press ⌘T
    Then the pane shows the new, empty Tab: the "Not defined" group is gone
    And the pane reads "No Environment · pick one in the toolbar", then "Globals" with host and user_agent
    And colours and layout match board 11's "Variables: No Environment" card in this run's column

  Scenario: 3. "No Globals."
    Given the pane from scenario 2 is open, on the new Tab, with No Environment
    When in Terminal B I run: echo '{"version": 1, "variables": []}' > /tmp/raccoon-inspector/globals.json
    Then within a second, under the "Globals" title, grey text reads "No Globals."
    And "No Environment · pick one in the toolbar" is still above it

  Scenario: 4. 200 Variables scroll, and a long value end-truncates (break-ui)
    Given the pane from scenario 3 is open
    When I choose "Load" from the Environment pop-up
    Then the title reads "Load · Active Environment" and rows var_000, var_001, … follow
    When I scroll down in the pane with the trackpad or mouse wheel
    Then the rows scroll smoothly down to var_199, then "Globals" and "No Globals." at the bottom
    And every row is the same height, with a thin rule under it
    When I scroll back to the top
    Then var_000's value starts "https://api.staging.payments.example.com/segment/" and ends in "…" at the pane's right edge
    And it does not wrap onto a second line or run under the scroll bar
    When I hold the pointer over that value
    Then a tooltip shows the whole value, ending in "segment/segment/"

  Scenario: 5. Edit Environments… opens the sheet on the Active Environment
    Given the pane from scenario 4 is open, with "Load" active
    When I choose "Staging" from the Environment pop-up
    And I click "Edit Environments…" at the bottom of the inspector
    Then the "Environments" sheet slides down with "Staging" selected in its list
    And its table holds host, api_key (secret), region, and old (unticked)
    When I click "Done"
    Then the sheet closes and the pane still shows "Staging · Active Environment"

# ─── Known simplifications ────────────────────────────────────────────────────────────────
#
# - "No Keychain read while the pane renders" is checked by the automated tests, not here:
#   there is nothing to see. If macOS ever asks for Keychain access while you only look at the
#   pane, that is a failure; note it.
# - The pane's values edit in place (one click on a value); those checks are not in this
#   section. Names, enabling and secrets are edited in the Environments sheet only.
# - The wavy line under a Not defined name was placed by calculation, not checked on screen.
#   Look at it closely next to the board.
# - variables.feature has no Variables pane scenario to reuse: its scenario 32 scrolls 200
#   Variables in the Environments sheet, not in this pane.
