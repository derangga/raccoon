# Manual acceptance: Variables and Environments (M5)
#
# ─── What this file is ────────────────────────────────────────────────────────────────────
#
# Step-by-step checks you run by hand. Each "Scenario" is one check: do the "When" steps,
# then confirm every "Then" line. If a "Then" line is not true, the check failed: note the
# scenario number, the line, and what you saw instead.
#
# Start every Feature fresh: quit Raccoon, do "Before you start", then launch again. Inside a
# Feature, run the scenarios in order without resetting: later ones start from where earlier
# ones left off, and say so in their "Given". The "Background" lines are what must be true
# before each scenario; they never mean "reset".
#
# Run the whole file twice: once with macOS Appearance set to Light (System Settings ▸
# Appearance ▸ Light), once with Dark. Between the two runs, do "When you are done": it also
# clears the Keychain, which "Before you start" does not touch.
#
# Compare colours and layout with the boards named under each Feature:
#   open design/ui/mockups/
#
# ─── Words used below ─────────────────────────────────────────────────────────────────────
#
# Variable              a name and a value. {{name}} in a request is replaced by the value
#                       when the request is sent.
# Globals               the Variables in globals.json. They apply whichever Environment is on.
# Environment           one file in environments/, such as Staging.json. Its Variables win
#                       over a Global with the same name.
# Active Environment    the one Environment in use, picked in the toolbar. Can be none.
# Secret Variable       a Variable whose value is kept in the macOS Keychain. The file holds
#                       only its name and "secret": true.
# Undefined Variable    a {{name}} with no value anywhere. Raccoon refuses to send it.
# Disabled Row          a row whose checkbox is unticked. It is kept but not used.
# Terminal A            the Terminal window you launch Raccoon from. It stays busy while
#                       Raccoon runs.
# Terminal B            a second Terminal window (⌘N in Terminal) for every other command.
#
# The colours, as the Theme names them:
#   blue                  a defined Variable (variableDefined)
#   mauve, dotted line    a Secret Variable (variableSecret)
#   red, wavy line        an Undefined Variable (variableUndefined)
#
# ─── How launching works ──────────────────────────────────────────────────────────────────
#
# In Terminal A, inside the project folder:
#   cd ~/Documents/playground/raccoon
#   swift run Raccoon -DataFolder /tmp/raccoon-vars
# "-DataFolder <path>" opens that folder instead of ~/Raccoon, for this launch only.
# Quit with ⌘Q while the Raccoon window is in front.
#
# Every request below goes to httpbin.org, which sends back what it received. Its "url" field
# shows the address the request went to, and "headers" shows the headers.
#
# ─── The test Workspace ───────────────────────────────────────────────────────────────────
#
#   /tmp/raccoon-vars/raccoon.json                    fixed id 5EC2E7A1-0000-4000-8000-000000000001
#   /tmp/raccoon-vars/globals.json                    host, path, and key (secret, no value yet)
#   /tmp/raccoon-vars/environments/Staging.json       tenant, path
#   /tmp/raccoon-vars/environments/Prod.json          no Variables
#
# The fixed id puts every secret under a Keychain service you can name in Terminal B:
#   Globals       Raccoon/5EC2E7A1-0000-4000-8000-000000000001
#   Staging       Raccoon/5EC2E7A1-0000-4000-8000-000000000001/Staging
# The account is the Variable's name. To read one, in Terminal B:
#   security find-generic-password -s <service> -a <name> -w
# It prints the value, or "The specified item could not be found in the keychain.".
# The first read may ask "security wants to use your confidential information": click Allow.
#
# The Session file for this folder, which remembers the Active Environment, is
#   ~/Library/Application Support/Raccoon/sessions/cc1bbe4ce0ca54c1.json
#
# ─── Before you start (once per run) ──────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder (the commands work in fish, zsh and bash):
#   cd ~/Documents/playground/raccoon
#   swift build
#   rm -rf /tmp/raccoon-vars
#   mkdir -p /tmp/raccoon-vars/environments
#   echo '{"version": 1, "id": "5EC2E7A1-0000-4000-8000-000000000001"}' > /tmp/raccoon-vars/raccoon.json
#   echo '{"version": 1, "variables": [{"name": "host", "value": "httpbin.org"}, {"name": "path", "value": "/anything/from-globals"}, {"name": "key", "secret": true}]}' > /tmp/raccoon-vars/globals.json
#   echo '{"version": 1, "variables": [{"name": "tenant", "value": "acme"}, {"name": "path", "value": "/anything/from-staging"}]}' > /tmp/raccoon-vars/environments/Staging.json
#   echo '{"version": 1, "variables": []}' > /tmp/raccoon-vars/environments/Prod.json
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/cc1bbe4ce0ca54c1.json
# "swift build" should end with "Build complete!". The other commands print nothing.
#
# ─── When you are done ────────────────────────────────────────────────────────────────────
#
# Quit Raccoon. In Terminal B, delete the test secrets (each line prints either "password has
# been deleted." or "could not be found": both are fine):
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001 -a key
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001/Staging -a tenant
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001/Staging -a key
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001/Vault -a pin
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001/Safe -a pin
#   rm -rf /tmp/raccoon-vars
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/cc1bbe4ce0ca54c1*
# Scenarios 30 and 39 move "New Environment.json", "Vault.json" and "Safe.json" to the Trash:
# delete them from it.
# Your own ~/Raccoon, its Tabs and its secrets were never touched.


Feature: The Environment picker
  Boards 01 and 07

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")

  Scenario: 1. The pop-up and its menu
    Then the toolbar shows the label "Environment" over a pop-up reading "No Environment"
    And the pop-up sits just left of the inspector toggle, at the right end of the toolbar
    When I click the pop-up
    Then a menu opens with these rows, top to bottom:
      | row                 | note                        |
      | No Environment      | has a checkmark: it is on   |
      | (a separator line)  |                             |
      | Prod                |                             |
      | Staging             |                             |
      | (a separator line)  |                             |
      | Edit Environments…  |                             |
    When I choose "Staging"
    Then the menu closes and the pop-up reads "Staging"
    When I click the pop-up again
    Then "Staging" has the checkmark and "No Environment" has none

  Scenario: 2. The keyboard and the View menu
    When I open the View menu
    Then it lists "Choose Environment" with the shortcut ⌃E and "Edit Environments…" with ⌥⌃E
    When I press Escape, then press ⌃E
    Then the picker's menu opens, as in scenario 1
    When I press Escape
    Then the menu closes and nothing changed

  Scenario: 3. One Active Environment for every Tab in the window
    Given "Staging" is picked
    When I type in the URL field: https://{{host}}{{path}}
    And I press ⌘↩
    Then the Response body's "url" reads "https://httpbin.org/anything/from-staging"
    When I press ⌘T, type the same URL in the new Tab and press ⌘↩
    Then that Response's "url" also reads ".../anything/from-staging"
    When I choose "No Environment" from the pop-up and press ⌘↩ in each Tab
    Then both Responses read "https://httpbin.org/anything/from-globals"

  Scenario: 4. A very long Environment name (break-ui)
    Given in Terminal B I ran:
      echo '{"version": 1, "variables": []}' > "/tmp/raccoon-vars/environments/Payments sandbox for EU tenants and their webhooks.json"
    When I wait a second and click the pop-up
    Then the menu shows the whole name "Payments sandbox for EU tenants and their webhooks"
    When I choose it
    Then the pop-up shows the start of the name and ends in "…", about 200 pt wide
    And the toolbar's other items did not move or squeeze
    When I choose "No Environment" and in Terminal B run:
      rm "/tmp/raccoon-vars/environments/Payments sandbox for EU tenants and their webhooks.json"
    Then after a second the menu no longer lists it

  Scenario: 5. The Active Environment survives a relaunch
    When I choose "Staging" and press ⌘Q
    And in Terminal A I run again: swift run Raccoon -DataFolder /tmp/raccoon-vars
    Then the pop-up reads "Staging"

  Scenario: 6. A missing Environment falls back to none
    Given scenario 5 passed, so "Staging" is picked
    When I press ⌘Q
    And in Terminal B I run: mv /tmp/raccoon-vars/environments/Staging.json /tmp/
    And in Terminal A I run: swift run Raccoon -DataFolder /tmp/raccoon-vars
    Then the pop-up reads "No Environment", and the menu lists only "Prod"
    And no alert or banner appears
    When I press ⌘Q
    And in Terminal B I run: mv /tmp/Staging.json /tmp/raccoon-vars/environments/
    Then the next launch lists "Staging" again


Feature: {{name}} highlighting
  Boards 02, 04, 09 and 10

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")
    And I chose "Staging" from the Environment pop-up

  Scenario: 7. The three kinds in the URL field
    When I type in the URL field: https://{{host}}/anything/{{tenant}}?k={{key}}&c={{charge_id}}
    Then "{{host}}" and "{{tenant}}" are blue, with no underline
    And "{{key}}" is mauve with a dotted underline (it is a secret, even though the Keychain has no value for it yet)
    And "{{charge_id}}" is red with a wavy underline
    And the rest of the URL keeps its usual colours
    When I click in the body area, so the URL field is no longer being edited
    Then the colours and underlines stay
    And the wave under "{{charge_id}}" lines up with its letters, not shifted left or right

  Scenario: 8. Changing the Active Environment recolours at once
    Given the URL from scenario 7
    When I choose "No Environment" from the pop-up
    Then without any typing "{{tenant}}" turns red with a wavy underline
    And "{{host}}" stays blue and "{{key}}" stays mauve: both are Globals
    When I choose "Staging" again
    Then "{{tenant}}" is blue again

  Scenario: 9. A header cell with all three kinds, and the section count
    When I open Headers and add a row with the name X-Mixed and the value: {{host}} {{key}} {{nope}}
    And I press Tab to leave the cell
    Then that one cell shows blue, then mauve with a dotted underline, then red with a wavy underline
    And the section bar reads "Headers 1", the "1" in red semibold
    When I untick the row's checkbox
    Then all three tokens turn grey and their underlines stay
    And the "1" turns grey: a Disabled Row is not sent, so it cannot block a send

  Scenario: 10. Params, Body and Auth take Variables too
    When I open Params and add a row with the name t and the value {{tenant}}
    Then "{{tenant}}" in the cell is blue
    And the section bar reads "Params 1", the "1" in the usual grey
    When I open Body, choose raw and JSON, and type: {"t": "{{tenant}}", "n": 1}
    Then "{{tenant}}" is blue, drawn over the JSON string colour
    And 1 keeps its JSON number colour
    When I open Auth, choose Bearer and type {{key}} in the token field
    Then "{{key}}" is mauve with a dotted underline
    When I click outside the token field
    Then the dotted underline stays

  Scenario: 11. Text that is not a Variable stays plain
    When I type in the URL field: https://{{host}}/a/{{}}/b/{{a b}}/c/{{ tenant }}/d/{{unclosed
    Then "{{}}", "{{a b}}" and "{{unclosed" keep the URL's usual colour, with no underline
    And "{{ tenant }}", spaces included, is blue like "{{tenant}}"


Feature: The Variable tooltip
  Boards 02 and 09

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")
    And I chose "Staging" from the Environment pop-up
    And the URL field reads: https://{{host}}{{path}}/{{tenant}}?k={{key}}&c={{charge_id}}

  Scenario: 12. Defined, overridden, secret and undefined
    When I rest the pointer on "{{tenant}}" without moving it
    Then after the usual tooltip delay (about a second) a small panel appears under the pointer
    And its first line reads "tenant · Staging", with "tenant" in bold blue, as {{tenant}} is in the field
    And under it "acme" sits in a monospaced font inside its own box, with a thin border and a darker fill
    And no letter of either line is cut off at the panel's edge
    When I move the pointer to "{{path}}" while the panel shows
    Then the panel changes at once, with no new delay, to "path · Staging" and "/anything/from-staging"
    And it does not say Globals: Staging's path wins over the Global one
    When I move to "{{host}}"
    Then it reads "host · Globals" and "httpbin.org"
    When I move to "{{key}}"
    Then it reads "key · Globals" with "key" in bold mauve, and "Secret" with no box, and never shows a value
    When I move to "{{charge_id}}"
    Then it reads "charge_id" in bold red, and below it, in red with no box, "Not defined in Staging or Globals"
    When I move onto "?k=" between two tokens
    Then the panel goes away

  Scenario: 13. With no Active Environment
    When I choose "No Environment" and rest the pointer on "{{tenant}}"
    Then the panel reads "tenant" and, in red, "Not defined in Globals"
    When I rest the pointer on "{{path}}"
    Then it reads "path · Globals" and "/anything/from-globals"

  Scenario: 14. The panel never takes the keyboard
    Given the caret is in the URL field and the panel shows over "{{tenant}}"
    When I type the letter x
    Then the panel goes away and the x lands in the URL field
    When I let the panel show again and click anywhere
    Then it goes away
    When I let it show again and scroll the body area
    Then it goes away
    And at no point did the Raccoon window lose its active title bar

  Scenario: 15. Every field that takes Variables shows it
    Given a header row with the value {{tenant}}, a raw body holding {{tenant}}, and Auth Bearer with the token {{key}}
    Then resting the pointer on each shows the same panel as on the URL field
    And moving from the URL field to the header cell waits out the delay again before the panel shows there

  Scenario: 16. A long value wraps (break-ui)
    Given in Terminal B I ran:
      echo '{"version": 1, "variables": [{"name": "tenant", "value": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, {"name": "path", "value": "/anything/from-staging"}]}' > /tmp/raccoon-vars/environments/Staging.json
    When I wait a second and rest the pointer on "{{tenant}}"
    Then the panel is no wider than about 320 pt
    And the long value breaks in the middle of the word, over several lines
    And the whole panel stays on screen
    When in Terminal B I put Staging.json back with the line from "Before you start"
    Then after a second the panel over "{{tenant}}" reads "acme" again


Feature: Sending and Copy as Curl with Variables
  Board 04

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")
    And I chose "Staging" from the Environment pop-up

  Scenario: 17. Every Variable is replaced when the request is sent
    When I type in the URL field: https://{{host}}{{path}}/{{tenant}}
    And I add the header X-Tenant with the value {{tenant}}
    And I choose Body raw, JSON and type: {"t": "{{tenant}}"}
    And I press ⌘↩
    Then the status reads 200
    And the Response's "url" reads "https://httpbin.org/anything/from-staging/acme"
    And its "headers" holds "X-Tenant": "acme"
    And its "data" reads "{\"t\": \"acme\"}"
    And the request editor still shows {{tenant}} everywhere: sending does not rewrite what I typed

  Scenario: 18. A blocked send names every missing Variable and keeps the last Response
    Given scenario 17 passed, so a 200 Response is on screen
    When I change the URL to https://{{host}}/anything/{{charge_id}}
    And I add the header X-Tenant-Id with the value {{tenant_id}}
    And I press ⌘↩
    Then no spinner appears and the 200 Response from scenario 17 stays in the Response pane
    And under the URL bar a red line reads: Not sent. charge_id and tenant_id are not defined in Staging or in Globals.
    When I open the Edit menu
    Then it shows "Copy as Curl (charge_id and tenant_id are not defined)", greyed out
    When I press Escape and choose "No Environment" from the pop-up, then press ⌘↩
    Then the red line reads: Not sent. charge_id and tenant_id are not defined in Globals.
    When I delete the X-Tenant-Id row and change the URL back to https://{{host}}{{path}}
    And I press ⌘↩
    Then the red line goes away and the Response's "url" reads "https://httpbin.org/anything/from-globals"

  Scenario: 19. A Disabled Row's Variable does not block a send
    When I set the URL to https://{{host}}/anything
    And I add the header X-Nope with the value {{nope}} and untick its checkbox
    And I press ⌘↩
    Then the request is sent (status 200) and the Response's "headers" has no X-Nope

  Scenario: 20. One pass only: a value that looks like a Variable is sent as written
    Given in Terminal B I ran:
      echo '{"version": 1, "variables": [{"name": "tenant", "value": "{{host}}"}, {"name": "path", "value": "/anything/from-staging"}]}' > /tmp/raccoon-vars/environments/Staging.json
    When I wait a second, set the URL to https://{{host}}/anything and add the header X-T with the value {{tenant}}
    And I press ⌘↩
    Then the Response's "headers" holds "X-T": "{{host}}", braces and all
    When in Terminal B I put Staging.json back with the line from "Before you start"
    Then nothing else changes

  Scenario: 21. A URL that is not valid after substitution
    Given in Terminal B I ran:
      echo '{"version": 1, "variables": [{"name": "base", "value": "not a url"}]}' > /tmp/raccoon-vars/environments/Prod.json
    When I wait a second, choose "Prod" and set the URL to {{base}}
    And I press ⌘↩
    Then the status reads "Not sent"
    And the Response pane reads "Invalid URL" over "After substitution the URL was not a url."
    When in Terminal B I run:
      echo '{"version": 1, "variables": []}' > /tmp/raccoon-vars/environments/Prod.json
    Then Prod is empty again

  Scenario: 22. A secret the Keychain does not hold counts as undefined
    Given "Staging" is picked and the Keychain holds no value for key (true after "Before you start")
    When I set the URL to https://{{host}}/anything, choose Auth Bearer and type {{key}} as the token
    Then "{{key}}" is mauve, not red: highlighting never reads the Keychain
    When I press ⌘↩
    Then nothing is sent and the red line reads: Not sent. key is not defined in Staging or in Globals.

  Scenario: 23. Copy as Curl fills in plain Variables and leaves secrets as written
    Given the request from scenario 22
    When I choose Edit ▸ Copy as Curl (or press ⇧⌘C)
    And in Terminal B I run: pbpaste
    Then it prints exactly:
      curl 'https://httpbin.org/anything' \
        -H 'Authorization: Bearer {{key}}'
    When I right-click the URL field
    Then its menu ends with a separator and "Copy as Curl"


Feature: The Environments sheet
  Board 07

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")
    And I chose "Staging" from the Environment pop-up

  Scenario: 24. Opening and closing
    Given the caret is in the URL field
    When I press ⌥⌃E
    Then a sheet about 680 × 430 pt slides down from the title bar, titled "Environments"
    And its left list reads, top to bottom: "Globals", a small header "Environments", "Prod", "Staging"
    And "Staging" is selected, with a + and a − button under the list
    And on the right a name field reads "Staging" above a table whose columns are a checkbox, "Name", "Value" and "Secret"
    And the table holds tenant = acme and path = /anything/from-staging, then an empty row with grey "Name" and "Value" placeholders
    And under the table the hint reads: Staging overrides Globals while it is the Active Environment. Secret values are kept in the Keychain; only their names are written to the Data Folder.
    When I click "Globals" in the list
    Then the name field reads "Globals" and cannot be edited, the − button is disabled
    And the table holds host, path, and key, whose value cell reads "Not in the Keychain"
    And the hint begins: Globals apply whichever Environment is active.
    When I click "Done"
    Then the sheet closes and the caret is back in the URL field
    When I choose "Edit Environments…" from the Environment pop-up
    Then the same sheet opens
    When I press Escape
    Then it closes

  Scenario: 25. Editing a value writes the file when I leave the cell
    Given the sheet is open on Staging
    When I double-click tenant's value, change it to globex, and press Tab
    And in Terminal B I run: cat /tmp/raccoon-vars/environments/Staging.json
    Then the file holds "value" : "globex" for tenant
    When I click Done, set the URL to https://{{host}}/anything/{{tenant}} and press ⌘↩
    Then the Response's "url" reads "https://httpbin.org/anything/globex"

  Scenario: 26. A Disabled Row falls back to the Global
    Given the sheet is open on Staging
    When I untick path's checkbox
    Then the row turns grey at once, with no Save button to press
    And "cat /tmp/raccoon-vars/environments/Staging.json" shows "isEnabled" : false for path
    When I click Done, set the URL to https://{{host}}{{path}} and press ⌘↩
    Then the Response's "url" reads "https://httpbin.org/anything/from-globals"
    When I tick path again in the sheet
    Then the next send goes to "/anything/from-staging"

  Scenario: 27. Adding and deleting a Variable
    Given the sheet is open on Staging
    When I type region in the empty row's Name cell, press Tab, type eu and press Tab
    Then region = eu is a row of its own, and a new empty row appears under it
    And Staging.json holds region
    When I click the region row and press ⌫
    Then the row is gone and Staging.json no longer holds region
    When I right-click the tenant row
    Then the menu offers "Delete Variable"
    When I press Escape
    Then tenant is still there

  Scenario: 28. Names are checked
    Given the sheet is open on Staging
    When I double-click tenant's name, type a b and press Tab
    Then the name goes back to tenant
    And a red line under the row reads: Names use letters, digits, _, - and . only.
    When I type path in the empty row's Name cell and press Tab
    Then the row is not added, and the red line reads: path is already in Staging.
    When I click "Globals" and type host in the empty row's Name cell, then press Tab
    Then the red line reads: host is already in Globals.
    And none of the files changed

  Scenario: 29. New Environment and renaming
    Given the sheet is open
    When I click +
    Then "New Environment" appears in the list, selected, with its name selected in the name field
    And "ls /tmp/raccoon-vars/environments" lists New Environment.json
    When I click + again
    Then the second one is named "New Environment 2"
    When I select "New Environment 2", type Prod in the name field and press Return
    Then the name goes back to "New Environment 2"
    And a red line under the name field reads: An Environment named “Prod” already exists.
    When I type Vault and press Return
    Then the list shows "Vault" in its sorted place, and the Environment pop-up lists "Vault" too
    And "ls /tmp/raccoon-vars/environments" lists Vault.json and no New Environment 2.json

  Scenario: 30. Deleting an Environment
    Given scenario 29 passed, so "New Environment" and "Vault" exist
    When I select "New Environment" and click −
    Then it leaves the list at once, with no confirmation
    And Finder's Trash holds "New Environment.json"
    And the Environment pop-up no longer lists it
    When I select "Vault" and click −
    Then Vault.json is in the Trash
    # Scenario 39 checks what happens to the secrets of a deleted Environment.

  Scenario: 31. A file Raccoon can't read
    Given in Terminal B I ran: echo '{ not json' > /tmp/raccoon-vars/environments/Broken.json
    When I wait a second and open the sheet
    Then the list shows "Broken" with a warning triangle
    And the Environment pop-up's menu does not list "Broken"
    When I select "Broken"
    Then there is no table, and the sheet reads: Not valid JSON at line 1. Raccoon won't change this file.
    And its name field cannot be edited
    And "cat /tmp/raccoon-vars/environments/Broken.json" still prints: { not json
    When in Terminal B I run: rm /tmp/raccoon-vars/environments/Broken.json
    Then after a second "Broken" leaves the list

  Scenario: 32a. Cells and the name field are centred
    Given the sheet is open on Staging, and a Tab's Headers table is open behind it to compare
    Then the Variables table looks like the Headers table: the same recessed header row with grey 11 pt "Name", "Value" and "Secret", the same 28 pt rows and row lines, one vertical rule before Value, and a rounded border
    And the rounded border ends just under the empty row, not at the hint
    And hovering a row tints it as in Headers, and a selected row takes the same fill
    And a closed lock sits on a pill in that selection colour
    And under the left list, a footer like System Settings' has a hairline across its top, then + | − with a short vertical line between them
    And − is as wide and as heavy as +
    When I select "Globals"
    Then − turns grey, at the same size: Globals can't be deleted
    Then in every row the name and value text sit in the middle of the row, level with the checkbox and the lock
    And the grey "Name" and "Value" placeholders of the empty row sit level with its checkbox too
    When I click tenant's value once
    Then the whole cell, from the column line to the next and from row line to row line, gets a square blue 2 pt outline on the text background, as in Postman
    And the text "acme" did not move when the outline appeared
    When I press Tab
    Then the first cell's outline goes away, and whichever cell takes the caret gets it
    When I click in the empty space at the right end of a value cell, past its text
    Then that cell is edited too
    When I click +
    Then the name field's blue ring is a little taller than "New Environment", with space above and below the letters
    And the text is in the middle of the ring, not touching its top

  Scenario: 32b. Request tables edit the same way
    Given the sheet is closed
    When I open Headers and click once in the empty row's Value cell
    Then the whole cell gets the blue outline at once, before I type anything, and the placeholder does not move
    And the same holds in Params, Cookies, and the form and multipart tables of Body

  Scenario: 32. 200 Variables scroll (break-ui)
    Given in Terminal B I ran:
      python3 -c "import json; print(json.dumps({'version': 1, 'variables': [{'name': 'v%d' % i, 'value': str(i)} for i in range(200)]}))" > /tmp/raccoon-vars/environments/Big.json
    When I wait a second and select "Big" in the sheet
    Then the table shows v0 at the top and scrolls smoothly down to v199
    And the sheet stays the same size, with the hint and Done in place


Feature: Secret Variables
  Boards 07 and 09

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")
    And I chose "Staging" from the Environment pop-up
    And the Environments sheet is open (⌥⌃E)

  Scenario: 33. Locking a value moves it to the Keychain
    When I select "Staging" in the sheet and click the open lock in tenant's Secret column
    Then the lock closes and sits on a pressed fill
    And the value cell reads "••••••••"
    When in Terminal B I run: cat /tmp/raccoon-vars/environments/Staging.json
    Then tenant shows "secret" : true and the file has no "acme" anywhere
    When in Terminal B I run: security find-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001/Staging -a tenant -w
    Then it prints: acme
    When I click Done, set the URL to https://{{host}}/anything/{{tenant}} and press ⌘↩
    Then "{{tenant}}" in the URL is mauve with a dotted underline
    And the Response's "url" reads "https://httpbin.org/anything/acme"

  Scenario: 34. Typing a secret's value
    When I click "Globals", double-click key's value cell (it reads "Not in the Keychain")
    And I type sk_new_123456789 and press Tab
    Then the cell reads "••••••••": eight bullets, whatever the length
    And "cat /tmp/raccoon-vars/globals.json" is unchanged: key has "secret" : true and no value
    And "security find-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001 -a key -w" prints sk_new_123456789
    When I click Done, set the URL to https://{{host}}/anything, choose Auth Bearer with the token {{key}}, and press ⌘↩
    Then the Response's "headers" holds "Authorization": "Bearer sk_new_123456789"

  Scenario: 35. An Environment's secret never falls back to the Global
    Given scenario 34 passed, so the Global key has a value
    When on Staging I add a row named key and click its lock while its value is empty
    Then its value cell reads "Not in the Keychain"
    When I click Done and send https://{{host}}/anything with Auth Bearer {{key}}
    Then nothing is sent and the red line reads: Not sent. key is not defined in Staging or in Globals.
    When I choose "No Environment" and press ⌘↩
    Then it sends, with "Authorization": "Bearer sk_new_123456789"

  Scenario: 36. Unlocking puts the value back in the file
    Given scenario 33 passed, so tenant is a secret
    When I click tenant's closed lock
    Then the lock opens and the value cell reads "acme"
    And "cat /tmp/raccoon-vars/environments/Staging.json" shows "value" : "acme" for tenant again
    And the security command from scenario 33 prints: The specified item could not be found in the keychain.

  Scenario: 37. Deleting a secret row removes its Keychain item
    Given tenant is locked again, as in scenario 33
    When I click the tenant row and press ⌫
    Then the row is gone and Staging.json no longer names tenant
    And the security command from scenario 33 prints: The specified item could not be found in the keychain.

  Scenario: 38. Renaming an Environment keeps its secrets
    When I click +, rename the new Environment to Vault, add pin = 1234 and lock it
    And I rename Vault to Safe and press Return
    Then "security find-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-000000000001/Safe -a pin -w" prints 1234
    And the same command with /Vault prints: The specified item could not be found in the keychain.
    When I choose "Safe" from the Environment pop-up and send https://{{host}}/anything/{{pin}}
    Then the Response's "url" ends in "/anything/1234"

  Scenario: 39. Deleting an Environment keeps its secrets in the Keychain
    Given scenario 38 passed
    When I select "Safe" in the sheet and click −
    Then Safe.json is in the Trash
    And the /Safe security command from scenario 38 still prints 1234
    # So putting Safe.json back from the Trash brings its secret back with it.

  Scenario: 40. A value someone wrote next to "secret": true is ignored
    Given I quit Raccoon, and in Terminal B I ran:
      echo '{"version": 1, "variables": [{"name": "host", "value": "httpbin.org"}, {"name": "path", "value": "/anything/from-globals"}, {"name": "key", "secret": true, "value": "leaked"}]}' > /tmp/raccoon-vars/globals.json
    When I launch Raccoon, choose "No Environment" and send https://{{host}}/anything with Auth Bearer {{key}}
    Then the Response's "headers" holds "Bearer sk_new_123456789" from the Keychain, never "leaked"
    And the sheet shows key's value as "••••••••"

  Scenario: 41. No secret ever lands in the Data Folder
    Given scenarios 33 to 40 passed
    When in Terminal B I run: grep -r "sk_new\|1234\|acme" /tmp/raccoon-vars
    Then it prints nothing: tenant was deleted in scenario 37, and every other value is in the Keychain

  Scenario: 42. A Workspace with no id can't hold secrets
    Given I quit Raccoon, and in Terminal B I ran: echo '{ not json' > /tmp/raccoon-vars/raccoon.json
    When I launch Raccoon, open the sheet on Globals and click the lock on host
    Then the lock stays open and a red line under the row reads: Not saved. raccoon.json can't be read.
    And "cat /tmp/raccoon-vars/raccoon.json" still prints: { not json
    When I quit, put raccoon.json back with the line from "Before you start" and launch again
    Then the key row in Globals reads "••••••••" again


Feature: Variable suggestions
  Not drawn on a board yet: design-system.md §6 "Variable suggestions"

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")
    And I chose "Staging" from the Environment pop-up

  Scenario: 43. Typing {{ in a header value offers every Variable in scope
    When I open Headers, add a row named Authorization and in its value type: Bearer {{
    Then a list opens just under the "{{", the caret still blinking in the cell
    And it lists, top to bottom, each name on the left and its source on the right:
      | name   | source           |
      | host   | Globals          |
      | key    | Globals · Secret |
      | path   | Staging          |
      | tenant | Staging          |
    And path says Staging, not Globals: Staging's path wins
    And the first row has the selection fill
    And no value appears anywhere in the list

  Scenario: 44. Filtering, choosing and undoing
    Given the list from scenario 43 is open
    When I type ke
    Then only "key" is listed
    When I press Return
    Then the cell reads "Bearer {{key}}", the caret after the "}}", and the list is gone
    And "{{key}}" is mauve with a dotted underline
    When I press ⌘Z
    Then the cell reads "Bearer {{ke" again

  Scenario: 45. Arrows, Tab, a click, and a }} already there
    When I click the URL field, select all and type: https://{{}}/anything
    And I click between the two pairs of braces and type h
    Then the list shows "host" first, then "path" (it holds an h too)
    When I press ↓, then ↑
    Then the selection moves down one row, then back up
    When I press Tab
    Then the URL reads "https://{{host}}/anything", with no extra "}}"
    When I place the caret at the end, type /{{ and click "tenant" in the list
    Then the URL reads "https://{{host}}/anything/{{tenant}}" and the caret is still in the field

  Scenario: 46. Closing the list, and keys that keep their meaning
    When I type {{ in the URL field and press Escape
    Then the list closes, the text stays as typed, and nothing else happens
    When I press Return
    Then Raccoon tries to send the request, as Return does with no list open
    When I type {{ again and then a space
    Then the list closes
    When I type {{zzz
    Then no list shows: nothing matches
    When I type {{ and click the sidebar
    Then the list closes
    When I click into the middle of an existing {{host}} without typing
    Then no list opens: only typing opens it

  Scenario: 47. The raw body and Auth offer it too
    When I choose Body raw, JSON, and type: {"t": "{{te
    Then the list shows "tenant"
    When I press Return
    Then the body reads {"t": "{{tenant}}
    When I choose Auth Bearer and type {{ in the token field
    Then the same list opens under it

  Scenario: 48. No Variables, no list
    When I choose "Prod" (it has no Variables) and type {{ in the URL field
    Then the list still shows the Globals: host, key, path
    When in Terminal B I run: echo '{"version": 1, "variables": []}' > /tmp/raccoon-vars/globals.json
    And I wait a second and type {{ again
    Then no list shows


Feature: Variables in a Path Variable value
  Board 17. A Path Variable is a `:name` segment, not a Variable: the table is "Path Variables"
  and never "Variables" (CONTEXT.md).

  Background:
    Given Raccoon is running on /tmp/raccoon-vars (see "How launching works")
    And I chose "Staging" from the Environment pop-up

  Scenario: 49. A Variable in a Path Variable value is replaced, highlighted and listed
    When I type in the URL field: https://{{host}}/anything/:id
    And I type {{tenant}} in the Value cell of the Path Variables row "id"
    Then "{{tenant}}" in the cell is blue, like a defined Variable anywhere
    When I press ⌘↩
    Then the Response's "url" reads "https://httpbin.org/anything/acme"
    And the Value cell still reads {{tenant}}
    When I open the inspector on Variables
    Then "tenant" is listed under Staging with the use "Params"

  Scenario: 50. Typing {{ in the Value cell opens the suggestions
    When I type {{te in the Value cell of the Path Variables row "id"
    Then the list shows "tenant"
    When I press Return
    Then the cell reads {{tenant}}

  Scenario: 51. A Path Variable value that is not defined blocks the send
    When I type {{nope}} in the Value cell of "id"
    Then "{{nope}}" is red with a wavy underline
    When I press ⌘↩
    Then no spinner appears and under the URL bar a red line reads: Not sent. nope is not defined in Staging or in Globals.
    And the Variables pane lists "nope" under "Not defined", used by "Params"
    When I choose "No Environment" and press ⌘↩
    Then the red line reads: Not sent. nope is not defined in Globals.

  Scenario: 52. One pass: a Variable whose value looks like :name is not a Path Variable
    Given in Terminal B I ran:
      echo '{"version": 1, "variables": [{"name": "tenant", "value": "/:other"}, {"name": "path", "value": "/anything/from-staging"}]}' > /tmp/raccoon-vars/environments/Staging.json
    When I wait a second, set the URL to https://{{host}}/anything{{tenant}} and press ⌘↩
    Then the Path Variables table is absent
    And the Response's "url" reads "https://httpbin.org/anything/:other"
    When in Terminal B I put Staging.json back with the line from "Before you start"
    Then nothing else changes

  Scenario: 53. Secrets off keeps a secret as written, in a Path Variable too
    Given the Globals Variable "key" is a secret with no value (from "Before you start")
    When I type {{key}} in the Value cell of "id" and press ⇧⌘C
    And in Terminal B I run: pbpaste
    Then the URL in the command ends with /{{key}}, not /%7B%7Bkey%7D%7D


# ─── Known simplifications ────────────────────────────────────────────────────────────────
#
# These differ from the boards on purpose, or were not checked on screen. They are not
# failures; note anything that looks wrong anyway.
#
# - The sheet has no ⊖ button on a row. Board 07 has none either: delete with ⌫ or the
#   row's right-click menu.
# - A secret can't be cleared by emptying its value cell. Unlock it instead.
# - "Include secrets" has no button yet. It comes with the inspector's Curl pane, so Copy as
#   Curl always leaves a secret as {{name}}.
# - The tooltip reads "Not defined in Staging or Globals" (board 09). The red line under the URL
#   bar reads "… in Staging or in Globals" (board 04). Both match their boards.
# - The tooltip shows the same delay again when the pointer moves to another field; it
#   switches at once only between tokens in the same field.
# - The tooltip looks at about 512 characters around the pointer, so a token in a very long
#   single-line body is found the same way as anywhere else.
# - Names in the red line under the URL bar are in the normal font, not monospaced.
# - The red line under a sheet row sits over the top of the next row.
# - The suggestion list has no board yet: its look follows the hover tooltip's (design-system
#   §6). It shows names and sources only, never a value, so it can't show what a Variable holds.
# - Positions were calculated, not checked on screen: the pressed fill behind a locked
#   lock, the wave under a field not being edited, and which token counts as under the
#   pointer. Look at these closely.
