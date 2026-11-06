# Manual acceptance: Environment Export (M9)
#
# ─── What this file is ────────────────────────────────────────────────────────────────────
#
# Step-by-step checks you run by hand. Each "Scenario" is one check: do the "When" steps,
# then confirm every "Then" line. If a "Then" line is not true, the check failed: note the
# scenario number, the line, and what you saw instead. Inside a Feature, run the scenarios in
# order without resetting: later ones start from where earlier ones left off.
#
# Run the whole file twice: once with macOS Appearance set to Light (System Settings ▸
# Appearance ▸ Light), which is Latte, once with Dark, which is Mocha. The sheet, the save
# panel and the Environments sheet under them are native: system colours in both, so what changes
# is the sheet's own background (light grey in Light, dark grey in Dark), the label colours
# (black / white) and nothing else. The green check, the orange triangle and the red failure line
# are the system's green, orange and red in both. Between the two runs, do "When you are done".
#
# ─── Words used below ─────────────────────────────────────────────────────────────────────
#
# Secret Variable       a Variable whose value is kept in the macOS Keychain. The Environment's
#                       file holds only its name and "secret": true.
# Terminal A            the Terminal window you launch Raccoon from. It stays busy while it runs.
# Terminal B            a second Terminal window (⌘N in Terminal) for every other command.
#
# ─── The test Workspace ───────────────────────────────────────────────────────────────────
#
#   /tmp/raccoon-envexport/raccoon.json                  fixed id 5EC2E7A1-0000-4000-8000-0000000000E2
#   /tmp/raccoon-envexport/globals.json                  one plain Variable, host
#   /tmp/raccoon-envexport/environments/Staging.json     5 Variables, 3 of them secrets:
#                                                        host    plain
#                                                        token   secret, value in the Keychain: example-token-value
#                                                        key     secret, Disabled, value in the Keychain: example-key-value
#                                                        pin     secret, never given a value: no Keychain item
#                                                        debug   plain, Disabled
#   /tmp/raccoon-envexport/environments/Dev.json         1 Variable, no secret
#   /tmp/raccoon-envexport/environments/Broken.json      not JSON: a row with a warning
#
# The values are made-up words, not real keys. Files are saved into /tmp/raccoon-envexport-out:
# in the save panel press ⇧⌘G and type that path to go there.
#
# ─── Before each Feature ──────────────────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder (the commands work in fish, zsh and bash):
#   cd ~/Documents/playground/raccoon
#   swift build
#   chmod -R u+w /tmp/raccoon-envexport-out 2>/dev/null
#   rm -rf /tmp/raccoon-envexport /tmp/raccoon-envexport-out
#   mkdir -p /tmp/raccoon-envexport/environments /tmp/raccoon-envexport-out
#   echo '{"version": 1, "id": "5EC2E7A1-0000-4000-8000-0000000000E2"}' > /tmp/raccoon-envexport/raccoon.json
#   echo '{"version": 1, "variables": [{"name": "host", "value": "globals.example.com"}]}' > /tmp/raccoon-envexport/globals.json
#   echo '{"version": 1, "variables": [{"name": "host", "value": "https://api.example.com"}, {"name": "token", "secret": true}, {"name": "key", "isEnabled": false, "secret": true}, {"name": "pin", "secret": true}, {"name": "debug", "isEnabled": false, "value": "true"}]}' > /tmp/raccoon-envexport/environments/Staging.json
#   echo '{"version": 1, "variables": [{"name": "host", "value": "https://dev.example.com"}]}' > /tmp/raccoon-envexport/environments/Dev.json
#   echo '{ not json' > /tmp/raccoon-envexport/environments/Broken.json
#   security add-generic-password -U -A -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a token -w example-token-value
#   security add-generic-password -U -A -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a key -w example-key-value
# "swift build" should end with "Build complete!". The others print nothing. -A lets any app read
# the items, so no system prompt asks about them, except where a scenario says so.
# Then in Terminal A:
#   swift run Raccoon -DataFolder /tmp/raccoon-envexport
# Quit with ⌘Q between Features.
#
# ─── When you are done ────────────────────────────────────────────────────────────────────
#
# Quit Raccoon. In Terminal B (each security line prints either "password has been deleted." or
# "could not be found": both are fine):
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a token
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a key
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/"Staging 2" -a token
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/"Staging 2" -a key
#   security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/"Staging 2" -a pin
#   chmod -R u+w /tmp/raccoon-envexport-out 2>/dev/null
#   rm -rf /tmp/raccoon-envexport /tmp/raccoon-envexport-out
# Your own ~/Raccoon, its Tabs and its secrets were never touched.


Feature: Opening the Export sheet
  Export… in an Environment row's context menu, in the Environments sheet

  Background:
    Given Raccoon is running on /tmp/raccoon-envexport and I pressed ⌥⌃E, so the Environments sheet is open

  Scenario: 1. Only a readable Environment has Export…
    Then the list reads, top to bottom: Globals · Environments (a heading) · Broken (with an orange warning triangle) · Dev · Staging
    When I right-click "Staging"
    Then a menu opens with one item: Export…
    When I press Escape and right-click "Dev"
    Then a menu opens with one item: Export…
    When I press Escape and right-click "Globals"
    Then no menu opens
    When I right-click "Broken"
    Then no menu opens
    When I right-click the heading "Environments"
    Then no menu opens
    And right-clicking did not change which row is selected

  Scenario: 2. The sheet, on top of the Environments sheet
    When I right-click "Staging" and choose Export…
    Then a sheet 380 pt wide slides down from the Environments sheet's own title bar, and the Environments sheet stays on the window under it
    And the title reads, in 15 pt semibold: Export “Staging”
    And under it, in 12 pt grey: 5 Variables, 3 secrets
    And a checkbox reads "Include secret values" and is not ticked
    And under the checkbox, indented to its label, in 11 pt grey: Secrets are exported empty.
    And the buttons read Cancel and Export…, Export… being the blue default button
    When I tick the checkbox
    Then the hint reads: Secret values are written to the file in plain text.
    When I untick it
    Then the hint reads: Secrets are exported empty.

  Scenario: 3. The box starts off every time
    Given in scenario 2 the box was last left unticked
    When I tick the box, click Cancel, right-click "Staging" and choose Export… again
    Then the checkbox is not ticked and the hint reads: Secrets are exported empty.

  Scenario: 4. An Environment with no secret has no checkbox
    When I click Cancel, then right-click "Dev" and choose Export…
    Then the title reads: Export “Dev”
    And under it: 1 Variable, 0 secrets
    And there is no checkbox and no hint, only Cancel and Export…

  Scenario: 5. Cancel and Esc write nothing, and the Environments sheet is as it was
    Given the Export sheet is open on Staging with the box ticked
    When I click Cancel
    Then the Export sheet slides up, the Environments sheet is still there with Staging's row where it was, and focus is in the Environments sheet's list
    And ls -A /tmp/raccoon-envexport-out prints nothing
    When I open the Export sheet again and press Escape
    Then the same happens
    And no system prompt about the Keychain appeared


Feature: Saving
  The save panel, as a sheet on the Export sheet

  Background:
    Given the Export sheet is open on Staging

  Scenario: 6. Export… opens the save panel on top of the sheet
    When I click Export… (or press Return)
    Then a save panel slides down from the Export sheet's own title bar, the Export sheet and the Environments sheet staying on the window under it
    And its name field reads Staging.postman_environment.json
    And the file it saves is a .json file
    When I click Cancel in the save panel
    Then the panel slides up, the Export sheet is still there with Export… enabled and no red line, and the box is as I left it
    And ls -A /tmp/raccoon-envexport-out prints nothing

  Scenario: 7. The box off: every secret is written empty
    Given the box is not ticked
    When I click Export…, go to /tmp/raccoon-envexport-out with ⇧⌘G, and click Save
    Then the save panel and the Export sheet both slide up, the Environments sheet is still open, and focus is in its list
    And ls /tmp/raccoon-envexport-out prints: Staging.postman_environment.json
    And grep -c "example-" /tmp/raccoon-envexport-out/Staging.postman_environment.json prints: 0
    And python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["name"], d["_postman_variable_scope"], d["_postman_exported_using"].split("/")[0]); [print(v["key"], v["type"], repr(v["value"]), v["enabled"]) for v in d["values"]]' /tmp/raccoon-envexport-out/Staging.postman_environment.json prints:
      Staging environment Raccoon
      host default 'https://api.example.com' True
      token secret '' True
      key secret '' False
      pin secret '' True
      debug default 'true' False
    And diff -r on environments/ shows the Data Folder is as it was: cat /tmp/raccoon-envexport/environments/Staging.json still holds no value for token

  Scenario: 8. The box on: the values are in the file
    Given I opened the Export sheet on Staging again and ticked the box
    When I click Export…, go to /tmp/raccoon-envexport-out, change the name to Staging-with-secrets.postman_environment.json, and click Save
    Then both sheets slide up, with no result and no orange line
    And python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [print(v["key"], v["type"], repr(v["value"]), v["enabled"]) for v in d["values"]]' /tmp/raccoon-envexport-out/Staging-with-secrets.postman_environment.json prints:
      host default 'https://api.example.com' True
      token secret 'example-token-value' True
      key secret 'example-key-value' False
      pin secret '' True
    And the Disabled secret key holds its value too
    And pin, which was never given a value, is empty and nothing says so

  Scenario: 9. A Keychain that refuses a secret: it is named after the write, never a failed export
    # The item "key" is made so that only the `security` tool is trusted with it: when Raccoon reads
    # it, macOS asks, and Deny is a refusal. Your login Keychain is never locked.
    Given in Terminal B I ran:
      security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a key
      security add-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a key -w example-key-value
    And the Environments sheet is open with Globals still selected, so no Staging row was selected (selecting it reads the Keychain)
    And I right-clicked "Staging", chose Export…, ticked the box, clicked Export…, went to /tmp/raccoon-envexport-out in the save panel, named the file Refused.postman_environment.json, and left the panel open
    # Nothing has asked for a password yet: the Keychain is read only after Save.
    When I click Save in the panel
    Then a system dialog asks whether Raccoon may use the "key" item, with Deny, Allow and Always Allow
    When I click Deny (never Always Allow)
    Then the save panel slides up and the same sheet shows its result instead of the form
    And the orange line reads: 1 secret could not be read from the Keychain and is empty in the file.
    And under it, in 11 pt grey monospace on one line: key
    And a green check reads: Exported to Refused.postman_environment.json, and there is no red line
    And Done is the only button, and it is the blue default button
    # Record what you saw, whichever way it went:
    #   - whether the dialog asked once (for key) or also for token or pin
    #   - what Deny's dialog was titled, and whether the sheet waited for it
    #   - how the sheet changed: it should shrink and stay top-anchored under the Environments
    #     sheet's title bar, with no jump of the Environments sheet underneath
    And ls /tmp/raccoon-envexport-out prints Refused.postman_environment.json among the files
    And python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [print(v["key"], repr(v["value"])) for v in d["values"] if v["type"]=="secret"]' /tmp/raccoon-envexport-out/Refused.postman_environment.json prints token 'example-token-value', key '' and pin ''
    And pin is not in the orange line: it has no item, so there was nothing to read
    When I press Return
    Then the sheet slides up, the Environments sheet is still open, and focus is in its list
    When I repeat this scenario from the Given (delete and add "key" the same way, open the Export sheet, tick, Export…, name the file Refused2.postman_environment.json, Save, Deny) and this time click Done
    Then the sheet closes just as it did on Return
    When in Terminal B I run, to give "key" back to the later scenarios:
      security delete-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a key
      security add-generic-password -U -A -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/Staging -a key -w example-key-value
    Then nothing in the Data Folder changed

  Scenario: 10. A target that is not writable: the reason on the sheet, the values dropped with it
    Given I opened the Export sheet on Staging and ticked the box
    And I clicked Export… and went to /tmp/raccoon-envexport-out in the save panel, and left the panel open
    And in Terminal B I ran: chmod 555 /tmp/raccoon-envexport-out
    When I click Save in the panel
    Then the save panel slides up and the Export sheet stays open, showing its form, not a result
    And above the buttons, in 11 pt red, one line reads: Not exported. Permission denied.
    And Export… is still enabled and the box is still ticked
    And ls -A /tmp/raccoon-envexport-out prints only the files of scenarios 7 to 9: nothing half-written, no temp file
    # If the save panel itself refuses with a system alert when the folder is read-only, that is the
    # system's check before Raccoon's: note what it said, and that no file was written either way.
    When in Terminal B I run chmod 755 /tmp/raccoon-envexport-out, then click Export… again, name the file Retry.postman_environment.json and click Save
    Then both sheets slide up, the red line was only on the sheet that is gone
    And python3 -c 'import json,sys; print([v["value"] for v in json.load(open(sys.argv[1]))["values"] if v["key"]=="token"])' /tmp/raccoon-envexport-out/Retry.postman_environment.json prints: ['example-token-value']


Feature: The file comes back
  File ▸ Import from Postman… reads what Export wrote

  Scenario: 11. Re-importing the file with the secrets gives the same Environment
    Given Raccoon is running on /tmp/raccoon-envexport and scenario 8 ran
    When I press ⇧⌘I, pick /tmp/raccoon-envexport-out/Staging-with-secrets.postman_environment.json, and click Import
    Then the sheet lists one row: ticked, Staging → Staging 2, "Environment · 5 Variables, 3 secrets · “Staging” already exists", Staging-with-secrets.postman_environment.json (Import never overwrites)
    And there is no note under "What won't come across" about this file
    When I click Done and press ⌥⌃E and select "Staging 2"
    Then its table reads, in order: host (Enabled, value https://api.example.com) · token (Enabled, locked, value bullets) · key (not Enabled, locked, value bullets) · pin (Enabled, locked, value "Not in the Keychain") · debug (not Enabled, value true)
    And in Terminal B, security find-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/"Staging 2" -a token -w prints: example-token-value
    And security find-generic-password -s Raccoon/5EC2E7A1-0000-4000-8000-0000000000E2/"Staging 2" -a key -w prints: example-key-value
    And cat /tmp/raccoon-envexport/environments/"Staging 2.json" holds no secret value, only "secret": true for token, key and pin

  Scenario: 12. Re-importing the file without secrets gives the secrets without values
    Given scenario 7 ran
    When I press ⇧⌘I, pick /tmp/raccoon-envexport-out/Staging.postman_environment.json, and click Import
    Then the sheet lists one row: ticked, Staging → Staging 3, "Environment · 5 Variables, 3 secrets · “Staging” already exists", Staging.postman_environment.json
    And in the Environments sheet its token, key and pin all read "Not in the Keychain"


Feature: Worst case (break-ui)

  Scenario: 13. A 120-character name and many Variables
    Given I quit Raccoon and in Terminal B ran:
      python3 - <<'PY'
      import json
      name = "E" * 120
      vs = [{"name": f"var_{i}", "value": "x"} for i in range(140)] + [{"name": f"secret_{i}", "secret": True} for i in range(60)]
      json.dump({"version": 1, "variables": vs}, open(f"/tmp/raccoon-envexport/environments/{name}.json", "w"))
      PY
    And I launched Raccoon again, pressed ⌥⌃E, right-clicked the Environment named with the 120 characters, and chose Export…
    Then the title is cut at its end with "…", on one line, and the sheet is still 380 pt wide
    And under it: 200 Variables, 60 secrets
    When I click Export… and Save in /tmp/raccoon-envexport-out
    Then the file holds 200 values, 60 of them type secret with an empty value: python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["values"]), sum(v["type"]=="secret" and v["value"]=="" for v in d["values"]))' "/tmp/raccoon-envexport-out/$(printf 'E%.0s' $(seq 1 120)).postman_environment.json" prints: 200 60


Feature: Import from the Environments sheet
  The footer's icon button closes the sheet, then runs File ▸ Import from Postman… (⇧⌘I)

  Background:
    Given Raccoon is running on /tmp/raccoon-envexport and I pressed ⌥⌃E, so the Environments sheet is open

  Scenario: 14. The button, the open panel, and Cancel
    Then under the list, at the footer's trailing edge and well apart from + and −, there is one icon-only button, a tray with a down arrow, 24 pt wide, borderless
    When I rest the pointer on it
    Then after a moment a tooltip reads "Import from Postman…"
    When I click it
    Then the Environments sheet slides up, and only then an open panel slides down from the window's title bar, with Open and Cancel buttons
    And the Environments sheet is not behind or on top of it
    When I click Cancel
    Then the open panel slides up and no sheet is open: the window is as it is with no sheet, and nothing was written
    When I press ⌥⌃E
    Then the Environments sheet opens again, listing Globals, then under Environments: Broken (with its warning), Dev and Staging

  Scenario: 15. Importing a Postman Environment from the sheet
    Given scenario 14 ran, so the Environments sheet is closed
    When I press ⌥⌃E and click the Import from Postman… button
    And in the open panel I press ⇧⌘G, type ~/Documents/playground/raccoon/example, press Return, pick "Sociolla Beauty Journal.postman_environment.json" and click Open
    Then the Import sheet slides down with one row: ticked, Sociolla Beauty Journal, "Environment · 14 Variables", Sociolla Beauty Journal.postman_environment.json
    When I click Import
    Then the sheet closes straight away and nothing else opens: the Environments sheet is not shown again
    When I press ⌥⌃E
    Then under Environments the list reads Broken, Dev, Sociolla Beauty Journal, Staging
    When I select "Sociolla Beauty Journal"
    Then its table has 14 rows, all Enabled and none locked, the first uat_host and the last local_accounts
    And in Terminal B, python3 -c 'import json; print(len(json.load(open("/tmp/raccoon-envexport/environments/Sociolla Beauty Journal.json"))["variables"]))' prints: 14
