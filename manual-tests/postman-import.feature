# Manual acceptance: Postman Import (M7)
#
# ─── What this file is ────────────────────────────────────────────────────────────────────
#
# Step-by-step checks you run by hand. Each "Scenario" is one check: do the "When" steps,
# then confirm every "Then" line. If a "Then" line is not true, the check failed: note which
# line and what you saw instead.
#
# Run every Feature twice: once with macOS Appearance set to Light (System Settings ▸
# Appearance ▸ Light), which is Latte, once with Dark, which is Mocha. Compare against board 12
# "Postman Import" on the Raccoon UI canvas. The sheet is native: system colours in both, a
# white list box with a hairline border in Light and a dark grey one in Dark.
#
# ─── The sample files ─────────────────────────────────────────────────────────────────────
#
# manual-tests/postman-import/files/ holds the Postman exports you pick:
#   Payments API.postman_collection.json   44 Requests in 6 Folders. Bearer Auth on the
#                                          Collection (inherited by 40), a Collection
#                                          pre-request script, 4 Requests with OAuth 2.0,
#                                          {{$guid}} and {{$timestamp}} in 3 Requests, and
#                                          7 Collection variables
#   Small API.postman_collection.json      3 Requests in 1 Folder, nothing that won't come across
#   Dev.postman_environment.json           12 Variables, 2 of them secrets (api_key, token)
#   Prod.postman_environment.json          the same shape; the Workspace already has a Prod
#   workspace.postman_globals.json         5 Globals; the Workspace already has base_url
#   insomnia-export.json                   an Insomnia export, not a Postman one
# manual-tests/postman-import/path-variables/ holds one more file, kept apart so the counts
# above stay true:
#   Posts.postman_collection.json          2 Requests with `:id`, `:user` and `:post` in the URL
#                                          and a url.variable for each (one with a value, one
#                                          with {{user_id}}, one empty)
# In the open panel, press ⇧⌘G and paste the folder's path to go there:
#   ~/Documents/playground/raccoon/manual-tests/postman-import/files
#
# manual-tests/postman-import/datafolder/ is the Workspace they import into: a Collection
# "Internal tools", environments/Prod.json, globals.json with base_url, and raccoon.json with
# the fixed id 70574A40-0000-4000-8000-000000000001.
#
# ─── Before each Feature ──────────────────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder (fish, zsh and bash):
#   cd ~/Documents/playground/raccoon
#   rm -rf /tmp/raccoon-postman && cp -R manual-tests/postman-import/datafolder /tmp/raccoon-postman
# Then in Terminal A:
#   swift run Raccoon -DataFolder /tmp/raccoon-postman
# Quit with ⌘Q between Features. The Session file for this folder is
#   ~/Library/Application Support/Raccoon/sessions/9eb1d6c532f87905.json
#
# Importing Dev or Prod stores their two secrets in your login Keychain, under the services
# Raccoon/70574A40-0000-4000-8000-000000000001/Dev and …/Prod 2. To remove them afterwards:
#   for e in Dev "Prod 2"; for a in api_key token; security delete-generic-password -s "Raccoon/70574A40-0000-4000-8000-000000000001/$e" -a $a; end; end
# (fish; in zsh or bash: for e in Dev "Prod 2"; do for a in api_key token; do security delete-generic-password -s "Raccoon/70574A40-0000-4000-8000-000000000001/$e" -a $a; done; done)


Feature: Opening Postman Import
  Board 12, the File menu and Sidebar + menu cards

  Scenario: 1. File ▸ Import from Postman… on ⇧⌘I
    When I open the File menu
    Then it reads, top to bottom: New Tab ⌘T · New Collection · a separator · Import from Postman… ⇧⌘I · a separator · Save ⌘S · a separator · Close Tab ⌘W
    When I press Escape, then ⇧⌘I
    Then an open panel slides down from the window's title bar, with Open and Cancel buttons
    And ⌥⌘I still shows and hides the inspector, and does not open the panel

  Scenario: 2. The sidebar's + menu
    When I click + at the bottom of the sidebar
    Then the menu reads: New Collection · New Folder · a separator · Import from Postman…
    When I choose Import from Postman…
    Then the same open panel slides down

  Scenario: 3. The open panel takes many .json files and nothing else
    Given the open panel is up, in manual-tests/postman-import/files
    Then every .json file can be selected, and ⌘A selects all six
    When I go to ~/Documents/playground/raccoon with ⇧⌘G
    Then Package.swift and CLAUDE.md are greyed out: only .json files and folders can be picked

  Scenario: 4. Cancel in the open panel opens no sheet
    Given the open panel is up
    When I click Cancel (or press Escape)
    Then the panel closes and no sheet appears
    And in Terminal B, ls /tmp/raccoon-postman prints: environments  globals.json  Internal tools  raccoon.json


Feature: The plan
  Board 12, the sheet

  Background:
    Given I pressed ⇧⌘I, went to manual-tests/postman-import/files and selected all six files with ⌘A
    When I click Open

  Scenario: 5. One row per file, by file name
    Then a sheet 620 pt wide slides down, titled "Import from Postman" in 13 pt semibold
    And under it a rounded list box holds six rows, each at least 38 pt tall, divided by hairlines:
      | checkbox     | glyph            | name (13 pt)            | under it (11 pt, secondary)                                         | trailing (11 pt, secondary)            |
      | ticked       | {}               | Dev                     | Environment · 12 Variables, 2 secrets                              | Dev.postman_environment.json           |
      | off, greyed  | page             | insomnia-export.json    | Not a Postman export Raccoon reads                                  |                                        |
      | ticked       | stacked layers   | Payments API            | Collection · 44 Requests in 6 Folders                              | Payments API.postman_collection.json   |
      | ticked       | {}               | Prod → Prod 2           | Environment · 12 Variables, 2 secrets · “Prod” already exists      | Prod.postman_environment.json          |
      | ticked       | stacked layers   | Small API               | Collection · 3 Requests in 1 Folder                                | Small API.postman_collection.json      |
      | ticked       | globe            | Globals                 | 4 new · 1 kept as it is in Raccoon (base_url)                      | workspace.postman_globals.json         |
    And every name is semibold except insomnia-export.json, which is regular weight in grey
    And the insomnia-export.json checkbox can't be clicked
    And the footer, under a hairline, reads on one line: "Imports into /tmp/raccoon-postman. Secrets go to the Keychain." with /tmp/raccoon-postman in SF Mono
    And on the right of the footer are Cancel and Import, Import blue (the default button)

  Scenario: 6. What won't come across, and a Request list that doesn't fit (break-ui)
    Then under the list an 11 pt semibold grey heading reads: What won't come across
    And five notes follow, each a 12 pt sentence with its names on one 11 pt grey line under it:
      | glyph             | sentence                                                                                                                                  | names line                                                                                                    |
      | ⓘ grey            | Auth inherited from Folders is copied onto 40 Requests.                                                                                    | List charges · Create charge · Get charge · Update charge · Search charges · List refunds and 34 more         |
      | ⚠ orange          | Scripts in 44 Requests are not imported. Raccoon runs no pre-request or test scripts.                                                     | List charges · Create charge · Get charge · Update charge · Search charges · Capture charge and 38 more       |
      | ⚠ orange          | 4 Requests use OAuth 2.0 and are imported with no Auth.                                                                                    | Capture charge · Create refund · List payouts · Rotate webhook secret                                         |
      | ⚠ orange          | {{$guid}} and {{$timestamp}} in 3 Requests are Postman dynamic variables. They stay undefined, so those Requests won't send until you replace them. | Send test event · Customer lookup 01 by email address and merchant account · Replay event |
      | ⓘ grey            | Collection variables of 1 Collection are added to Globals.                                                                                 | Payments API                                                                                                  |
    And {{$guid}} and {{$timestamp}} are in SF Mono
    And no names line wraps onto a second line, and none is cut off mid-name: a list that doesn't fit ends with "and N more"
    And hovering a names line shows a tooltip with every name, all 44 for the scripts note
    And the dynamic variables sentence wraps onto two lines inside the sheet, never past its edge
    And the list and the notes together grow to at most 440 pt; past that they scroll (the scroller flashes once), the last note is reachable, and the heading and footer stay put
    And there is no note about Prod or base_url: the rename and the kept Global are on their rows

  Scenario: 7. Unticking re-plans
    When I untick Payments API
    Then all five notes and the "What won't come across" heading disappear, and the sheet gets shorter
    And Import stays enabled
    When I untick every other row
    Then Import is greyed out and can't be clicked, and Return does nothing
    When I tick Small API again
    Then Import is enabled again

  Scenario: 8. Cancel on the sheet writes nothing
    When I click Cancel (or press Escape)
    Then the sheet slides up and nothing else changes: the sidebar still shows only Internal tools
    And in Terminal B, ls /tmp/raccoon-postman prints: environments  globals.json  Internal tools  raccoon.json
    And ls /tmp/raccoon-postman/environments prints: Prod.json
    And focus is back where it was before ⇧⌘I


Feature: Import
  Board 12, the result card

  Scenario: 9. Everything lands: the sheet closes at once
    Given the plan from scenario 5, everything ticked
    When I click Import (or press Return)
    Then the sheet closes straight away, with no result shown
    And the sidebar shows, in its own order, Internal tools, Payments API and Small API
    And Payments API is selected, scrolled into view, and the sidebar has focus (its selection is accent-coloured, not grey)
    And in Terminal B, ls /tmp/raccoon-postman/environments prints: Dev.json  Prod 2.json  Prod.json
    And cat "/tmp/raccoon-postman/environments/Prod 2.json" shows api_key and token with "secret" : true and no value
    And security find-generic-password -s "Raccoon/70574A40-0000-4000-8000-000000000001/Dev" -a api_key -w prints: dev-not-a-real-key
    And cat /tmp/raccoon-postman/globals.json lists base_url first, still "https://raccoon.example", then api_version, merchant, currency, page_size, region, tenant, timeout_ms, trace_header, retry_count, support_email, docs_url

  Scenario: 10. Re-import never overwrites
    Given scenario 9 ran
    When I press ⇧⌘I and pick Small API.postman_collection.json and workspace.postman_globals.json
    Then the rows read:
      | name                     | under it                                                                                                      |
      | Small API → Small API 2  | Collection · 3 Requests in 1 Folder · “Small API” already exists                                              |
      | Globals                  | 0 new · 5 kept as they are in Raccoon (base_url, trace_header, retry_count, support_email, docs_url)          |
    When I click Import
    Then the sheet closes, and Small API 2 is selected in the sidebar beside Small API

  Scenario: 11. A Collection or Environment that doesn't write: the result, then Done
    Given I quit Raccoon, made a fresh copy of the Workspace, and in Terminal B ran:
      rm -rf /tmp/raccoon-postman/environments && touch /tmp/raccoon-postman/environments
    And I launched Raccoon again
    When I press ⇧⌘I, pick Small API.postman_collection.json and Dev.postman_environment.json, and click Import
    Then the sheet stays open and is replaced by the result:
      | glyph               | line                                                                                     |
      | heading, semibold   | Imported 1 of 2                                                                          |
      | ✓ in label colour   | Small API                                                                                |
      | red circled !       | Dev was not written: file exists. Nothing of it was left in the Data Folder.             |
    And the footer holds only Done, blue; Cancel, Import and the "Imports into" line are gone
    And the sidebar already shows Small API
    When I click Done (or press Return)
    Then the sheet closes, and Small API is selected in the sidebar with focus
    And security find-generic-password -s "Raccoon/70574A40-0000-4000-8000-000000000001/Dev" -a api_key prints "The specified item could not be found in the keychain."

  Scenario: 12. A secret the Keychain refuses: imported with no value
    Given I quit Raccoon, made a fresh copy of the Workspace, and in Terminal B ran:
      echo '{ not json' > /tmp/raccoon-postman/raccoon.json
    And I launched Raccoon again
    When I press ⇧⌘I, pick Dev.postman_environment.json, and click Import
    Then the result reads:
      | glyph               | line                                                                          |
      | heading, semibold   | Imported 1 of 1                                                               |
      | ✓ in label colour   | Dev                                                                           |
      | ⚠ orange            | The Keychain refused 1 secret (api_key in Dev). It is imported with no value. |
      | ⚠ orange            | The Keychain refused 1 secret (token in Dev). It is imported with no value.   |
    When I click Done
    Then the sheet closes and the sidebar selection does not change: no Collection was imported
    And cat /tmp/raccoon-postman/environments/Dev.json shows api_key and token with "secret" : true and no value


Feature: What can't be imported
  §4 on the sheet

  Scenario: 13. A file that isn't a Postman export
    When I press ⇧⌘I and pick only insomnia-export.json
    Then the sheet has one row: page glyph, insomnia-export.json in regular grey, "Not a Postman export Raccoon reads", its checkbox off and greyed
    And there is no "What won't come across" heading
    And Import is greyed out

  Scenario: 14. A file that can't be read: that row says why, the rest import
    Given in Terminal B I ran:
      cp "manual-tests/postman-import/files/Small API.postman_collection.json" /tmp/locked.json && chmod 000 /tmp/locked.json
    When I press ⇧⌘I, pick /tmp/locked.json and Dev.postman_environment.json (⇧⌘G /tmp, then ⌘-click both), and click Open
    Then the rows read: Dev (ticked) · locked.json, greyed, with "Can't be read: permission denied" under it
    When I click Import
    Then the sheet closes and in Terminal B, ls /tmp/raccoon-postman/environments prints: Dev.json  Prod.json
    And afterwards: chmod 644 /tmp/locked.json && rm /tmp/locked.json

  Scenario: 15. A Data Folder that can't be written: Import disabled, the reason in the footer
    Given in Terminal B I ran: chmod a-w /tmp/raccoon-postman
    When I press ⇧⌘I, pick Small API.postman_collection.json, and click Open
    Then the row for Small API is ticked as usual
    And the footer reads: "Can't import into /tmp/raccoon-postman. The folder is not writable."
    And Import is greyed out; Cancel still closes the sheet
    And afterwards: chmod u+w /tmp/raccoon-postman

  Scenario: 16. Path variables come across whole, with no note
    When I press ⇧⌘I, go to manual-tests/postman-import/path-variables with ⇧⌘G, pick Posts.postman_collection.json, and click Open
    Then the row reads "Posts" · "Collection · 2 Requests"
    And "What won't come across" is absent: nothing in this file is lost, and no line mentions path variables
    When I click Import
    Then the sheet closes and "Posts" is selected in the sidebar
    When I open "Retry share"
    Then the URL reads "http://localhost:3061/posts/:id/retry-share-social-media" with ":id" drawn as a token
    And under "Query Params" the "Path Variables" table has one row: Name "id", Value "689eba19be47b88f9d590367"
    When I open "Two names, one with no value"
    Then the URL reads "http://localhost:3061/users/:user/posts/:post"
    And the Path Variables table has two rows: "user" with the Value {{user_id}} (red if undefined), and "post" with the empty placeholder "Value"
    And the file Posts/Retry share.json in the Data Folder has "pathVariables": {"id": "689eba19be47b88f9d590367"}

# ─── Known simplifications ────────────────────────────────────────────────────────────────
#
# - Rows follow the file names' order (as Finder lists them), not the order you clicked them.
# - An unticked row shows what that file would add if ticked, after the ticked files before it.
# - A Collection or Folder whose Postman name is empty is left out of a note's names line (the
#   count still counts it); a Collection's row shows the name Import writes, "New Collection".
# - There is no spinner while files are read: parsing happens before the sheet opens.
# - A Keychain refusal is one line per secret, each reading "1 secret", rather than one line
#   per Environment.
# - Esc on the result does nothing: Done (or Return) closes it.
# - The kind glyphs are SF Symbols: square.3.layers.3d, curlybraces, globe, doc. Board 12 draws
#   the Environment glyph as square brackets; curlybraces is the nearest symbol.
# - The notes body caps at 440 pt and scrolls; board 12 shows no scrolling case.
