import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Environments sheet over a window loaded from a temp Data Folder.
@MainActor
struct EnvironmentsSheetTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    let secrets = FlakySecretStore()
    let token = VariableName("token")!
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    func makeWindow() -> WindowModel {
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: secrets, instants: FixedInstantSource(.now),
            makeTab: { [secrets] in
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: secrets, files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    func put(_ text: String, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func put(_ entries: [VariableEntry], at path: String) throws {
        try put(String(decoding: EnvironmentFile.encode(entries), as: UTF8.self), at: path)
    }

    func entry(_ name: String, _ value: String, enabled: Bool = true) -> VariableEntry {
        VariableEntry(name: VariableName(name)!, isEnabled: enabled, value: .plain(value))
    }

    func disk(_ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }

    /// 680 × 430, laid out, over a window loaded after the files were put.
    func sheet(_ window: WindowModel) -> EnvironmentsSheet {
        let sheet = EnvironmentsSheet(window: window, theme: theme)
        sheet.view.frame = NSRect(x: 0, y: 0, width: 680, height: 430)
        sheet.view.layoutSubtreeIfNeeded()
        return sheet
    }

    func field(_ sheet: EnvironmentsSheet, _ column: String, _ row: Int) throws -> NSTextField {
        try #require((sheet.table.view(atColumn: sheet.table.column(withIdentifier: .init(column)), row: row, makeIfNecessary: true) as? NSTableCellView)?.textField)
    }

    @Test func `a cell's text sits in the middle of its row, and the name field is taller than its text`() throws {
        let sheet = sheet(try staging())
        try select("Staging", in: sheet)
        // The border grows to Staging's rows, so the whole sheet is laid out again.
        sheet.view.layoutSubtreeIfNeeded()

        for (column, row) in [("name", 0), ("value", 0), ("value", 1), ("name", 3)] {
            let field = try field(sheet, column, row)
            let middle = try #require(field.superview).bounds.midY
            #expect(abs(field.frame.midY - middle) <= 0.5, "\(column) \(row)")
            #expect(field.frame.height < sheet.table.rowHeight)
        }
        let value = try field(sheet, "value", 0)
        let cell = try #require(value.superview as? EditableCellView)
        #expect(cell.frame.size == sheet.table.frameOfCell(atColumn: 2, row: 0).size)
        #expect(value.focusRingType == .none)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 430), styleMask: [], backing: .buffered, defer: false)
        window.contentView = sheet.view
        window.makeFirstResponder(value)
        #expect(cell.isEditing && cell.layer?.borderWidth == 2)
        window.makeFirstResponder(nil)
        #expect(!cell.isEditing)

        let name = sheet.nameField
        #expect(name.frame.height == 24)
        let text = try #require(name.cell).drawingRect(forBounds: name.bounds)
        #expect(abs(text.midY - name.bounds.midY) <= 0.5)
        #expect(text.height < name.bounds.height)
    }

    /// What typing `text` into a cell and leaving it does.
    func type(_ text: String, _ column: String, _ row: Int, in sheet: EnvironmentsSheet) throws {
        let cell = try field(sheet, column, row)
        cell.stringValue = text
        sheet.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: cell))
    }

    func select(_ name: String?, in sheet: EnvironmentsSheet) throws {
        let row = try #require(sheet.sourceTitles.firstIndex(of: name ?? "Globals"))
        sheet.sourceTable.selectRowIndexes([row], byExtendingSelection: false)
    }

    func staging() throws -> WindowModel {
        try put([entry("base_url", "https://api.example.com"), VariableEntry(name: token, value: .secret), entry("debug", "true", enabled: false)],
                at: "environments/Staging.json")
        try put([], at: "environments/Dev.json")
        return makeWindow()
    }

    // MARK: The list

    @Test func `Globals only, no Environments: the list shows Globals and +, and − is off`() {
        let sheet = sheet(makeWindow())

        #expect(sheet.sourceTitles == ["Globals", "Environments"])
        #expect(sheet.selectedName == nil)
        #expect(sheet.addButton.isEnabled)
        #expect(!sheet.removeButton.isEnabled)
        #expect(!sheet.nameField.isEditable && sheet.nameField.stringValue == "Globals")
        #expect(sheet.table.numberOfRows == 1)
    }

    @Test func `it opens on the Active Environment, else Globals, and checks the active one`() throws {
        let window = try staging()
        #expect(sheet(window).selectedName == nil)

        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        #expect(sheet.sourceTitles == ["Globals", "Environments", "Dev", "Staging"])
        #expect(sheet.selectedName == "Staging")
        #expect(sheet.sourceTable.selectedRow == 3)
        #expect(sheet.activeRow == 3)
        #expect(sheet.nameField.isEditable && sheet.nameField.stringValue == "Staging")
        #expect(sheet.removeButton.isEnabled)
        #expect(sheet.hintLabel.stringValue == "Staging overrides Globals while it is the Active Environment. Secret values are kept in the Keychain; only their names are written to the Data Folder.")
    }

    @Test func `+ and − are the same size, and − is drawn as wide as +`() throws {
        let sheet = sheet(try staging())
        sheet.view.layoutSubtreeIfNeeded()

        // Layout sizes the alignment rect; a symbol's frame adds its own insets around it.
        func size(_ button: NSButton) -> NSSize { button.alignmentRect(forFrame: button.frame).size }
        #expect(size(sheet.addButton) == NSSize(width: 24, height: 22))
        #expect(size(sheet.removeButton) == size(sheet.addButton))
        for button in [sheet.addButton, sheet.removeButton] {
            #expect(button.imageScaling == .scaleNone)
            #expect(try #require(button.image).size.width >= 13)
        }
        #expect(sheet.removeButton.image?.size.width == sheet.addButton.image?.size.width)
    }

    @Test func `+ and − sit in a footer under the list, as in System Settings: a hairline above, a divider between`() throws {
        let sheet = sheet(try staging())
        sheet.view.layoutSubtreeIfNeeded()
        let footer = sheet.listFooter
        let list = try #require(sheet.sourceTable.enclosingScrollView)

        #expect(footer.frame.height == 28)
        #expect(footer.frame.width == list.frame.width)
        #expect(abs(list.frame.minY - footer.frame.maxY) <= 1)
        // Layout sizes alignment rects; a box or a symbol adds its own insets around one.
        func laid(_ view: NSView) -> NSRect { view.alignmentRect(forFrame: view.frame) }
        #expect(laid(sheet.footerRule).width == footer.frame.width && laid(sheet.footerRule).height == 1)
        let add = sheet.addButton.convert(sheet.addButton.bounds, to: footer)
        let divider = laid(sheet.footerDivider)
        let remove = sheet.removeButton.convert(sheet.removeButton.bounds, to: footer)
        #expect(add.maxX <= divider.minX && divider.maxX <= remove.minX)
        #expect(divider.width == 1 && divider.height < footer.frame.height)
        for item in [add, divider, remove] { #expect(abs(item.midY - footer.bounds.midY) <= 1) }
    }

    // MARK: The table

    @Test func `the table is [enabled] Name Value Secret in SF Mono 12, with a Disabled Row dimmed and a trailing empty row`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        #expect(sheet.table.tableColumns.map(\.title) == ["", "Name", "Value", "Secret"])
        #expect(sheet.table.numberOfRows == 4)
        #expect(try field(sheet, "name", 0).stringValue == "base_url")
        #expect(try field(sheet, "name", 0).font == .monospacedSystemFont(ofSize: 12, weight: .regular))
        #expect(try field(sheet, "value", 0).stringValue == "https://api.example.com")
        let debug = try field(sheet, "name", 2)
        #expect(debug.textColor == theme.color(.textDisabled))
        #expect(try field(sheet, "name", 0).textColor == theme.color(.text))
        #expect((try #require(sheet.table.view(atColumn: 0, row: 2, makeIfNecessary: true) as? NSButton)).state == .off)
        #expect(try field(sheet, "name", 3).stringValue == "" && field(sheet, "name", 3).placeholderAttributedString?.string == "Name")
        #expect(try field(sheet, "value", 3).placeholderAttributedString?.string == "Value")
    }

    @Test func `the table is drawn as Headers is: recessed header, 28 pt rows, a rounded border hugging the rows`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)
        sheet.view.layoutSubtreeIfNeeded()

        #expect(sheet.table.rowHeight == 28)
        #expect(sheet.table.headerView?.frame.height == 24)
        #expect(sheet.table.tableColumns.allSatisfy { $0.headerCell is KeyHeaderCell })
        #expect(sheet.table.backgroundColor == theme.color(.background))
        #expect(sheet.table.gridColor == theme.color(.border))
        #expect(sheet.table.rowView(atRow: 0, makeIfNecessary: true) is KeyRowView)
        let box = try #require(sheet.tableBox.layer)
        #expect(box.cornerRadius == 6 && box.borderWidth == 1 && box.borderColor == theme.color(.border).cgColor)
        // Three Variables and the trailing row under the header.
        #expect(abs(sheet.tableBox.frame.height - (24 + 4 * 28)) < 0.5)
        let placeholder = try #require(try field(sheet, "name", 3).placeholderAttributedString)
        #expect((placeholder.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.alphaComponent ?? 1 < 1)
    }

    @Test func `a secret row is a pressed closed lock over a secure field of 8 bullets whatever the value; a plain row an open lock`() throws {
        let window = try staging()
        try secrets.set("sk_live_a_much_longer_value_than_eight", environment: "Staging", name: token)
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        let secret = try field(sheet, "value", 1)
        #expect(secret is NSSecureTextField && secret.isEditable)
        #expect(secret.stringValue == "" && sheet.valueShown(row: 1) == "••••••••")
        let plain = try field(sheet, "value", 0)
        #expect(!(plain is NSSecureTextField) && plain.isEditable)
        #expect(sheet.lockName(row: 1) == "Secret" && sheet.lockName(row: 0) == "Plain" && sheet.lockName(row: 3) == nil)
        #expect(sheet.lock(row: 1)?.state == .on && sheet.lock(row: 0)?.state == .off)
    }

    @Test func `a secret the Keychain cannot give reads Not in the Keychain, and so does one with no value yet`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)
        #expect(try sheet.valueShown(row: 1) == "Not in the Keychain" && field(sheet, "value", 1).stringValue == "")
        #expect(try field(sheet, "value", 1).isEditable)

        try secrets.set("sk", environment: "Staging", name: token)
        secrets.refuse(.get, with: .unavailable(-25308))
        #expect(self.sheet(window).valueShown(row: 1) == "Not in the Keychain")
    }

    // MARK: The lock

    func plainToken() throws -> WindowModel {
        try put([entry("host", "a"), entry("token", "sk_live")], at: "environments/Staging.json")
        let window = makeWindow()
        window.pickActiveEnvironment("Staging")
        return window
    }

    @Test func `clicking an open lock marks the row: the Keychain has the value, the file has none, the row is secret`() throws {
        let sheet = sheet(try plainToken())

        sheet.toggleSecret(try #require(sheet.lock(row: 1)))

        #expect(try secrets.get(environment: "Staging", name: token) == "sk_live")
        #expect(try disk("environments/Staging.json") == String(decoding: EnvironmentFile.encode([entry("host", "a"), VariableEntry(name: token, value: .secret)]), as: UTF8.self))
        #expect(sheet.lockName(row: 1) == "Secret" && sheet.lock(row: 1)?.state == .on)
        #expect(try field(sheet, "value", 1) is NSSecureTextField)
        #expect(sheet.valueShown(row: 1) == "••••••••" && sheet.rowError.isHidden)
    }

    @Test func `clicking a closed lock unmarks the row: the file has the value, the Keychain item is gone`() throws {
        let window = try staging()
        try secrets.set("sk_live", environment: "Staging", name: token)
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        sheet.toggleSecret(try #require(sheet.lock(row: 1)))

        #expect(try disk("environments/Staging.json").contains("\"value\" : \"sk_live\""))
        #expect(try secrets.get(environment: "Staging", name: token) == nil)
        #expect(sheet.lockName(row: 1) == "Plain" && sheet.lock(row: 1)?.state == .off)
        let value = try field(sheet, "value", 1)
        #expect(!(value is NSSecureTextField) && value.stringValue == "sk_live")
    }

    @Test func `marking a row with no value yet puts a secret in the file and reads Not in the Keychain`() throws {
        try put([entry("token", "")], at: "environments/Staging.json")
        let window = makeWindow()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        sheet.toggleSecret(try #require(sheet.lock(row: 0)))

        #expect(sheet.lockName(row: 0) == "Secret" && sheet.valueShown(row: 0) == "Not in the Keychain")
        #expect(try secrets.get(environment: "Staging", name: token) == nil)
    }

    @Test func `a Keychain write that fails leaves the row and the file as they were, with the OSStatus line under the row`() throws {
        let sheet = sheet(try plainToken())
        let before = try disk("environments/Staging.json")
        secrets.refuse(.set, with: .unavailable(-25308))

        sheet.toggleSecret(try #require(sheet.lock(row: 1)))

        let line = sheet.rowError.stringValue
        #expect(line.hasPrefix("Not saved. The Keychain refused the write (OSStatus −25308") && line.hasSuffix(")."))
        #expect(!sheet.rowError.isHidden && sheet.rowError.textColor == .systemRed && sheet.rowError.font?.pointSize == 11)
        #expect(try disk("environments/Staging.json") == before)
        #expect(sheet.lockName(row: 1) == "Plain" && sheet.lock(row: 1)?.state == .off)
        #expect(try field(sheet, "value", 1).stringValue == "sk_live")
    }

    @Test func `with no readable raccoon.json the line says so`() throws {
        let sheet = sheet(try plainToken())
        secrets.refuse(.set, with: .raccoonJSONUnreadable)

        sheet.toggleSecret(try #require(sheet.lock(row: 1)))

        #expect(sheet.rowError.stringValue == "Not saved. raccoon.json can't be read.")
    }

    @Test func `typing in a secret's secure field stores the value, leaves the file alone, and shows bullets again`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)
        let before = try disk("environments/Staging.json")

        try type("sk_new", "value", 1, in: sheet)

        #expect(try secrets.get(environment: "Staging", name: token) == "sk_new")
        #expect(try disk("environments/Staging.json") == before)
        #expect(try field(sheet, "value", 1).stringValue == "" && sheet.valueShown(row: 1) == "••••••••")
        #expect(window.tabs[0].scope(.read).values[token] == "sk_new")
    }

    @Test func `a secret value the Keychain refuses shows the line and is not kept`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)
        secrets.refuse(.set, with: .unavailable(-25308))

        try type("sk_new", "value", 1, in: sheet)

        #expect(sheet.rowError.stringValue.hasPrefix("Not saved. The Keychain refused the write (OSStatus −25308"))
        #expect(try field(sheet, "value", 1).stringValue == "" && sheet.valueShown(row: 1) == "Not in the Keychain")
    }

    @Test func `leaving a value cell writes the file through the window`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)
        let scans = window.scanCount

        try type("https://api.staging.example.com", "value", 0, in: sheet)

        #expect(window.entries(of: "Staging")?.first == entry("base_url", "https://api.staging.example.com"))
        #expect(try disk("environments/Staging.json").contains("https://api.staging.example.com"))
        #expect(window.scanCount == scans)
    }

    @Test func `the enabled checkbox writes at once and dims the row`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)
        let box = try #require(sheet.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSButton)

        box.state = .off
        sheet.toggleEnabled(box)

        #expect(window.entries(of: "Staging")?.first?.isEnabled == false)
        #expect(try field(sheet, "name", 0).textColor == theme.color(.textDisabled))
    }

    @Test func `typing a name on the trailing row adds a Variable and a new trailing row`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        try type("tenant", "name", 3, in: sheet)

        #expect(window.entries(of: "Staging")?.last == entry("tenant", ""))
        #expect(sheet.table.numberOfRows == 5)
        try type("t_staging_01", "value", 3, in: sheet)
        #expect(window.entries(of: "Staging")?.last == entry("tenant", "t_staging_01"))
        #expect(try field(sheet, "name", 4).stringValue == "")
        #expect(try #require(sheet.table.view(atColumn: 0, row: 3, makeIfNecessary: true) as? NSButton).isEnabled)
    }

    @Test func `a value typed on the trailing row, with no name, is dropped`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        try type("orphan", "value", 3, in: sheet)

        #expect(window.entries(of: "Staging")?.count == 3)
        #expect(try field(sheet, "value", 3).stringValue == "")
    }

    @Test(arguments: [
        ("a b", "Names use letters, digits, _, - and . only."),
        ("", "Names use letters, digits, _, - and . only."),
        ("debug", "debug is already in Staging."),
    ])
    func `a refused name keeps the old one, says why under the row, and writes nothing`(text: String, line: String) throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)
        let before = try disk("environments/Staging.json")

        try type(text, "name", 0, in: sheet)

        #expect(try field(sheet, "name", 0).stringValue == "base_url")
        #expect(sheet.rowError.stringValue == line && !sheet.rowError.isHidden)
        #expect(sheet.rowError.textColor == .systemRed && sheet.rowError.font == .systemFont(ofSize: 11))
        #expect(try disk("environments/Staging.json") == before)
    }

    @Test func `a duplicate in Globals reads … is already in Globals, and the next edit clears the line`() throws {
        try put([entry("host", "a"), entry("path", "/")], at: "globals.json")
        let sheet = sheet(makeWindow())

        try type("path", "name", 0, in: sheet)
        #expect(sheet.rowError.stringValue == "path is already in Globals.")

        try type("other", "name", 0, in: sheet)
        #expect(sheet.rowError.isHidden)
        #expect(sheet.table.numberOfRows == 3)
    }

    @Test func `deleting a row rewrites the file without it and deletes a secret's Keychain item`() throws {
        let window = try staging()
        try secrets.set("sk", environment: "Staging", name: token)
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        sheet.deleteVariable(at: 1)

        #expect(window.entries(of: "Staging")?.map(\.name.rawValue) == ["base_url", "debug"])
        #expect(sheet.table.numberOfRows == 3)
        #expect(try secrets.get(environment: "Staging", name: token) == nil)
    }

    @Test func `200 Variables scroll`() throws {
        try put((1...200).map { entry("var_\($0)", "value \($0)") }, at: "globals.json")
        let sheet = sheet(makeWindow())

        #expect(sheet.table.numberOfRows == 201)
        let scroll = try #require(sheet.table.enclosingScrollView)
        #expect(scroll.hasVerticalScroller)
        #expect(sheet.table.frame.height > scroll.frame.height)
        sheet.table.scrollRowToVisible(199)
        #expect(scroll.contentView.bounds.origin.y > 0)
    }

    // MARK: + and −

    @Test func `+ writes New Environment, selects it and focuses its name field`() throws {
        let window = makeWindow()
        let sheet = sheet(window)
        let host = NSWindow(contentViewController: sheet)

        sheet.addButton.performClick(nil)

        #expect(window.environments.map(\.name) == ["New Environment"])
        #expect(sheet.selectedName == "New Environment")
        #expect(sheet.nameField.stringValue == "New Environment")
        #expect((host.firstResponder as? NSTextView)?.delegate === sheet.nameField)
    }

    @Test func `− trashes the selected Environment, keeps its Keychain items, and falls back to Globals`() throws {
        let window = try staging()
        try secrets.set("sk", environment: "Staging", name: token)
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        sheet.removeButton.performClick(nil)

        #expect(window.environments.map(\.name) == ["Dev"])
        #expect(window.activeEnvironment == nil)
        #expect(sheet.selectedName == nil)
        #expect(sheet.sourceTitles == ["Globals", "Environments", "Dev"])
        #expect(try secrets.get(environment: "Staging", name: token) == "sk")
    }

    // MARK: Rename

    @Test func `renaming through the name field moves the file and keeps the secrets resolvable`() throws {
        let window = try staging()
        try secrets.set("sk", environment: "Staging", name: token)
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        sheet.nameField.stringValue = "Pre-prod"
        sheet.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: sheet.nameField))

        #expect(sheet.sourceTitles == ["Globals", "Environments", "Dev", "Pre-prod"])
        #expect(sheet.selectedName == "Pre-prod")
        #expect(window.activeEnvironment == "Pre-prod")
        #expect(window.tabs[0].scope(.read).values[token] == "sk")
        #expect(sheet.renameError.isHidden)
    }

    @Test func `a name another Environment has is refused: it reverts and an 11 pt red line says so`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let sheet = sheet(window)

        sheet.nameField.stringValue = "dev"
        sheet.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: sheet.nameField))

        #expect(sheet.nameField.stringValue == "Staging")
        #expect(sheet.renameError.stringValue == "An Environment named “Dev” already exists.")
        #expect(sheet.renameError.textColor == .systemRed && sheet.renameError.font == .systemFont(ofSize: 11))
        #expect(window.environments.map(\.name) == ["Dev", "Staging"])
    }

    // MARK: A file that does not decode

    @Test func `a broken Environment is a read-only row with a warning; selecting it shows why and no table`() throws {
        try put("{ not json", at: "environments/Broken.json")
        try put([], at: "environments/Dev.json")
        let window = makeWindow()
        let sheet = sheet(window)

        #expect(sheet.sourceTitles == ["Globals", "Environments", "Broken", "Dev"])
        #expect(sheet.brokenRows == [2])

        try select("Broken", in: sheet)
        #expect(!sheet.problemLabel.isHidden)
        #expect(sheet.problemLabel.stringValue == "Not valid JSON at line 1. Raccoon won't change this file.")
        #expect(sheet.table.enclosingScrollView?.isHidden == true)
        #expect(!sheet.nameField.isEditable && sheet.nameField.stringValue == "Broken")
        #expect(sheet.removeButton.isEnabled)

        sheet.removeButton.performClick(nil)
        #expect(window.brokenEnvironments.isEmpty)
        #expect(sheet.sourceTitles == ["Globals", "Environments", "Dev"])
    }

    @Test func `a broken globals.json shows the same, and is never written over`() throws {
        try put("{ nope", at: "globals.json")
        let sheet = sheet(makeWindow())

        #expect(sheet.problemLabel.stringValue == "Not valid JSON at line 1. Raccoon won't change this file.")
        #expect(sheet.table.enclosingScrollView?.isHidden == true)
        #expect(try disk("globals.json") == "{ nope")
    }

    // MARK: Done, focus, ways in

    @Test func `Done is the default button`() {
        let sheet = sheet(makeWindow())

        #expect(sheet.doneButton.title == "Done" && sheet.doneButton.keyEquivalent == "\r")
    }

    @Test func `focus goes back to the field that had it, field editor and all`() throws {
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(string: "https://x")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 22)
        host.contentView?.addSubview(field)
        host.makeFirstResponder(field)

        let restore = EnvironmentsSheet.rememberFocus(in: host)
        host.makeFirstResponder(nil)
        #expect(host.firstResponder === host)
        restore()

        #expect((host.firstResponder as? NSTextView)?.delegate === field)
    }

    @Test func `View ▸ Edit Environments… is ⌥⌃E`() throws {
        let view = try #require(MainMenu.make(theme: .standalone()).item(withTitle: "View")?.submenu)
        let item = try #require(view.item(withTitle: "Edit Environments…"))

        #expect(item.keyEquivalent == "e" && item.keyEquivalentModifierMask == [.control, .option])
        #expect(item.action == #selector(AppDelegate.editEnvironments(_:)))
    }

    @Test func `the picker's Edit Environments… is on, opens the sheet, and leaves the choice showing`() throws {
        let window = try staging()
        window.pickActiveEnvironment("Staging")
        let picker = EnvironmentPicker()
        picker.bind(window)
        var opened = 0
        picker.onEdit = { opened += 1 }

        let edit = try #require(picker.item(withTitle: "Edit Environments…"))
        picker.select(edit)
        picker.edit(edit)

        #expect(edit.isEnabled)
        #expect(opened == 1)
        #expect(picker.titleOfSelectedItem == "Staging")
    }
}
