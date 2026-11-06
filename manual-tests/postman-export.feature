# Manual acceptance: Collection Export (M9)
#
# ─── What this file is ────────────────────────────────────────────────────────────────────
#
# Step-by-step checks you run by hand. Each "Scenario" is one check: do the "When" steps,
# then confirm every "Then" line. If a "Then" line is not true, the check failed: note which
# line and what you saw instead.
#
# Run every Feature twice: once with macOS Appearance set to Light (System Settings ▸
# Appearance ▸ Light), which is Latte, once with Dark, which is Mocha. The sheet and the save
# panel are native: system colours in both, so what changes is the sheet's own background (light
# grey in Light, dark grey in Dark), the label colours (black / white) and nothing else. The
# green checks, the orange triangles and the red failure line are the system's green, orange
# and red in both.
#
# ─── The sample data ──────────────────────────────────────────────────────────────────────
#
# manual-tests/postman-export/datafolder/ is the Workspace you export from:
#   Payments API   7 Requests in 3 Folders (Refunds, Refunds ▸ Archive, Webhooks), and a
#                  Broken.json that is not JSON (an unreadable row).
#                  5 credentials in 4 Requests, in tree order: Old refund (a Basic password),
#                  Create refund (an api_key Param, Disabled), Capture charge (an X-Api-Key
#                  header and a Bearer token: two credentials, one name) and Create charge (an
#                  Authorization header). List charges has Authorization: Bearer {{token}}, a
#                  reference, so it is not one.
#   Clean API      2 Requests, no Folder, no credential
#   Big Collection 40 Requests named "Request number 1" … "Request number 40", each with a
#                  literal Authorization header: 40 credentials
#
# ─── Before each Feature ──────────────────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder (fish, zsh and bash):
#   cd ~/Documents/playground/raccoon
#   rm -rf /tmp/raccoon-export /tmp/raccoon-export-out
#   cp -R manual-tests/postman-export/datafolder /tmp/raccoon-export && mkdir /tmp/raccoon-export-out
# Then in Terminal A:
#   swift run Raccoon -DataFolder /tmp/raccoon-export
# Quit with ⌘Q between Features. Files are saved into /tmp/raccoon-export-out: in the save
# panel press ⇧⌘G and type that path to go there.
#
# Nothing in these Features writes to the Keychain or to the Data Folder.


Feature: Opening the Export sheet
  File ▸ Export Collection… and a Collection row's menu

  Background:
    Given a fresh copy of the datafolder, Raccoon launched with it, and all three Collections shown in the sidebar

  Scenario: 1. File ▸ Export Collection… follows the selection
    When I open the File menu with nothing selected in the sidebar
    Then it reads, top to bottom: New Tab ⌘T · New Collection · a separator · Import from Postman… ⇧⌘I · Export Collection… · a separator · Save ⌘S · a separator · Close Tab ⌘W
    And Export Collection… is greyed out and has no shortcut
    When I press Escape and click the Collection row "Clean API"
    And I open the File menu
    Then Export Collection… is enabled
    When I press Escape, expand Payments API and Refunds, and click the Request "List refunds"
    And I open the File menu
    Then Export Collection… is still enabled, and choosing it opens the sheet titled Export “Payments API”

  Scenario: 2. Only a Collection row's context menu has Export…
    When I right-click "Payments API"
    Then the menu reads New Folder… · Rename… · Export… · a separator · Move to Trash · Reveal in Finder
    When I choose Export…
    Then a sheet titled Export “Payments API” slides down from the window's title bar
    When I click Cancel and right-click "Refunds"
    Then the menu reads New Folder… · Rename… · Move To ▸ · a separator · Move to Trash · Reveal in Finder, with no Export…
    When I right-click "List refunds" and then "Broken.json"
    Then neither menu has Export…

  Scenario: 3. While the sheet is up, File ▸ Export Collection… is greyed out
    Given the Export sheet is open on Payments API
    When I open the File menu
    Then Export Collection… is greyed out
    And ⇧⌘I does not open an open panel
    When I press Escape
    Then the sheet is gone, and File ▸ Export Collection… is enabled again


Feature: The steps, then the counts
  The sheet, in Latte and in Mocha

  Scenario: 4. The layout, on a Collection with nothing to warn about
    Given I right-click "Clean API" and choose Export…
    Then a sheet 440 pt wide slides down, with 20 pt margins
    And its title reads Export “Clean API”, in 15 pt semibold
    And under it are three rows, each a green check then a 13 pt label:
      | row | text                                       |
      | 1   | Read 2 Requests from /tmp/raccoon-export   |
      | 2   | Formatted as Collection Format v2.1        |
      | 3   | Scanned for credentials                    |
    And under the rows, in 13 pt, it reads: 2 Requests · 0 Folders
    And there is no warning, no info line and no red line
    And at the trailing edge are Cancel and Export…, Export… blue (the default button)
    And the sheet did not change size while the checks appeared, except for growing to hold the counts

  Scenario: 5. The checks fade in one after another, opacity only
    Given Reduce Motion is off (System Settings ▸ Accessibility ▸ Display)
    When I open the sheet on Clean API again
    Then the three checks fade in from top to bottom, about 60 ms apart, each over about 150 ms
    And nothing slides or grows while they do: only opacity changes
    And the counts appear in the same frame as the third check, with no fade of their own
    And Export… is greyed out until the third check shows, then enabled in that same frame

  Scenario: 6. Reduce Motion: the steps appear at once
    Given Reduce Motion is on
    When I open the sheet on Clean API
    Then all three rows, the counts and an enabled Export… are there at once, with no fade
    And I turn Reduce Motion off again

  Scenario: 7. Credentials, and a file that is not exported
    Given I right-click "Payments API" and choose Export…
    Then the row 1 text reads: Read 7 Requests from /tmp/raccoon-export
    And the counts read: 7 Requests · 3 Folders
    And under the counts, in this order:
      | glyph                        | line                                                                  | size                  |
      | orange filled triangle       | 5 credentials in plain text                                           | 13 pt semibold        |
      |                              | The file keeps them exactly as typed.                                 | 12 pt, grey           |
      |                              | Old refund · Create refund · Capture charge · Create charge          | 11 pt, grey, one line |
      | orange filled triangle       | 1 file is not exported                                                | 13 pt semibold        |
      |                              | Raccoon can't read it as a Request, and won't change it.             | 12 pt, grey           |
      |                              | Broken.json                                                           | 11 pt, grey, one line |
    And "Capture charge" is named once, though it holds two credentials
    And "List charges" is not named: its Authorization is {{token}}
    And Export… is enabled, and no value (no "tok_example", no "hunter2") is printed anywhere on the sheet

  Scenario: 8. A Request with edits in a Tab
    Given I opened "List charges" and added a header named X-Edited in its Tab, without saving
    When I right-click "Payments API" and choose Export…
    Then under the warnings an ⓘ line in 12 pt grey reads: 1 Request has edits in a Tab. Export uses what is saved.
    And Export… is enabled
    Given I close the sheet, and also edit "Create refund" in a second Tab without saving
    When I open the Export sheet on Payments API again
    Then the ⓘ line reads: 2 Requests have edits in Tabs. Export uses what is saved.

  Scenario: 9. Cancel and Escape write nothing
    Given the Export sheet is open on Payments API
    When I click Cancel
    Then the sheet slides up and focus is where it was before
    And in Terminal B, ls -A /tmp/raccoon-export-out prints nothing
    When I open the sheet again and press Escape
    Then the sheet closes, and ls -A /tmp/raccoon-export-out still prints nothing


Feature: Saving
  The save panel, as a sheet on the Export sheet

  Background:
    Given the Export sheet is open on Payments API, with its three rows and Export… enabled

  Scenario: 10. Export… opens the save panel on top of the sheet
    When I click Export… (or press Return)
    Then a save panel slides down from the Export sheet's own title bar, the Export sheet staying on the window under it
    And its name field reads Payments API.postman_collection.json
    And the file it saves is a .json file
    When I click Cancel in the save panel
    Then the panel slides up, the Export sheet is still there with Export… enabled and no red line
    And ls -A /tmp/raccoon-export-out prints nothing

  Scenario: 11. Save: the file is the one the sheet described
    When I click Export…, go to /tmp/raccoon-export-out with ⇧⌘G, and click Save
    Then the save panel and the Export sheet both slide up, and focus is where it was before
    And ls /tmp/raccoon-export-out prints: Payments API.postman_collection.json
    And python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["info"]["name"], len(d["item"]))' "/tmp/raccoon-export-out/Payments API.postman_collection.json" prints: Payments API 5
    And grep -c "tok_example_0000000000000000" "/tmp/raccoon-export-out/Payments API.postman_collection.json" prints: 1
    And grep -c "Broken" "/tmp/raccoon-export-out/Payments API.postman_collection.json" prints: 0
    And grep -c "X-Edited" "/tmp/raccoon-export-out/Payments API.postman_collection.json" prints: 0 (what is saved, never the Tab's edit)
    And diff -r manual-tests/postman-export/datafolder /tmp/raccoon-export prints nothing: the Data Folder is as it was

  Scenario: 12. A target that is not writable: the reason on the sheet, nothing half-written
    Given I click Export… and go to /tmp/raccoon-export-out in the save panel, and leave the panel open
    And in Terminal B I ran: chmod 555 /tmp/raccoon-export-out
    When I click Save in the panel
    Then the save panel slides up and the Export sheet stays open
    And above the buttons, in 11 pt red, one line reads: Not exported. Permission denied.
    And Export… is still enabled
    And ls -A /tmp/raccoon-export-out prints nothing: no file and no temp file
    When in Terminal B I run chmod 755 /tmp/raccoon-export-out, then click Export… again and Save in the same place
    Then the sheets slide up, and the red line was only on the sheet that is gone
    And ls /tmp/raccoon-export-out prints: Payments API.postman_collection.json
    # If the save panel itself refuses with a system alert when the folder is read-only, that is the
    # system's check before Raccoon's: note what it said, and that no file was written either way.

  Scenario: 12b. The same failure, on a file that cannot be replaced
    Given in Terminal B I ran:
      cp manual-tests/postman-export/datafolder/"Clean API"/Ping.json "/tmp/raccoon-export-out/Payments API.postman_collection.json"
      chflags uchg "/tmp/raccoon-export-out/Payments API.postman_collection.json"
    When I click Export…, go to /tmp/raccoon-export-out, keep the name Payments API.postman_collection.json, click Save, and click Replace
    Then the save panel slides up and the Export sheet stays open
    And above the buttons, in 11 pt red, one line reads: Not exported. followed by the system's reason (probably "Operation not permitted.", which may differ from scenario 12's "Permission denied.")
    And Export… is still enabled
    And shasum "/tmp/raccoon-export-out/Payments API.postman_collection.json" equals shasum manual-tests/postman-export/datafolder/"Clean API"/Ping.json: the old file is as it was
    And ls -A /tmp/raccoon-export-out prints only: Payments API.postman_collection.json (no temp file)
    When in Terminal B I run chflags nouchg "/tmp/raccoon-export-out/Payments API.postman_collection.json"
    And I click Export… again, choose the same file, click Save and Replace
    Then the sheets slide up, and the file now holds the export: grep -c '"info"' "/tmp/raccoon-export-out/Payments API.postman_collection.json" prints: 1

  Scenario: 13. Saving over a file asks first, and a failed replace leaves the old file
    Given scenario 11 ran
    When I open the Export sheet on Payments API and click Export…, choose /tmp/raccoon-export-out, and click Save
    Then the system asks whether to replace Payments API.postman_collection.json
    When I click Cancel in that question
    Then I am back in the save panel, and the file's modification time is unchanged
    When I click Replace
    Then the sheets slide up, and the file holds a new info._postman_id (the only line that differs between two exports)


Feature: Worst case (break-ui)
  Long lists, long names, nothing in the Collection

  Scenario: 14. A warning naming 40 Requests stays one line
    Given I right-click "Big Collection" and choose Export…
    Then the counts read: 40 Requests · 0 Folders
    And the warning reads: 40 credentials in plain text
    And its names line is one 11 pt grey line that starts "Request number 1 · Request number 2" and ends "and 37 more" (a different number of names on another font is fine: it ends in "and N more" and never wraps)
    And hovering it shows a tooltip with every name, up to Request number 40
    And the sheet is still 440 pt wide, with nothing cut off at its edges

  Scenario: 15. A Collection and a skipped file with 120-character names
    Given I quit Raccoon and in Terminal B ran:
      N=$(printf 'LongName%.0s' $(seq 1 15))
      mv "/tmp/raccoon-export/Clean API" "/tmp/raccoon-export/$N"
      cp "/tmp/raccoon-export/Payments API/Broken.json" "/tmp/raccoon-export/$N/$N.json"
    And I launched Raccoon again, right-clicked the Collection named with the 120 characters (the second row, between Big Collection and Payments API), and chose Export…
    Then the title is cut at its end with "…", on one line, and the sheet is still 440 pt wide
    And the warning "1 file is not exported" has a names line that is one line, with the long file name cut in the middle and ending ".json"
    And the row 1 text is one line: nothing wraps

  Scenario: 16. A Collection with no Request exports
    Given I chose File ▸ New Collection, named it "Empty", and right-clicked it and chose Export…
    Then row 1 reads: Read 0 Requests from /tmp/raccoon-export
    And the counts read: 0 Requests · 0 Folders
    And there is no warning, and Export… is enabled
    When I click Export…, go to /tmp/raccoon-export-out, and click Save
    Then python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["item"])' /tmp/raccoon-export-out/Empty.postman_collection.json prints: []


Feature: The example Collection
  Needs example/Sociolla.postman_collection.json, which is not in the repository

  Scenario: 17. Import, then export: 41 Requests, 11 Folders, 18 credentials
    Given a fresh empty Workspace: rm -rf /tmp/raccoon-sociolla && swift run Raccoon -DataFolder /tmp/raccoon-sociolla
    When I press ⇧⌘I, pick example/Sociolla.postman_collection.json, and click Import
    And I right-click "Sociolla" and choose Export…
    Then row 1 reads: Read 41 Requests from /tmp/raccoon-sociolla
    And the counts read: 41 Requests · 11 Folders
    And the warning reads: 18 credentials in plain text
    And there is no "not exported" warning
    And under the warning, the first names line is one 11 pt grey line ending in "and N more"
