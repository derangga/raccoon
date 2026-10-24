# Manual acceptance: Workspaces (M8)
#
# ─── What this file is ────────────────────────────────────────────────────────────────────
#
# Step-by-step checks you run by hand. Each "Scenario" is one check: do the "When" steps,
# then confirm every "Then" line. If a "Then" line is not true, the check failed: note which
# line and what you saw instead.
#
# Part 1, "One Session file per Data Folder", runs on the current build.
# Parts 2 onward describe the Workspace pop-up and run on the current build. Run each Feature
# twice: once with macOS Appearance set to Light (System Settings ▸ Appearance ▸ Light),
# once with Dark.
#
# ─── Words used below ─────────────────────────────────────────────────────────────────────
#
# Data Folder   the folder on disk whose sub-folders show as Collections in the sidebar.
#               Normally ~/Raccoon. Here we use two throwaway folders in /tmp instead.
# Tab           one request editor along the top of the window (the "strip").
# Draft         a Tab that is not saved to a file. A new Tab is a Draft.
# Session       the list of open Tabs Raccoon saves when you quit and restores when you
#               launch. Each Data Folder has its own Session file in
#               ~/Library/Application Support/Raccoon/sessions/
# Terminal A    the Terminal window you launch Raccoon from. It stays busy while Raccoon runs.
# Terminal B    a second Terminal window (⌘N in Terminal) for every other command.
#
# ─── How launching works ──────────────────────────────────────────────────────────────────
#
# You launch Raccoon from Terminal A, inside the project folder:
#   cd ~/Documents/playground/raccoon
#   swift run Raccoon -DataFolder /tmp/raccoon-work/api
# Everything after "Raccoon" is handed to the app. "-DataFolder <path>" tells Raccoon to open
# that folder instead of ~/Raccoon, for this launch only: nothing is saved, so plain
# "swift run Raccoon" later opens ~/Raccoon with your own Tabs, as before.
# Quit Raccoon with ⌘Q while its window is in front. Terminal A then shows its prompt again.
#
# ─── The two test folders and their Session files ─────────────────────────────────────────
#
#   Data Folder               its Session file, in ~/Library/Application Support/Raccoon/sessions/
#   /tmp/raccoon-work/api     288e302558ab9f61.json
#   /tmp/raccoon-side/api     77b241eff6ff9fb5.json
#
# The name is the first 16 characters of the SHA-256 of the folder's path, so each folder
# gets its own file. To check one yourself: printf %s /tmp/raccoon-work/api | shasum -a 256
#
# ─── Before you start (once) ──────────────────────────────────────────────────────────────
#
# In Terminal B, inside the project folder:
#   cd ~/Documents/playground/raccoon
#   swift build
#   rm -rf /tmp/raccoon-work /tmp/raccoon-side
#   mkdir -p /tmp/raccoon-work/api /tmp/raccoon-side/api
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/288e302558ab9f61.json
#   rm -f ~/Library/Application\ Support/Raccoon/sessions/77b241eff6ff9fb5.json
# "swift build" should end with "Build complete!". The other commands print nothing.
#
# ─── When you are done ────────────────────────────────────────────────────────────────────
#
# In Terminal B:
#   rm -rf /tmp/raccoon-work /tmp/raccoon-side
#   find ~/Library/Application\ Support/Raccoon/sessions -name '288e302558ab9f61*' -delete
#   find ~/Library/Application\ Support/Raccoon/sessions -name '77b241eff6ff9fb5*' -delete
# Your own ~/Raccoon and its Tabs were never touched.


Feature: One Session file per Data Folder

  Background:
    Given I did "Before you start" above
    And Raccoon is not running

  Scenario: 1. Tabs come back after a relaunch
    When in Terminal A I run: swift run Raccoon -DataFolder /tmp/raccoon-work/api
    Then the Raccoon window opens with one Tab, an empty Draft
    And the sidebar reads "No Collections yet. Create one, or save a Draft into one with ⌘S." with "/tmp/raccoon-work/api" under it
    When I press ⌘T
    Then a second Tab appears and is selected
    When I click the URL field at the top of that Tab and type: https://example.com/a
    And I press ⌘Q
    Then the window closes and Terminal A shows its prompt again
    When in Terminal B I run: ls ~/Library/Application\ Support/Raccoon/sessions/
    Then the list contains "288e302558ab9f61.json"
    When in Terminal A I run again: swift run Raccoon -DataFolder /tmp/raccoon-work/api
    Then the window opens with two Tabs
    And the second Tab is selected
    And its URL field reads "https://example.com/a"
    When I press ⌘Q
    Then Raccoon quits

  Scenario: 2. Each Data Folder keeps its own Tabs
    Given scenario 1 passed, so /tmp/raccoon-work/api has a Tab reading "https://example.com/a"
    When in Terminal A I run: swift run Raccoon -DataFolder /tmp/raccoon-side/api
    Then the window opens with one Tab, an empty Draft
    And no Tab reads "https://example.com/a"
    And the path under the sidebar text reads "/tmp/raccoon-side/api"
    When I click the URL field and type: https://side.example
    And I press ⌘Q
    And in Terminal B I run: ls ~/Library/Application\ Support/Raccoon/sessions/
    Then the list contains both "288e302558ab9f61.json" and "77b241eff6ff9fb5.json"
    When in Terminal A I run: swift run Raccoon -DataFolder /tmp/raccoon-work/api
    Then the two Tabs from scenario 1 are back, the second reading "https://example.com/a"
    And no Tab reads "https://side.example"
    When I press ⌘Q
    And in Terminal A I run: swift run Raccoon -DataFolder /tmp/raccoon-side/api
    Then the one Tab reading "https://side.example" is back
    When I press ⌘Q
    Then Raccoon quits

  Scenario: 3. The same folder written with a trailing slash is the same Session
    Given scenario 1 passed
    When in Terminal A I run: swift run Raccoon -DataFolder /tmp/raccoon-work/api/
    Then the two Tabs from scenario 1 are back, the second reading "https://example.com/a"
    When I press ⌘Q
    And in Terminal B I run: ls ~/Library/Application\ Support/Raccoon/sessions/
    Then the list still has "288e302558ab9f61.json" and no "52c25914804b0547.json" (the name the "/" spelling would get if Raccoon did not drop the slash)

  Scenario: 4. A broken Session file is set aside, not deleted
    Given scenario 1 passed, so the sessions folder exists
    When in Terminal B I run: echo '{ not json' > ~/Library/Application\ Support/Raccoon/sessions/288e302558ab9f61.json
    And in Terminal A I run: swift run Raccoon -DataFolder /tmp/raccoon-work/api
    Then the window opens with one Tab, an empty Draft
    And no alert, banner or message about the Session appears
    When in Terminal B I run: ls ~/Library/Application\ Support/Raccoon/sessions/
    Then the list contains a file named like "288e302558ab9f61.corrupt-2026-10-19T091500Z.json" (today's date and time, in UTC)
    When in Terminal B I run: cat ~/Library/Application\ Support/Raccoon/sessions/288e302558ab9f61.corrupt-*
    Then it prints: { not json
    When I press ⌘Q in Raccoon
    Then Raccoon quits


# ══════════════════════════════════════════════════════════════════════════════════════════
# The Workspace pop-up and switching. Each Feature runs in Light and in Dark, and the
# pop-up, its menu and the banner are compared with board 13:
#   open design/ui/mockups/13-workspaces.html
# ══════════════════════════════════════════════════════════════════════════════════════════


Feature: The Workspace pop-up
  Board 13, in Light and in Dark

  Background:
    Given I did "Before you start" above
    And in Terminal A I ran: swift run Raccoon -DataFolder /tmp/raccoon-work/api
    And I clicked the pop-up at the top of the sidebar, chose "Open Workspace…", pressed ⌘⇧G, typed /tmp/raccoon-side/api, pressed Return and clicked "Open"
    And I chose "api — work" from the pop-up again

  Scenario: The pop-up and its menu
    Then at the top of the sidebar, above the "Filter Collections" field, a pop-up with no border reads "api — work"
    When I click it
    Then a menu opens with these rows, top to bottom:
      | row                | note                          |
      | api — side         |                               |
      | api — work         | has a checkmark: it is open   |
      | (a separator line) |                               |
      | New Workspace…     |                               |
      | Open Workspace…    |                               |
      | Remove from List   | has an arrow ▸: a submenu     |
    When I point at "Remove from List"
    Then its submenu holds one row, "api — side", and not "api — work"
    When I press Escape
    Then the menu closes and nothing changed

  Scenario: Only one Workspace
    Given Raccoon remembers only /tmp/raccoon-work/api
    When I click the pop-up
    Then the pop-up and its only row read "api", with no " — work" after it
    And "Remove from List" has no Workspace to offer

  Scenario: A very long folder name (break-ui)
    Given in Terminal B I made a folder with a 120-character name:
      mkdir -p /tmp/raccoon-long/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    And I added it with "Open Workspace…"
    Then the pop-up shows the start of the name and ends in "…", inside the sidebar's width
    When I click the pop-up
    Then the menu shows the whole 120-character name on its row


Feature: New Workspace… and Open Workspace…
  Board 13, in Light and in Dark

  Background:
    Given in Terminal A I ran: swift run Raccoon -DataFolder /tmp/raccoon-work/api
    And in Terminal B I ran: rm -rf ~/raccoon-new

  Scenario: Create a new Workspace
    When I click the pop-up and choose "New Workspace…"
    Then a save panel slides down from the window's title bar
    And it shows my home folder, and its blue button reads "Create"
    When I type raccoon-new in the name field and click "Create"
    Then the pop-up reads "raccoon-new"
    And the sidebar shows "No Collections yet. Create one, or save a Draft into one with ⌘S."
    And the window has one Tab, an empty Draft
    When in Terminal B I run: cat ~/raccoon-new/raccoon.json
    Then it prints three lines: {, "id" : "<a UUID>", "version" : 1, and a closing }
    When I click the pop-up
    Then "raccoon-new" is in the menu with a checkmark

  Scenario: Cancel creates nothing
    When I click the pop-up, choose "New Workspace…" and click "Cancel"
    Then the panel closes, the pop-up still reads "api"
    And in Terminal B "ls ~/raccoon-new" says "No such file or directory"

  Scenario: The name is already taken
    Given in Terminal B I ran: mkdir ~/raccoon-new
    When I click the pop-up, choose "New Workspace…", type raccoon-new and click "Create"
    Then an alert reads: A folder named “raccoon-new” already exists. Use Open Workspace… to add it.
    And after I click "OK", "ls ~/raccoon-new" in Terminal B prints nothing (no raccoon.json was written)
    And the pop-up still reads "api"

  Scenario: The folder can't be created
    When I click the pop-up, choose "New Workspace…", press ⌘⇧G, type /System, press Return
    And I type raccoon-new and click "Create"
    Then an alert sheet reads: Couldn't create “raccoon-new”: <a reason, such as "operation not permitted">.
    And the pop-up still reads "api"

  Scenario: Open a folder as a Workspace
    When I click the pop-up and choose "Open Workspace…"
    Then an open panel appears that lets me pick one folder and has a "New Folder" button
    When I press ⌘⇧G, type /tmp/raccoon-side/api, press Return and click "Open"
    Then the pop-up reads "api — side"
    And in Terminal B "ls /tmp/raccoon-side/api" lists raccoon.json

  Scenario: Opening a folder that is already listed does not add a second row
    Given the previous scenario passed
    When I choose "api — work" from the pop-up
    And I choose "Open Workspace…" and pick /tmp/raccoon-side/api again
    Then the pop-up reads "api — side"
    And the menu lists "api — side" exactly once


Feature: Switching Workspaces

  Background:
    Given both test folders are listed in the pop-up and "api — work" is open

  Scenario: Each Workspace keeps its own Tabs, and switching never asks to save
    Given in "api — work" I have a Draft reading "https://work.example" and a second Draft reading "https://two.example"
    When I click the pop-up and choose "api — side"
    Then no dialog asks me to save anything
    And the Tabs are those of "api — side", not the two above
    When I click the pop-up and choose "api — work"
    Then both Drafts are back, reading "https://work.example" and "https://two.example"

  Scenario: Choosing the Workspace that is already open does nothing
    When I click the pop-up and choose "api — work"
    Then the Tabs and the sidebar do not change

  Scenario: A request still sending is cancelled by the switch
    Given in "api — work" a Tab reads "https://httpbin.org/delay/10" and I clicked Send
    And the spinner is showing
    When I switch to "api — side" and straight back to "api — work"
    Then that Tab shows no spinner and no Response

  Scenario: Relaunch opens the Workspace that was open
    Given I switched to "api — side"
    When I press ⌘Q and in Terminal A run plain: swift run Raccoon
    Then the pop-up reads "api — side"


Feature: Remove from List
  Board 13, in Light and in Dark

  Background:
    Given both test folders are listed in the pop-up and "api — work" is open
    And "api — side" has an open Draft reading "https://side.example"

  Scenario: Remove from List forgets the Workspace and keeps its folder
    When I click the pop-up and point at "Remove from List", then click "api — side"
    Then the menu no longer lists it, and the remaining row reads "api" (no " — work" any more)
    And in Terminal B "ls /tmp/raccoon-side/api" still lists raccoon.json
    And in Terminal B "ls ~/Library/Application\ Support/Raccoon/sessions/" no longer lists 77b241eff6ff9fb5.json
    When I choose "Open Workspace…" and pick /tmp/raccoon-side/api again
    Then it opens with one empty Draft: "https://side.example" does not come back


Feature: A Workspace that can't be read or written
  Board 13, in Light and in Dark

  Background:
    Given both test folders are listed in the pop-up and "api — work" is open

  Scenario: A listed folder was deleted
    Given in Terminal B I ran: rm -rf /tmp/raccoon-side
    When I click the pop-up and choose "api — side"
    Then a banner at the top of the window says the Data Folder can't be read
    And the banner's buttons read "Remove from List" and "Open Workspace…"
    And the sidebar is empty and the window has one empty Draft
    And in Terminal B "ls /tmp/raccoon-side" says "No such file or directory" (Raccoon did not recreate it)

  Scenario: The banner hides Remove from List when no other Workspace is listed
    Given only /tmp/raccoon-side/api is listed, it is open, and it was deleted
    When I quit and run: swift run Raccoon
    Then the banner shows "Open Workspace…" and no "Remove from List"

  Scenario: A raccoon.json that is not valid
    Given in Terminal B I ran: echo garbage > /tmp/raccoon-side/api/raccoon.json
    When I switch to "api — side"
    Then in Terminal B "cat /tmp/raccoon-side/api/raccoon.json" still prints: garbage
    When I press ⌥⌃E and click + under the list
    And I type token in the empty row's Name cell, press Tab, type abc and press Tab
    And I click the open lock in token's Secret column
    Then a red line under the table reads: Not saved. raccoon.json can't be read.
    And the lock stays open and token's value still reads "abc"
    When I click Done
    Then in Terminal B "cat /tmp/raccoon-side/api/raccoon.json" still prints: garbage

  Scenario: A folder that can be read but not written
    Given in Terminal B I ran: rm -f /tmp/raccoon-side/api/raccoon.json && chmod 500 /tmp/raccoon-side/api
    When I switch to "api — side"
    Then a banner says the Data Folder can't be written
    And the Tabs "api — side" had before are still restored
    And afterwards I run in Terminal B: chmod 700 /tmp/raccoon-side/api
