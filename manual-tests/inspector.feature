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
      | 2       | terminal >_          | not selected: no fill                                   |
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
    And "Variables" is selected and enabled, and "Curl" is not selected and enabled

  Scenario: 4. The Curl segment opens the Curl pane
    Given the inspector is open
    When I click the terminal segment
    Then the header reads "Curl" and the terminal segment is selected
    And the Variables pane and its "Edit Environments…" button are gone, the Curl pane in their place
    When I click the curly-braces segment
    Then the header reads "Variables" and the Variables pane is back

  Scenario: 5. The toggle closes it again
    Given the inspector is open
    When I click the inspector toggle
    Then the inspector closes and the content reaches the window's right edge again


# Curl pane
#
# Board 11's left-hand window and its "Curl: blocked by Undefined Variables" card. Run every
# Scenario in Latte, then again in Mocha. Same Data Folder and launch as above.
#
# Setup, once: Edit Environments… ▸ Dev, add "host" = "https://api.dev.payments.example.com"
# and "api_key" = "sk_live_1" marked secret. Pick Dev in the toolbar. Then ⌘T and paste into
# the URL field, as one line:
#   curl -X POST 'https://api.dev.payments.example.com/v1/refunds' -H 'Content-Type: application/json' -H 'Authorization: Bearer {{api_key}}' -b 'session=7f3a; locale=en' --data-raw '{"charge":"ch_3PqL8x2e","amount":500}'
#
# Known simplifications: with no command the footer holds only Copy (as on board 11's card);
# Include secrets is off again at every launch; a secret the Keychain cannot read makes Copy
# with Include secrets copy nothing.


Feature: The Curl pane
  Board 11, in Latte and in Mocha

  Background:
    Given Raccoon is running on /tmp/raccoon-inspector with the setup above
    And the pasted Tab is selected, the inspector open on its terminal segment

  Scenario: 6. The command, as board 11 draws it
    Then the header reads "Curl"
    And under it, in a box with 6 pt rounded corners, a 1 pt border and the editor's background, reads in 11 pt monospace:
      """
      curl -X POST 'https://api.dev.payments.example.com/v1/refunds' \
        -H 'Content-Type: application/json' \
        -H 'Authorization: Bearer {{api_key}}' \
        -b 'session=7f3a; locale=en' \
        --data-raw '{"charge":"ch_3PqL8x2e","amount":500}'
      """
    And "curl", "-H", "-b" and "--data-raw" are dimmer than the rest of the text
    And "{{api_key}}" is in the secret colour with a dotted underline, and "sk_live_1" is nowhere in the pane
    And long lines wrap inside the box, mid-word where needed, with nothing cut off
    And under the box, in small tertiary text: "Resolved with Dev. Disabled Rows are left out."
    And the footer holds an unchecked "Include secrets" checkbox on the left and "Copy" in the accent colour on the right

  Scenario: 7. Copy leaves the secret as {{name}}
    When I click "Copy" and paste into TextEdit
    Then the pasted text is exactly the command in scenario 6

  Scenario: 8. Include secrets fills the secret in the copied text only
    When I check "Include secrets"
    Then the pane still reads "Bearer {{api_key}}"
    When I click "Copy" and paste into TextEdit
    Then the pasted text reads "Bearer sk_live_1" where the pane reads "Bearer {{api_key}}", and every other character is the same
    When I quit with ⌘Q and launch again
    Then "Include secrets" is unchecked

  Scenario: 9. It follows every edit, the Active Environment and the selected Tab
    When I uncheck the "Content-Type" row in Headers
    Then the "-H 'Content-Type: application/json'" line leaves the pane at once
    When I change the URL to "{{host}}/v1/refunds"
    Then the first line still reads "curl -X POST 'https://api.dev.payments.example.com/v1/refunds' \"
    When I pick No Environment in the toolbar
    Then the pane reads "No curl command yet" and "host is not defined in Globals."
    And there is no note under it
    When I pick Dev again
    Then the command is back, and the note reads "Resolved with Dev. Disabled Rows are left out."
    When I click another Tab, then this one again
    Then the pane shows that Tab's command, then this one's

  Scenario: 10. Undefined Variables block the command
    When I change the URL to "https://api.dev.payments.example.com/v1/charges/{{charge_id}}"
    And I add a header "X-Tenant" with the value "{{tenant_id}}"
    Then the box and its note are gone; centred in the pane are a red circled "!" and "No curl command yet" in red semibold
    And under them, in tertiary text: "charge_id and tenant_id are not defined in Dev or in Globals."
    And the footer holds only "Copy", in faint text with no accent fill, and clicking it does nothing
    And "Include secrets" is not shown
    And the pane matches board 11's "Curl: blocked by Undefined Variables" card

  Scenario: 11. An invalid URL is quoted
    When I change the URL to "localhost:4000/a"
    Then the pane reads "No curl command yet" and "After substitution the URL was localhost:4000/a."
    And "Copy" is disabled

  Scenario: 12. An empty Draft asks for a URL
    When I press ⌘T
    Then the pane reads only "Type a URL to see the curl command.", centred, in tertiary text, with no glyph
    And "Copy" is disabled and "Include secrets" is not shown
    When I type "https://h/a"
    Then the pane reads "curl 'https://h/a'" and "Copy" is in the accent colour

  Scenario: 13. A 2,000-character URL and a 20 KB body wrap and scroll
    When I set the URL to "https://h/" followed by 1,990 "a"s
    And I set the Body to raw JSON and paste 20 KB of text into it
    Then the URL wraps across many lines inside the box, with no horizontal scroll bar
    And the box scrolls down to the body's closing "'"
    When I click "Copy" and paste into TextEdit
    Then TextEdit holds the whole command, ending with the body's last character and "'"

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

# Shortcuts
#
# Four keys open or focus a part of the window, and each is listed on its menu item:
#   ⌥⌃E   View ▸ Edit Environments…     opens the Environments sheet
#   ⌥⌘F   Edit ▸ Find ▸ Filter Collections   focuses the sidebar filter
#   ⌥⌘I   View ▸ Show Inspector          shows or hides the inspector
#   ⌃⌘S   View ▸ Show Sidebar            shows or hides the sidebar
# ⌘F stays Edit ▸ Find ▸ Find…, the system find bar over the body you are typing in or reading.
# In a menu, ⌃ is drawn as ^, ⌥ as the option glyph and ⌘ as the command glyph, in the order
# ⌃⌥⇧⌘ whatever order this file writes them in. Scenario 6 sends a request to httpbin.org,
# so it needs a network connection.
#
# ─── How launching works ──────────────────────────────────────────────────────────────────
#
# In Terminal A, inside the project folder:
#   cd ~/Documents/playground/raccoon
#   swift run Raccoon -DataFolder /tmp/raccoon-shortcuts
# Quit with ⌘Q while the Raccoon window is in front.
#
# ─── Before you start (once) ──────────────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder (the commands work in fish, zsh and bash):
#   cd ~/Documents/playground/raccoon
#   swift build
#   rm -rf /tmp/raccoon-shortcuts
#   cp -R manual-tests/collections.datafolder /tmp/raccoon-shortcuts
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/0cedfa846a35250d.json
# "swift build" should end with "Build complete!". The other commands print nothing.
#
# ─── When you are done ────────────────────────────────────────────────────────────────────
#
# Quit Raccoon. In Terminal B:
#   rm -rf /tmp/raccoon-shortcuts
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/0cedfa846a35250d*

Feature: Shortcuts for the sheet, the filter, the inspector and the sidebar

  Background:
    Given Raccoon is running on /tmp/raccoon-shortcuts (see "How launching works")
    And the window is at least 1,200 pt wide (double-click its title bar to zoom it if not)

  Scenario: 1. Each shortcut is listed on its menu item
    When I open the View menu
    Then "Hide Sidebar" (the sidebar is open) shows ⌃⌘S at its right
    And "Show Inspector" shows ⌥⌘I at its right
    And "Edit Environments…" shows ⌃⌥E at its right
    When I open the Edit menu and point at "Find"
    Then its submenu holds "Find…" with ⌘F and "Filter Collections" with ⌥⌘F

  Scenario: 2. ⌃⌘S hides and shows the sidebar, and the menu item says which
    When I press ⌃⌘S
    Then the sidebar closes and the "Show Sidebar" button at the left of the toolbar is no longer pressed
    And the View menu's first item reads "Show Sidebar"
    When I press ⌃⌘S again
    Then the sidebar opens again, as wide as before, and the toolbar button is pressed
    And the View menu's first item reads "Hide Sidebar"

  Scenario: 3. ⌥⌘I shows and hides the inspector, and the menu item says which
    When I press ⌥⌘I
    Then the inspector opens on the right and the "Show Inspector" button at the right of the toolbar is pressed
    And the View menu's second item reads "Hide Inspector"
    When I press ⌥⌘I again
    Then the inspector closes, the toolbar button is no longer pressed
    And the View menu's second item reads "Show Inspector"

  Scenario: 4. ⌥⌘F focuses the sidebar filter, opening a hidden sidebar first
    When I click the URL field and press ⌥⌘F
    Then the caret blinks in the field reading "Filter Collections" at the top of the sidebar
    When I type: refund
    Then the tree narrows to "Payments API" and the rows under it whose names contain "refund", "Refund charge" and "List refunds" among them
    And the line under the field ends "matches in 1 Collection"
    When I press Esc
    Then the filter clears and the whole tree is back
    When I press ⌃⌘S to close the sidebar, click the URL field, and press ⌥⌘F
    Then the sidebar opens and the caret blinks in "Filter Collections"
    When I drag the window's right edge until the window is narrower than 960 pt
    Then the sidebar closes
    When I press ⌥⌘F
    Then the sidebar opens over the left of the content, with a shadow, and the caret blinks in "Filter Collections"
    When I press Esc
    Then the overlay closes

  Scenario: 5. ⌥⌃E opens the Environments sheet
    Given I zoomed the window back to at least 1,200 pt
    When I press ⌥⌃E
    Then the "Environments" sheet slides down from the toolbar
    When I click "Done"
    Then the sheet closes

  Scenario: 6. ⌘F still finds in the body, not in the sidebar
    When I click "List charges" in the sidebar
    And I press ⌘↩ to send it and wait for the Response
    And I click inside the Response body text
    And I press ⌘F
    Then a find bar opens above the Response body with the caret in its search field
    And the sidebar's "Filter Collections" field stays empty and does not take the caret
    When I type: charges
    Then the matches are highlighted in the Response body and the find bar counts them
    When I press Esc
    Then the find bar closes
    When I press ⌘T for a new Tab, set its Body Type to raw, and type in the body editor: {"refund": "charges"}
    And I press ⌘F
    Then a find bar opens above the body editor with the caret in its search field
    When I type: refund
    Then "refund" in the body editor is highlighted
    When I click the URL field and press ⌘F
    Then no find bar opens and nothing else happens

# ─── Known simplifications ────────────────────────────────────────────────────────────────
#
# - ⌘F only opens the find bar: there are no Find Next (⌘G), Find Previous (⇧⌘G) or Use
#   Selection for Find (⌘E) items yet. The find bar's own arrows and Return step through the
#   matches.
# - With no Collections the filter field is hidden, so ⌥⌘F opens the sidebar and nothing
#   takes the caret. "Filter Collections" stays enabled in the menu all the same.
# - The find bar searches the text shown: matches inside a Folded Fold Region are not found
#   until it is unfolded.

# Remembered across relaunch
#
# Whether the inspector is open, its width and Variables / Curl are kept in UserDefaults
# (design-system §9 Q14), never in the Session file. Widths are in points. To read the
# inspector's width on screen, press ⇧⌘4 and drag from its left border (the 1 pt line) to the
# window's right edge: the number beside the pointer is the width in points; Esc cancels the
# screenshot. To read the width Raccoon stored, in Terminal B:
#   defaults read Raccoon InspectorWidth
#
# ─── How launching works ──────────────────────────────────────────────────────────────────
#
# In Terminal A, inside the project folder:
#   cd ~/Documents/playground/raccoon
#   swift run Raccoon -DataFolder /tmp/raccoon-remember
# Quit with ⌘Q while the Raccoon window is in front. The window opens 1,200 pt wide.
#
# ─── Before you start (once) ──────────────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder:
#   cd ~/Documents/playground/raccoon
#   swift build
#   rm -rf /tmp/raccoon-remember
#   cp -R manual-tests/collections.datafolder /tmp/raccoon-remember
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/219c9decb85386d1.json
#   defaults delete Raccoon InspectorShown; defaults delete Raccoon InspectorWidth; defaults delete Raccoon InspectorPane
# "swift build" should end with "Build complete!". A "defaults delete" of a key that is not
# there prints "Domain (Raccoon) not found" or "...does not exist"; that is fine.
#
# ─── When you are done ────────────────────────────────────────────────────────────────────
#
# Quit Raccoon. In Terminal B:
#   rm -rf /tmp/raccoon-remember
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/219c9decb85386d1*

Feature: The inspector is remembered across relaunch

  Scenario: 1. With nothing remembered, the inspector starts closed on Variables
    Given Raccoon is running on /tmp/raccoon-remember for the first time since "Before you start"
    Then the inspector is closed and the toolbar's "Show Inspector" button is not pressed
    When I click the inspector toggle
    Then the inspector opens about 280 pt wide, its header reading "Variables"

  Scenario: 2. Quit with the Curl pane open at 320 pt; relaunch shows the same
    Given Raccoon is not running
    When I run in Terminal B: defaults write Raccoon InspectorWidth -float 320
    And I launch Raccoon and click the inspector toggle if the inspector is closed
    Then the inspector is 320 pt wide (⇧⌘4, see above)
    When I click the terminal segment in the inspector's header
    Then the header reads "Curl"
    When I quit with ⌘Q and launch Raccoon again
    Then the inspector is already open, 320 pt wide, the toolbar's "Show Inspector" button pressed
    And the header reads "Curl", the terminal segment selected, the Curl pane below it
    And the View menu's second item reads "Hide Inspector"

  Scenario: 3. A width dragged by hand is the width after relaunch
    Given the inspector is open, docked, on Curl
    When I drag the inspector's left border to the left by about two finger-widths
    And I quit with ⌘Q
    And I run in Terminal B: defaults read Raccoon InspectorWidth
    Then it prints a number between 340 and 400; call it W
    When I launch Raccoon again
    Then the inspector is open on Curl and W pt wide (⇧⌘4)
    When I click the inspector toggle twice, closing and opening it
    Then it opens W pt wide again

  Scenario: 4. Closed and on Variables is remembered too
    Given the inspector is open on Curl
    When I click the curly-braces segment, then the inspector toggle to close it
    And I quit with ⌘Q and launch Raccoon again
    Then the inspector is closed and the toolbar's "Show Inspector" button is not pressed
    When I press ⌥⌘I
    Then the inspector opens W pt wide, its header reading "Variables"

  Scenario: 5. A width out of range is kept within 240–400 pt
    Given Raccoon is not running and the inspector was open when it quit
    When I run in Terminal B: defaults write Raccoon InspectorWidth -float 1000
    And I launch Raccoon
    Then the inspector is open and 400 pt wide
    When I quit, run: defaults write Raccoon InspectorWidth -float 100, and launch again
    Then the inspector is open and 240 pt wide
    When I quit, run: defaults write Raccoon InspectorPane Headers, and launch again
    Then the inspector's header reads "Variables"

  Scenario: 6. Remembered open in a narrow window, the inspector overlays
    Given the inspector is open and docked
    When I drag the window's right edge until the window is about 800 pt wide
    Then the inspector lies over the right of the content, with a shadow
    When I quit with ⌘Q and launch Raccoon again
    Then the window opens 1,200 pt wide and the inspector is docked, not overlaid
    When I drag the window narrow again, press Esc to close the overlay, quit and relaunch
    Then the inspector is closed

  Scenario: 7. The Session file does not change when only the inspector changes
    Given Raccoon is running on /tmp/raccoon-remember with the inspector closed
    When I type "x" at the end of the URL field and wait two seconds
    And I run in Terminal B: ls -lT ~/Library/Application\ Support/Raccoon/sessions/219c9decb85386d1.json
    Then it prints one line; note its time, to the second
    When I wait until that time is at least five seconds ago
    And I open the inspector, drag its left border, click the terminal segment, click the curly-braces segment and close the inspector
    And I wait two seconds and run the same ls -lT
    Then it prints the same time as before

# ─── Known simplifications ────────────────────────────────────────────────────────────────
#
# - Showing a Variable from its popover ("Variables in request") switches to Variables, and
#   that is remembered as the last choice like a click on the segment.
# - The window's own size and place are not remembered: it opens 1,200 × 760, centred, so a
#   narrow-window overlay at quit comes back docked.
# - Quitting writes the Session file (Tabs) whatever the inspector did, so scenario 7 looks
#   at the file while Raccoon is running, not across a quit.
