# Manual acceptance: Collections (M4)
#
# Run every Feature twice: macOS Appearance Light (Latte), then Dark (Mocha).
# Compare against the Raccoon UI canvas boards named in each Feature.
#
# The Data Folder is a copy of manual-tests/collections.datafolder in /tmp, passed as a launch
# argument, so ~/Raccoon is never touched and nothing is remembered:
#   D=/tmp/raccoon-collections
#   rm -rf "$D" && cp -R manual-tests/collections.datafolder "$D"
#   swift run Raccoon -DataFolder "$D"
# Raccoon still reads and writes your real Session:
#   S=~/Library/Application\ Support/Raccoon
# Back it up first (cp "$S/session.json" ~/session.backup.json) and restore it when done.
# "A fresh Session" below means: quit Raccoon (⌘Q), then rm "$S/session.json".
#
# The fixture holds three Collections and an environments/ folder that is not one:
#   Auth Service         POST Login · Login_copy.json (same id as Login.json)
#   Payments API         Refunds/ (DELETE Cancel refund · GET List refunds · Old refund.json,
#                        not valid JSON · PURGE Purge refund cache) · POST Create charge ·
#                        GET List charges · POST Refund charge · PATCH Update charge
#   決済API（本番環境・東京リージョン）  Legacy v1 (do not use after 2027-01-01)/ (a conflicted copy
#                        at file version 3) · PROPFIND 🦝 Webhooks テスト 🚀 · OPTIONS CORS
#                        preflight for the merchant onboarding dashboard · DELETE x ·
#                        GET 請求書の一覧を取得する
# manual-tests/collections.session.json is a Session with one Request Tab per relaunch case.
#
# Accessibility checks use Accessibility Inspector (Xcode ▸ Open Developer Tool).


Feature: The sidebar tree
  Boards 01, 02, 09 and 10, in Latte and in Mocha

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it in a window at least 1200 pt wide

  Scenario: Collections, Folders and Requests
    Then the sidebar shows, under a "Filter Collections" field and the 11 pt semibold label "Collections":
      | row                                  | glyph               |
      | Auth Service                         | stacked layers      |
      | Payments API                         | stacked layers      |
      | 決済API（本番環境・東京リージョン）       | stacked layers      |
    And there is no "environments" row
    When I expand Payments API and Refunds
    Then the rows under Payments API read, in order:
      | badge  | name               | level |
      | folder | Refunds            | 1     |
      | DELETE | Cancel refund      | 2     |
      | GET    | List refunds       | 2     |
      | ⚠      | Old refund.json    | 2     |
      | PURGE  | Purge refund cache | 2     |
      | POST   | Create charge      | 1     |
      | GET    | List charges       | 1     |
      | POST   | Refund charge      | 1     |
      | PATCH  | Update charge      | 1     |
    And each level is indented 16 pt more than its parent, and rows are 24 pt tall
    And every badge is SF Mono bold 9.5 pt, right-aligned in one 52 pt column, in its method's Theme colour, with no chip behind it
    And the sidebar is the plain window background (#f0f0f0 in Light, #2c2c2c in Dark), focused or not

  Scenario: break-ui, board 10
    When I expand 決済API（本番環境・東京リージョン） and Legacy v1 (do not use after 2027-01-01)
    Then "PROPFIND" shows whole in its badge, and "🦝 Webhooks テスト 🚀" sits beside it
    And "CORS preflight for the merchant onboarding dashboard" ends in "…" at the sidebar's edge
    And the single-letter Request "x" still has its DELETE badge

  Scenario: Expansion survives a relaunch
    When I expand Payments API and collapse Refunds, then quit with ⌘Q and relaunch with the same command
    Then Payments API is open and Refunds is closed

  Scenario: No Collections, board 01
    Given Raccoon is launched with -DataFolder /tmp/raccoon-empty instead (it creates the folder)
    Then the sidebar shows "Collections" and below it, in 12 pt secondary text:
      "No Collections yet. Create one, or save a Draft into one with ⌘S."
    And under that "/tmp/raccoon-empty" in SF Mono 11
    And there is no "Filter Collections" field
    And the + button sits at the bottom left of the sidebar


Feature: Unreadable rows and Reveal in Finder
  Boards 09 and 10, in Latte and in Mocha

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it

  Scenario: The three reasons
    When I expand every Collection and Folder
    Then these rows have a yellow warning triangle, the file name in secondary text, and a reason line under it in 11 pt:
      | file                                              | reason                                                      |
      | Login_copy.json                                   | Same id as Login.json.                                      |
      | Old refund.json                                   | Not valid JSON at line 4. Raccoon won't change this file.   |
      | Create charge (conflicted copy 2026-10-14).json   | Unknown file version 3.                                     |
    And each has a 20 × 18 pt icon-only button at its trailing edge with the tooltip "Reveal in Finder"
    And the long conflicted-copy name ends in "…" before the button, and the button and the reason line stay whole

  Scenario: Selecting does nothing, double-click reveals
    When I click the "Old refund.json" row
    Then it is selected and no Tab opens or changes
    When I double-click it
    Then Finder opens with "Old refund.json" selected in Payments API/Refunds
    When I click the Reveal button on "Login_copy.json"
    Then Finder opens with "Login_copy.json" selected

  Scenario: An unreadable file is never rewritten
    When I note the bytes of Old refund.json (shasum "$D/Payments API/Refunds/Old refund.json"), and use Raccoon for a while
    Then its checksum never changes


Feature: Opening a Request
  Board 02

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it, with Payments API expanded

  Scenario: Click opens a clean Tab named after the Request
    When I click "Create charge"
    Then a Tab opens right after the selected Draft and is selected
    And its strip reads POST "Create charge", upright, with no accent dot and no Dirty dot
    And the URL bar reads POST "https://httpbin.org/anything/charges"
    And Headers reads "Headers 1" with the row Idempotency-Key = abc-123

  Scenario: One Tab per Request
    When I click "Create charge", then the Draft Tab, then "Create charge" again
    Then there are still two Tabs, and the Create charge Tab is selected
    When I select the row and press Return
    Then still two Tabs

  Scenario: A file broken on disk opens nothing
    When I run: printf '{' > "$D/Payments API/List charges.json"
    Then within a second the row becomes "List charges.json" with "Not valid JSON at line 1. Raccoon won't change this file."
    And clicking it opens no Tab


Feature: Saving with ⌘S
  Boards 05 and 09

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it
    And cd "$D" && git init -q && git add -A && git commit -qm base

  Scenario: ⌘S on a Request
    When I open "Create charge" and change the Idempotency-Key value to abc-124
    Then its Tab shows the 8 pt Dirty dot
    When I press ⌘S
    Then the dot is gone and no banner appears
    And git diff shows one changed line in "Payments API/Create charge.json": "value" : "abc-124"

  Scenario: An unchanged save writes the same bytes
    When I open "List charges" and press ⌘S
    Then git status is clean

  Scenario: ⌘S on a Draft opens the Save Request sheet
    When I select the Draft, type the URL https://httpbin.org/anything/ping and press ⌘S
    Then a sheet titled "Save Request" slides down with a focused, empty Name field and Cancel · Save
    And Save is disabled
    And the Location pop-up lists:
      | Auth Service |
      | Payments API |
      | Payments API ▸ Refunds |
      | 決済API（本番環境・東京リージョン） |
      | 決済API（本番環境・東京リージョン） ▸ Legacy v1 (do not use after 2027-01-01) |
    When I type "Ping", pick "Payments API ▸ Refunds" and press Return
    Then the sheet closes and the URL field has focus
    And the Tab reads GET "Ping", upright, with no accent dot
    And the row "GET Ping" appears under Refunds
    And "$D/Payments API/Refunds/Ping.json" exists

  Scenario: The sheet remembers the last Location, and a taken name gets " 2"
    When I press ⌘T, type any URL, press ⌘S
    Then Location is already "Payments API ▸ Refunds"
    When I name it "Ping" and save
    Then the file is "Payments API/Refunds/Ping 2.json" and both rows read "Ping"

  Scenario: Cancel writes nothing
    When I press ⌘T, type any URL, press ⌘S, then Esc
    Then the Tab is still a Draft, the URL field has focus, and git status shows nothing new

  Scenario: New Collection… when there are none
    Given Raccoon is launched with -DataFolder /tmp/raccoon-empty
    When I type a URL in the Draft and press ⌘S
    Then the Location pop-up offers only "New Collection…" and a Collection field is shown under it
    And Save stays disabled until both Name and Collection have text
    When I enter Name "Ping" and Collection "Health" and save
    Then the sidebar shows Collection "Health" holding GET "Ping"


Feature: The Tab banners and the Data Folder banner
  Boards 05 and 09, in Latte and in Mocha

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it

  Scenario: Not saved
    When I open "Create charge", add any header, and run: chmod 555 "$D/Payments API"
    And I press ⌘S
    Then between the tab strip and the URL bar a 36 pt banner appears over 200 ms, on backgroundElevated with a border under it:
      "Not saved. Couldn't write Create charge.json: permission denied. The Tab keeps your edits."
    And "Not saved." is semibold, the rest in textSecondary, with a red error glyph and a Dismiss button
    And the Tab keeps its Dirty dot
    When I select another Tab
    Then the banner goes; selecting Create charge again brings it back
    When I click Dismiss
    Then the banner leaves over 150 ms
    And afterwards: chmod 755 "$D/Payments API"

  Scenario: Changed on Disk
    When I open "Update charge" and add the header X-Mine = 1
    And I run: sed -i '' 's#charges/1#charges/42#' "$D/Payments API/Update charge.json"
    Then within a second the banner reads:
      "Changed on Disk. Update charge.json was changed outside Raccoon. Your edits are kept until you choose."
    And it has a yellow warning glyph and the buttons Keep Mine · Reload, Reload primary, and no Dismiss
    And the Tab shows the warning glyph and the Dirty dot
    And the URL still reads ".../charges/1"

  Scenario: Deleted on disk
    When I open "Refund charge" and run: rm "$D/Payments API/Refund charge.json"
    Then the banner reads:
      "Deleted on disk. Refund charge.json is gone. This Tab is now a Draft with your content, and ⌘S saves it again."
    And the Tab turns italic with the accent dot, named "/anything/charges/1/refund", with Dismiss on the banner

  Scenario: Data Folder not writable
    Given mkdir -p /tmp/raccoon-ro && chmod 555 /tmp/raccoon-ro
    When Raccoon is launched with -DataFolder /tmp/raccoon-ro
    Then a banner spans the whole window under the toolbar, above both sidebar and Tabs:
      "Raccoon can't write to the Data Folder. /tmp/raccoon-ro is read-only. Collections are unavailable; Drafts and sending still work."
    And "/tmp/raccoon-ro" is in SF Mono, and Choose Folder… is the primary button
    And the sidebar shows the empty text, and a Draft still sends with ⌘↩
    And ⌘S on a Draft opens no sheet
    When I click Choose Folder…, Cancel the panel
    Then nothing changes
    When I click Choose Folder… and pick "$D" (⇧⌘G in the panel, type /tmp/raccoon-collections)
    Then the banner leaves and the sidebar shows the three Collections

  Scenario: A long path wraps
    Given mkdir -p "/tmp/Library/Mobile Documents/com~apple~CloudDocs/Work/Clients/Northwind/API Collections/Raccoon" and chmod 555 it
    When Raccoon is launched with that path in a 760 pt wide window
    Then the banner text wraps to two or three lines and Choose Folder… stays whole

  Scenario: Reduce Motion
    Given System Settings ▸ Accessibility ▸ Display ▸ Reduce motion is on
    When any banner appears or leaves
    Then it only fades, over 150 ms, with no change of height animated


Feature: Files changed by Terminal or git while open
  Board 05

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And cd "$D" && git init -q && git add -A && git commit -qm base
    And Raccoon is launched with it, with "List charges" and "Update charge" open

  Scenario: A clean Tab follows the file silently
    When I run: sed -i '' 's#anything/charges"#anything/charges?limit=5"#' "$D/Payments API/List charges.json"
    Then the List charges Tab's URL reads "https://httpbin.org/anything/charges?limit=5", with no banner and no dot

  Scenario: Reload
    When I edit Update charge (add a header), then run: sed -i '' 's#charges/1#charges/7#' "$D/Payments API/Update charge.json"
    Then Changed on Disk shows
    When I click Reload
    Then my header is gone, the URL reads ".../charges/7", and the banner, glyph and dot are gone

  Scenario: Keep Mine, then ⌘S writes over
    When I edit Update charge and the file changes as above, and I click Keep Mine
    Then the banner and glyph go, the Dirty dot stays, and my edits stay
    When I press ⌘S
    Then the file holds my edits, with the URL I see

  Scenario: The same bytes written again are not a change
    When I edit Update charge, then run: cp "$D/Payments API/Update charge.json" /tmp/u.json && cp /tmp/u.json "$D/Payments API/Update charge.json"
    Then no Tab changes, my edits stay, and no banner appears

  Scenario: Our own save is not Changed on Disk
    When I edit Update charge and press ⌘S
    Then no Changed on Disk banner ever appears for it

  Scenario: A rename on disk renames the Tab
    When I run: sed -i '' 's#"Update charge"#"Update a charge"#' "$D/Payments API/Update charge.json"
    Then the sidebar row and the Tab both read "Update a charge"

  Scenario: Deleted with git
    When I run: git -C "$D" rm -q "Payments API/List charges.json"
    Then the List charges Tab becomes a Draft with "Deleted on disk." and its row disappears

  Scenario: A file broken under its Tab
    When I add a header to Update charge and run: printf '{' > "$D/Payments API/Update charge.json"
    Then the row turns "Update charge.json" with "Not valid JSON at line 1. Raccoon won't change this file."
    And the Tab keeps my edits
    When I press ⌘S
    Then the banner reads "Not saved. Couldn't write Update charge.json: it can't be read, and Raccoon won't change it. The Tab keeps your edits."
    And the file still holds only "{"

  Scenario: A git checkout of many files is one update
    When I run: for i in $(seq 1 200); do printf '{"version":1,"id":"%s","name":"R%s","method":"GET","url":"x"}' $(uuidgen) $i > "$D/Payments API/R$i.json"; done
    Then within a second the 200 rows appear together, with no visible stutter


Feature: Create, rename, move and Move to Trash
  Board 12 (the + menu); the rest is not drawn

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it

  Scenario: The + menu
    When I click + at the bottom of the sidebar
    Then a menu offers "New Collection" and "New Folder"
    And New Folder is disabled while no row is selected
    When I choose New Collection
    Then a sheet "New Collection" asks for a Name, with Cancel · Create, Create disabled while blank
    When I enter "Health" and press Return
    Then "Health" appears at once between Auth Service and Payments API, and "$D/Health" exists
    And File ▸ New Collection opens the same sheet

  Scenario: New Folder, and a taken name
    When I select "Create charge" and choose + ▸ New Folder, named "Webhooks"
    Then "Webhooks" appears under Payments API after Refunds, before the Requests
    When I do it again with "webhooks"
    Then the second is "webhooks 2"

  Scenario: The context menu
    When I right-click "Create charge"
    Then the menu reads New Folder… · Rename… · Move To ▸ · separator · Move to Trash · Reveal in Finder
    And Move To lists every Collection and Folder as a path, except Payments API where it already is
    When I right-click "Payments API"
    Then there is no Move To
    When I right-click "Old refund.json"
    Then there is no Rename…

  Scenario: Rename a Folder with an open Tab
    When I open "List refunds", add a header, and rename Refunds to "Charges back" from its context menu
    Then the sheet "Rename" is prefilled with "Refunds" and its button reads Rename
    And after Rename the folder reads "Charges back" at once, "$D/Payments API/Charges back" exists
    And the List refunds Tab is still that Request, still Dirty, with no banner
    When I press ⌘S
    Then "$D/Payments API/Charges back/List refunds.json" holds the header

  Scenario: Rename a Request
    When I rename "List charges" to "List all charges"
    Then the row and any open Tab read "List all charges"
    And the file is now "Payments API/List all charges.json" with "name" : "List all charges" inside

  Scenario: Move
    When I choose Move To ▸ Auth Service on "Refund charge" while it is open
    Then it appears under Auth Service at once and its Tab stays on it
    And "$D/Auth Service/Refund charge.json" exists

  Scenario: Move to Trash
    When I choose Move to Trash on "Update charge" while it is open
    Then nothing asks, the row goes, the file is in the Trash (Finder ▸ Trash)
    And its Tab becomes a Draft with "Deleted on disk. Update charge.json is gone. This Tab is now a Draft with your content, and ⌘S saves it again."

  Scenario: A failure says so
    When I run: chmod 555 "$D/Payments API" and rename Refunds
    Then an alert sheet reads "Couldn't rename “Refunds”: permission denied." and nothing changes
    And afterwards: chmod 755 "$D/Payments API"


Feature: The sidebar filter
  Board 11, in Latte and in Mocha

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it

  Scenario: Typing narrows the tree
    When I click "Filter Collections" and type "refund"
    Then with each keystroke the tree narrows, with no delay
    And the "Collections" label gives way to "6 matches in 1 Collection" in 11 pt secondary text
    And the rows are Payments API ▸ Refunds ▸ (Cancel refund, List refunds, Old refund.json, Purge refund cache), then Refund charge, all open
    And in each name the matched text has the yellow find highlight and is semibold, e.g. "Refund" in "Refund charge", "refund" in "List refunds"

  Scenario: Japanese and diacritics
    When I type "テスト"
    Then only 決済API（本番環境・東京リージョン） ▸ "🦝 Webhooks テスト 🚀" shows, "テスト" highlighted, and the count reads "1 match in 1 Collection"

  Scenario: Names only
    When I type "PROPFIND", then "httpbin"
    Then each time the sidebar reads:
      "No Requests, Folders or Collections match “PROPFIND”."
      "Esc clears the filter."

  Scenario: No matches, board 11
    When I type "refnd"
    Then the sidebar reads "No Requests, Folders or Collections match “refnd”." and "Esc clears the filter." on the next line

  Scenario: Esc and Return
    Given only Payments API is expanded
    When I type "refund" and press Esc
    Then the field empties and the tree is back with only Payments API open
    When I press Esc again
    Then focus moves to the URL field of the selected Tab
    When I type "refund" in the filter and press Return
    Then "Cancel refund" opens in a Tab and the URL field has focus, and the filter stays

  Scenario: A change on disk while filtering
    When the filter reads "refund" and I run: cp "$D/Payments API/List charges.json" "$D/Payments API/Refund status.json" && sed -i '' 's#"List charges"#"Refund status"#; s#0C0FFEE0-0000-4000-8000-000000000002#0C0FFEE0-0000-4000-8000-000000000077#' "$D/Payments API/Refund status.json"
    Then "Refund status" joins the results and the count reads "7 matches in 1 Collection"

  Scenario: break-ui, 2,000 matches
    Given a Data Folder with 4 Collections of 500 Requests named "Request 1"…"Request 500"
      (for c in 1 2 3 4; do mkdir -p "$D/C$c"; for i in $(seq 1 500); do printf '{"version":1,"id":"%s","name":"Request %s","method":"GET","url":"x"}' $(uuidgen) $i > "$D/C$c/R$i.json"; done; done)
    When I type "request"
    Then the count reads "2,000 matches in 4 Collections" and the list scrolls smoothly to the end


Feature: Save from the close prompt
  Not drawn; design-system §6 Close confirmation

  Background:
    Given a fresh copy of the fixture Data Folder and a fresh Session
    And Raccoon is launched with it

  Scenario: The prompt
    When I open "Create charge", add a header, and press ⌘W
    Then a sheet asks "Save “Create charge” before closing?"
    And reads "Your edits to this Request haven't been saved and will be lost."
    And offers Save (blue, default), Don't Save (red), Cancel
    When I press Return
    Then the file is written and the Tab closes

  Scenario: A failed Save keeps the Tab
    When I open "Update charge", add a header, chmod 555 "$D/Payments API", press ⌘W and choose Save
    Then the Tab stays open, Dirty, with the Not saved banner
    And afterwards: chmod 755 "$D/Payments API"

  Scenario: A Draft
    When I type a URL in the Draft and press ⌘W
    Then the prompt reads "This Draft hasn't been saved. Its request will be lost."
    When I choose Save
    Then the Save Request sheet follows
    When I press Esc
    Then the Draft stays open
    When I press ⌘W, choose Save, name it "Ping" in Payments API and save
    Then the Tab closes and "Ping" is in the sidebar

  Scenario: Don't Save and Cancel
    When I close an edited Tab and press ⌘D
    Then it closes without writing
    When I close another edited Tab and press Esc
    Then it stays, and focus returns where it was


Feature: Relaunch with Request Tabs
  Board 05

  Background:
    Given a fresh copy of the fixture Data Folder
    And Raccoon is quit and the fixture Session is copied: cp manual-tests/collections.session.json "$S/session.json"
    And Raccoon is launched with the Data Folder

  Scenario: Each Tab is checked against its file
    Then the strip shows, left to right:
      | badge | name              | marks                                |
      | GET   | List charges      | Dirty dot                            |
      | POST  | Create charge     | none                                 |
      | PATCH | Update charge     | warning glyph and Dirty dot          |
      | GET   | /anything/gone    | italic, accent dot (a Draft)         |
    And Create charge is selected, reading POST "https://httpbin.org/anything/charges" with "Headers 1", the file's, silently
    When I select Update charge
    Then the banner reads "Changed on Disk. Update charge.json was changed outside Raccoon. Your edits are kept until you choose."
    And its URL is ".../charges/1" with my X-Mine header
    When I select List charges
    Then it shows my X-Mine header and no banner
