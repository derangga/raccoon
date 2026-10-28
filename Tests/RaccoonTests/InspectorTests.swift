import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The inspector over a window loaded from a temp Data Folder: its header and the Variables pane
/// (boards 04, 11, 14).
@MainActor
struct InspectorTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    var root: URL { temp.appending(path: "Raccoon") }
    let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." + String(repeating: "eyJzdWIiOiJvcHMtYm90In0", count: 20)
    /// The window's Keychain, which its Tabs share: counts reads, and can refuse a write.
    let secrets = FlakySecretStore()
    let clipboard = RecordingClipboardWriter()

    func entry(_ name: String, _ value: VariableEntry.Value) -> VariableEntry {
        VariableEntry(name: VariableName(name)!, value: value)
    }

    func makeWindow(environments: [String: [VariableEntry]], globals: [VariableEntry]) throws -> WindowModel {
        for (name, entries) in environments {
            let url = root.appending(path: "environments/\(name).json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try EnvironmentFile.encode(entries).write(to: url)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try EnvironmentFile.encode(globals).write(to: root.appending(path: "globals.json"))
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: secrets, instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: secrets, files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: clipboard)
            }
        )
        window.loadDataFolder()
        return window
    }

    /// Board 04's window: Staging active, a Tab using two names nothing defines.
    func board04(theme: ThemeEnvironment? = nil) throws -> (WindowModel, InspectorViewController) {
        let window = try makeWindow(
            environments: ["Staging": [entry("host", .plain("https://api.staging")), entry("access_token", .plain(jwt)), entry("api_key", .secret)]],
            globals: [entry("host", .plain("http://localhost:4000")), entry("user_agent", .plain("Raccoon/1.0"))]
        )
        window.pickActiveEnvironment("Staging")
        let tab = try #require(window.selectedTab)
        tab.tab.definition.url = "{{host}}/v1/charges/{{charge_id}}"
        tab.tab.definition.headers = [Row(name: "Authorization", value: "Bearer {{access_token}}"), Row(name: "X-Tenant", value: "{{tenant_id}}")]
        let inspector = InspectorViewController(window: window, theme: theme ?? self.theme, memory: InspectorMemory())
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        inspector.view.layoutSubtreeIfNeeded()
        return (window, inspector)
    }

    @Test func `the header names the pane; Variables is selected and Curl can be picked`() throws {
        let (_, inspector) = try board04()
        #expect(inspector.paneTitle.stringValue == "Variables")
        #expect(inspector.paneSwitch.selectedSegment == 0)
        #expect(inspector.paneSwitch.label(forSegment: 0) == "Variables" && inspector.paneSwitch.label(forSegment: 1) == "Curl")
        #expect(inspector.paneSwitch.isEnabled(forSegment: 1))
    }

    @Test func `each segment's tooltip and accessibility label name its pane`() throws {
        let (_, inspector) = try board04()
        let control = inspector.paneSwitch
        let tips = [15, 46].map { control.view(control, stringForToolTip: 0, point: NSPoint(x: $0, y: 12), userData: nil) }
        #expect(tips == ["Variables", "Curl"])
        let segments = try #require(control.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(segments.map { $0.accessibilityLabel() } == ["Variables", "Curl"])
        #expect(segments.map { $0.accessibilityRole() } == [.radioButton, .radioButton])
        #expect(segments.map { $0.accessibilityValue() as? Bool } == [true, false])
        #expect(segments.map { $0.isAccessibilityEnabled() } == [true, true])
    }

    @Test func `the switch swaps the pane under the header and the title follows; a reveal comes back to Variables`() throws {
        let (_, inspector) = try board04()
        let footer = try #require(inspector.editButton.superview)

        inspector.showPane(1)
        #expect(inspector.paneTitle.stringValue == "Curl" && inspector.paneSwitch.selectedSegment == 1)
        #expect(inspector.variables.isHidden && footer.isHidden && !inspector.curl.isHidden)

        inspector.reveal(VariableName("host")!)
        #expect(inspector.paneTitle.stringValue == "Variables" && inspector.paneSwitch.selectedSegment == 0)
        #expect(!inspector.variables.isHidden && !footer.isHidden && inspector.curl.isHidden)
    }

    @Test func `board 04: missing names first, then Staging with the names the Tab uses, then Globals struck where overridden`() throws {
        let (_, inspector) = try board04()
        let pane = inspector.variables

        #expect(pane.titles == ["Not defined · used by this Tab", "Staging · Active Environment", "Globals"])
        #expect(pane.rows.map(\.name) == ["charge_id", "tenant_id", "host", "access_token", "api_key", "host", "user_agent"])
        #expect(pane.rows.map(\.value) == ["URL", "Headers", "https://api.staging", jwt, "Secret", "http://localhost:4000", "Raccoon/1.0"])
        #expect(pane.rows.map(\.isStruck) == [false, false, false, false, false, true, false])
        #expect(pane.note == "A struck-out Global is overridden by Staging. Disabled Variables are not listed.")
        #expect(pane.rows.allSatisfy { !$0.isSelected && $0.error == nil })
    }

    @Test func `revealing a name highlights the row that resolves, and the table stays a table`() throws {
        let (_, inspector) = try board04()

        inspector.reveal(VariableName("access_token")!)
        #expect(inspector.variables.rows.filter(\.isSelected).map(\.name) == ["access_token"])

        inspector.reveal(VariableName("host")!)
        let host = inspector.variables.rows.filter(\.isSelected)
        #expect(host.map(\.name) == ["host"] && host.map(\.isStruck) == [false])
    }

    /// The inspector alone in a window. Alone, its first value is the window's first key view and
    /// takes focus as the window opens (in the app the sidebar and URL bar come first), so that
    /// focus is let go before the test clicks.
    func shown(_ inspector: InspectorViewController) async -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 280, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = inspector
        window.setContentSize(NSSize(width: 280, height: 600))
        // Ordered front, never made key: a key window makes the test process an app that macOS
        // may quit, mid-run, once its windows are gone.
        window.orderFront(nil)
        window.layoutIfNeeded()
        window.makeFirstResponder(nil)
        for _ in 0..<100 where inspector.variables.editingRow != nil { await Task.yield() }
        return window
    }

    /// A click at `x` (in the row's own width) on row `row`, routed as a key window routes it: to
    /// the view its hit test finds. (A test window is never key, so `sendEvent` would only
    /// activate it.) A value field is focused as its own mouse-down focuses it; its mouse-down
    /// would run AppKit's tracking loop, which stops the test runner's main run loop.
    func click(row: Int, atX x: (NSRect) -> CGFloat, in inspector: InspectorViewController, window: NSWindow) throws -> NSView {
        let frame = inspector.variables.rowFrames[row]
        let point = inspector.variables.documentView.convert(NSPoint(x: x(frame), y: frame.midY), to: nil)
        let hit = try #require(window.contentView?.hitTest(point))
        if let field = hit as? NSTextField, field.isEditable {
            window.makeFirstResponder(field)
        } else {
            hit.mouseDown(with: try #require(NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )))
        }
        return hit
    }

    @Test func `with the pane open from the link, a click on any row selects it, and a click on its value edits it`() async throws {
        let (_, inspector) = try board04()
        let window = await shown(inspector)
        defer { window.orderOut(nil) }
        inspector.reveal(VariableName("access_token")!)
        let names = inspector.variables.rows.map(\.name)

        let onName = try click(row: try #require(names.firstIndex(of: "user_agent")), atX: { $0.minX + 20 }, in: inspector, window: window)
        #expect(!(onName is NSTextField))
        #expect(inspector.variables.rows.filter(\.isSelected).map(\.name) == ["user_agent"])
        #expect(inspector.variables.editingRow == nil)

        let host = try #require(names.firstIndex(of: "host"))
        let onValue = try click(row: host, atX: { $0.maxX - 30 }, in: inspector, window: window)
        #expect((onValue as? NSTextField)?.isEditable == true)
        #expect(inspector.variables.rows.filter(\.isSelected).map(\.name) == ["host"])
        #expect(inspector.variables.editingRow == host)
        window.makeFirstResponder(nil)
    }

    /// The row of `name` in `group`'s order: the pane lists Not defined, then Staging, then Globals.
    func row(_ name: String, in inspector: InspectorViewController, struck: Bool = false) throws -> Int {
        try #require(inspector.variables.rows.firstIndex { $0.name == name && $0.isStruck == struck })
    }

    @Test func `a value edits in place and is written to its file; the pane follows`() async throws {
        let (window, inspector) = try board04()

        inspector.variables.edit(row: try row("user_agent", in: inspector), to: "Raccoon/2.0")
        inspector.variables.edit(row: try row("host", in: inspector), to: "https://api.prod")

        #expect(window.globals.entries.map(\.value) == [.plain("http://localhost:4000"), .plain("Raccoon/2.0")])
        let staging = try #require(window.environments.first { $0.name == "Staging" })
        #expect(staging.entries.first?.value == .plain("https://api.prod"))
        let file = try EnvironmentFile.decode(Data(contentsOf: root.appending(path: "environments/Staging.json")), path: "environments/Staging.json")
        #expect(file.entries.first?.value == .plain("https://api.prod"))
        for _ in 0..<100 where !inspector.variables.rows.contains(where: { $0.value == "https://api.prod" }) { await Task.yield() }
        #expect(inspector.variables.rows.contains { $0.name == "host" && $0.value == "https://api.prod" })
    }

    @Test func `a secret's new value goes to the Keychain only, and an empty one writes nothing`() throws {
        let (window, inspector) = try board04()
        let before = try Data(contentsOf: root.appending(path: "environments/Staging.json"))

        inspector.variables.edit(row: try row("api_key", in: inspector), to: "")
        #expect(try secrets.inner.get(environment: "Staging", name: VariableName("api_key")!) == nil)
        inspector.variables.edit(row: try row("api_key", in: inspector), to: "sk_live_1")

        #expect(try secrets.inner.get(environment: "Staging", name: VariableName("api_key")!) == "sk_live_1")
        #expect(try Data(contentsOf: root.appending(path: "environments/Staging.json")) == before)
        #expect(window.environments.first?.entries.last?.value == .secret)
        // Rendering never read the Keychain.
        #expect(secrets.gets == 0)
    }

    @Test func `a value for a Not defined name defines it in the Active Environment, or in Globals without one`() async throws {
        let (window, inspector) = try board04()

        inspector.variables.edit(row: try row("charge_id", in: inspector), to: "ch_3PqL8x2e")

        #expect(window.environments.first?.entries.last == VariableEntry(name: VariableName("charge_id")!, value: .plain("ch_3PqL8x2e")))
        for _ in 0..<100 where inspector.variables.rows.first?.name == "charge_id" { await Task.yield() }
        #expect(inspector.variables.rows.map(\.name).prefix(1) == ["tenant_id"])
        #expect(inspector.variables.rows.contains { $0.name == "charge_id" && $0.value == "ch_3PqL8x2e" })

        window.pickActiveEnvironment(nil)
        for _ in 0..<100 where inspector.variables.titles[1] != "No Environment · pick one in the toolbar" { await Task.yield() }
        inspector.variables.edit(row: try row("tenant_id", in: inspector), to: "acme")
        #expect(window.globals.entries.last == VariableEntry(name: VariableName("tenant_id")!, value: .plain("acme")))
    }

    @Test func `a refused Keychain write says so under the row`() throws {
        let (_, inspector) = try board04()
        secrets.refuse(.set, with: .unavailable(-25308))

        inspector.variables.edit(row: try row("api_key", in: inspector), to: "sk_live_1")

        let error = try #require(inspector.variables.rows.first { $0.name == "api_key" }?.error)
        #expect(error.hasPrefix("Not saved. The Keychain refused the write (OSStatus −25308"))
    }

    @Test func `a file that cannot be written says so under the row, and the value goes back`() throws {
        let (window, inspector) = try board04()
        let folder = root.appending(path: "environments")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        inspector.variables.edit(row: try row("host", in: inspector), to: "https://api.prod")

        let host = try #require(inspector.variables.rows.first { $0.name == "host" && !$0.isStruck })
        #expect(host.error?.hasPrefix("Not saved. ") == true)
        #expect(host.value == "https://api.staging")
        #expect(window.environments.first?.entries.first?.value == .plain("https://api.staging"))
    }

    @Test func `No Environment points at the toolbar, and no Globals says so`() throws {
        let window = try makeWindow(environments: [:], globals: [])
        let inspector = InspectorViewController(window: window, theme: theme, memory: InspectorMemory())
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        #expect(inspector.variables.titles == ["No Environment · pick one in the toolbar", "Globals"])
        #expect(inspector.variables.emptyGlobals == "No Globals.")
        #expect(inspector.variables.rows.isEmpty && inspector.variables.note == nil)
    }

    @Test func `it follows the Active Environment and the Tab as they change`() async throws {
        let (window, inspector) = try board04()
        inspector.reveal(VariableName("host")!)

        let noEnvironment = ["Not defined · used by this Tab", "No Environment · pick one in the toolbar", "Globals"]
        window.pickActiveEnvironment(nil)
        for _ in 0..<100 where inspector.variables.titles != noEnvironment { await Task.yield() }
        #expect(inspector.variables.titles == noEnvironment)
        // The Global now resolves, so it is the one selected.
        #expect(inspector.variables.rows.filter(\.isSelected).map(\.value) == ["http://localhost:4000"])

        try #require(window.selectedTab).tab.definition.url = "{{user_agent}}"
        for _ in 0..<100 where inspector.variables.rows.contains(where: { $0.name == "charge_id" }) { await Task.yield() }
        #expect(!inspector.variables.rows.contains { $0.name == "charge_id" })
    }

    @Test func `Edit Environments… asks for the sheet`() throws {
        let (_, inspector) = try board04()
        var asked = 0
        inspector.onEditEnvironments = { asked += 1 }
        inspector.editButton.performClick(nil)
        #expect(asked == 1)
    }

    // MARK: Boards 04 and 11 in Latte and Mocha, rendering without the Keychain, worst case

    /// The pane's labels as drawn: names, "Secret", where an undefined name is used.
    func labels(_ text: String, in inspector: InspectorViewController) -> [NSTextField] {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return all(inspector.variables.documentView).compactMap { $0 as? NSTextField }.filter { !$0.isEditable && $0.stringValue == text }
    }

    /// The value cell of the row named `name`.
    func valueCell(_ name: String, in inspector: InspectorViewController) throws -> NSTextField {
        try #require(inspector.variables.documentView.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.accessibilityLabel() == name })
    }

    func color(_ field: NSTextField) -> NSColor? {
        field.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    }

    @Test(arguments: [false, true])
    func `board 04 in Latte and Mocha: Not defined red with a wavy underline, a secret locked, an overridden Global struck`(isDark: Bool) throws {
        let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: isDark)
        #expect(theme.flavor.name == (isDark ? "Mocha" : "Latte"))
        let (_, inspector) = try board04(theme: theme)

        #expect(inspector.variables.titles == ["Not defined · used by this Tab", "Staging · Active Environment", "Globals"])
        let chargeID = try #require(labels("charge_id", in: inspector).first)
        #expect(color(chargeID) == theme.color(.variableUndefined))
        #expect(chargeID.attributedStringValue.attribute(.wavyUnderline, at: 0, effectiveRange: nil) as? NSColor == theme.color(.variableUndefined))
        #expect(color(try #require(labels("URL", in: inspector).first)) == theme.color(.variableUndefined))

        #expect(color(try #require(labels("Secret", in: inspector).first)) == theme.color(.variableSecret))

        let struck = try #require(labels("host", in: inspector).first { $0.attributedStringValue.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil })
        #expect(color(struck) == theme.color(.textDisabled))
        #expect(struck.toolTip == "Overridden by Staging")
    }

    @Test func `board 11 in Mocha: No Environment points at the toolbar and Globals follow`() throws {
        let window = try makeWindow(environments: ["Staging": []], globals: [entry("host", .plain("http://localhost:4000")), entry("user_agent", .plain("Raccoon/1.0"))])
        let inspector = InspectorViewController(window: window, theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: true), memory: InspectorMemory())
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)

        #expect(inspector.variables.titles == ["No Environment · pick one in the toolbar", "Globals"])
        #expect(inspector.variables.rows.map(\.name) == ["host", "user_agent"])
        #expect(inspector.variables.rows.map(\.value) == ["http://localhost:4000", "Raccoon/1.0"])
        #expect(inspector.variables.emptyGlobals == nil && inspector.variables.note == nil)
    }

    @Test func `switching to Mocha recolours the pane in place`() async throws {
        let (_, inspector) = try board04()
        let mocha = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: true)
        #expect(mocha.color(.variableUndefined) != theme.color(.variableUndefined))

        theme.flavor = mocha.flavor
        func undefinedColor() -> NSColor? { labels("charge_id", in: inspector).first.flatMap(color) }
        for _ in 0..<100 where undefinedColor() != mocha.color(.variableUndefined) { await Task.yield() }
        #expect(undefinedColor() == mocha.color(.variableUndefined))
    }

    @Test func `the pane renders secrets without one Keychain read, however it changes`() async throws {
        let window = try makeWindow(
            environments: ["Staging": [entry("api_key", .secret), entry("host", .plain("https://api.staging"))], "Dev": [entry("api_key", .secret)]],
            globals: [entry("api_key", .secret), entry("token", .secret)]
        )
        window.pickActiveEnvironment("Staging")
        try #require(window.selectedTab).tab.definition.url = "{{host}}?key={{api_key}}"
        let inspector = InspectorViewController(window: window, theme: theme, memory: InspectorMemory())
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        inspector.view.layoutSubtreeIfNeeded()
        #expect(inspector.variables.rows.filter { $0.value == "Secret" }.count == 3)

        inspector.reveal(VariableName("api_key")!)
        window.pickActiveEnvironment("Dev")
        for _ in 0..<100 where inspector.variables.titles.contains("Staging · Active Environment") { await Task.yield() }
        window.pickActiveEnvironment(nil)
        for _ in 0..<100 where inspector.variables.titles.contains("Dev · Active Environment") { await Task.yield() }
        theme.flavor = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: true).flavor
        for _ in 0..<100 { await Task.yield() }

        #expect(inspector.variables.titles.contains("No Environment · pick one in the toolbar"))
        #expect(secrets.gets == 0)
    }

    @Test func `break-ui: 200 Variables scroll, and the link scrolls to the last`() throws {
        let entries = (0..<200).map { entry(String(format: "var_%03d", $0), .plain("value \($0)")) }
        let window = try makeWindow(environments: ["Load": entries], globals: [])
        window.pickActiveEnvironment("Load")
        let inspector = InspectorViewController(window: window, theme: theme, memory: InspectorMemory())
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        inspector.view.layoutSubtreeIfNeeded()
        let pane = inspector.variables

        #expect(pane.rows.count == 200)
        #expect(pane.emptyGlobals == "No Globals.")
        let visible = pane.documentView.visibleRect
        #expect(pane.documentView.frame.height > visible.height)
        #expect(visible.intersects(try #require(pane.rowFrames.first)))

        inspector.reveal(VariableName("var_199")!)
        let last = try #require(pane.rowFrames.last)
        // The link scrolls its selection fill into view: the whole row but its 1 pt rule.
        #expect(pane.documentView.visibleRect.intersection(last).height >= last.height - 1)
        #expect(!pane.documentView.visibleRect.intersects(try #require(pane.rowFrames.first)))
    }

    @Test func `break-ui: a long value end-truncates in its cell, with the full value in its tooltip`() throws {
        let long = "https://api.staging.payments.example.com/" + String(repeating: "segment/", count: 60)
        let window = try makeWindow(environments: [:], globals: [entry("base", .plain(long))])
        let inspector = InspectorViewController(window: window, theme: theme, memory: InspectorMemory())
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        inspector.view.layoutSubtreeIfNeeded()

        let cell = try valueCell("base", in: inspector)
        #expect(cell.stringValue == long)
        #expect(cell.toolTip == long)
        #expect(cell.lineBreakMode == .byTruncatingTail)
        #expect(cell.attributedStringValue.size().width > cell.frame.width)
        #expect(cell.frame.maxX <= inspector.variables.documentView.frame.width - 12)
    }

    // MARK: Curl pane

    /// Board 11's window: Dev active with a secret api_key, and the refund POST.
    func board11(isDark: Bool = false) throws -> (WindowModel, InspectorViewController) {
        let window = try makeWindow(
            environments: ["Dev": [entry("host", .plain("https://api.dev.payments.example.com")), entry("api_key", .secret)]],
            globals: []
        )
        try secrets.inner.set("sk_live_1", environment: "Dev", name: VariableName("api_key")!)
        window.pickActiveEnvironment("Dev")
        let tab = try #require(window.selectedTab)
        tab.tab.definition.method = "POST"
        tab.tab.definition.url = "{{host}}/v1/refunds"
        tab.tab.definition.headers = [Row(name: "Content-Type", value: "application/json"), Row(name: "X-Off", value: "1", isEnabled: false)]
        tab.tab.definition.auth = .bearer(token: "{{api_key}}")
        tab.tab.definition.cookies = [Row(name: "session", value: "7f3a"), Row(name: "locale", value: "en")]
        tab.tab.definition.body = .raw(.json, #"{"charge":"ch_3PqL8x2e","amount":500}"#)
        let inspector = InspectorViewController(window: window, theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: isDark), memory: InspectorMemory())
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        inspector.showPane(1)
        inspector.view.layoutSubtreeIfNeeded()
        return (window, inspector)
    }

    let board11Command = #"""
        curl -X POST 'https://api.dev.payments.example.com/v1/refunds' \
          -H 'Content-Type: application/json' \
          -H 'Authorization: Bearer {{api_key}}' \
          -b 'session=7f3a; locale=en' \
          --data-raw '{"charge":"ch_3PqL8x2e","amount":500}'
        """#

    /// The colour of the command's text at the first `needle`.
    func color(of needle: String, in pane: CurlPaneView) -> NSColor? {
        let range = (pane.textView.string as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return pane.textView.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    /// Waits for the observation's re-render, a turn or more after the change.
    func settle(_ done: () -> Bool) async {
        for _ in 0..<100 where !done() { await Task.yield() }
    }

    @Test(arguments: [false, true])
    func `board 11: the command colored by token, the secret as {{name}}, the note and the footer`(isDark: Bool) throws {
        let (_, inspector) = try board11(isDark: isDark)
        let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: isDark)
        let pane = inspector.curl

        #expect(pane.textView.string == board11Command)
        #expect(pane.note == "Resolved with Dev. Disabled Rows are left out.")
        #expect(pane.voidTitle == nil && pane.voidText == nil)
        #expect(pane.includeSecrets.title == "Include secrets" && pane.includeSecrets.state == .off && !pane.includeSecrets.isHidden)
        #expect(pane.copyButton.title == "Copy" && pane.copyButton.isEnabled)
        #expect(color(of: "curl", in: pane) == theme.color(.curlFlag))
        #expect(color(of: "-H", in: pane) == theme.color(.curlFlag))
        #expect(color(of: "--data-raw", in: pane) == theme.color(.curlFlag))
        #expect(color(of: "'Content-Type", in: pane) == theme.color(.jsonPunctuation))
        #expect(color(of: "Content-Type", in: pane) == theme.color(.jsonKey))
        #expect(color(of: "{{api_key}}", in: pane) == theme.color(.variableSecret))
        let at = (pane.textView.string as NSString).range(of: "{{api_key}}").location
        #expect(pane.textView.textStorage?.attribute(.underlineStyle, at: at, effectiveRange: nil) as? Int
            == NSUnderlineStyle([.single, .patternDot]).rawValue)
        #expect(pane.textView.font == .monospacedSystemFont(ofSize: 11, weight: .regular))
        #expect(pane.box.layer?.backgroundColor == theme.color(.background).cgColor)
        #expect(pane.box.layer?.borderColor == theme.color(.border).cgColor && pane.box.layer?.cornerRadius == 6)
    }

    @Test(arguments: [false, true])
    func `the preview never shows a secret value; Include secrets fills it in the copied text only`(on: Bool) throws {
        let (_, inspector) = try board11()
        let pane = inspector.curl

        pane.includeSecrets.state = on ? .on : .off
        pane.copyButton.performClick(nil)

        #expect(!pane.textView.string.contains("sk_live_1"))
        #expect(clipboard.string == (on ? board11Command.replacing("{{api_key}}", with: "sk_live_1") : board11Command))
        // Only Copy with Include secrets reads the Keychain; rendering never does.
        #expect(secrets.gets == (on ? 1 : 0))
    }

    @Test func `Undefined Variables: no command, every name, Copy disabled`() throws {
        let (_, inspector) = try board04()
        inspector.showPane(1)
        let pane = inspector.curl

        #expect(pane.voidTitle == "No curl command yet")
        #expect(pane.voidText == "charge_id and tenant_id are not defined in Staging or in Globals.")
        #expect(pane.box.isHidden && pane.note == nil)
        #expect(!pane.copyButton.isEnabled && pane.includeSecrets.isHidden)
    }

    @Test func `an empty Draft asks for a URL, and an invalid one is quoted`() async throws {
        let (window, inspector) = try board11()
        let tab = try #require(window.selectedTab)
        let pane = inspector.curl

        tab.tab.definition = .empty
        await settle { pane.voidText != nil }
        #expect(pane.voidTitle == nil && pane.voidText == "Type a URL to see the curl command.")
        #expect(!pane.copyButton.isEnabled && pane.includeSecrets.isHidden)

        tab.tab.definition.url = "localhost:4000/a"
        await settle { pane.voidTitle != nil }
        #expect(pane.voidTitle == "No curl command yet" && pane.voidText == "After substitution the URL was localhost:4000/a.")
        #expect(!pane.copyButton.isEnabled)
    }

    @Test func `it follows edits, the Active Environment and the selected Tab`() async throws {
        let (window, inspector) = try board11()
        let pane = inspector.curl
        let tab = try #require(window.selectedTab)

        tab.tab.definition.method = "GET"
        tab.tab.definition.body = .none
        tab.tab.definition.headers = []
        tab.tab.definition.cookies = []
        tab.tab.definition.auth = .none
        let get = "curl 'https://api.dev.payments.example.com/v1/refunds'"
        await settle { pane.textView.string == get }
        #expect(pane.textView.string == get)

        window.pickActiveEnvironment(nil)
        await settle { pane.voidTitle != nil }
        #expect(pane.voidText == "host is not defined in Globals.")

        window.newTab()
        await settle { pane.voidTitle == nil }
        #expect(pane.voidText == "Type a URL to see the curl command.")

        window.select(tab.tab.id)
        await settle { pane.voidTitle != nil }
        #expect(pane.voidText == "host is not defined in Globals.")
    }

    @Test func `break-ui: a 2,000-character URL and a 20 KB body wrap, scroll, and Copy gives the exact text`() async throws {
        let (window, inspector) = try board11()
        let tab = try #require(window.selectedTab)
        let pane = inspector.curl
        let url = "https://h/" + String(repeating: "a", count: 1_990)
        let body = String(repeating: #"{"k":"0123456789"},"#, count: 1_100)
        tab.tab.definition.url = url
        tab.tab.definition.headers = []
        tab.tab.definition.auth = .none
        tab.tab.definition.cookies = []
        tab.tab.definition.body = .raw(.json, body)
        let expected = "curl -X POST '\(url)' \\\n  --data-raw '\(body)'"
        await settle { pane.textView.string == expected }
        inspector.view.layoutSubtreeIfNeeded()

        #expect(url.count == 2_000 && body.utf8.count >= 20_000)
        #expect(pane.textView.string == expected)
        let scroll = try #require(pane.textView.enclosingScrollView)
        #expect(!scroll.hasHorizontalScroller && scroll.hasVerticalScroller)
        let container = try #require(pane.textView.textContainer)
        let manager = try #require(pane.textView.layoutManager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        // Wrapped to the box's width, and taller than it: the box scrolls, nothing is cut.
        #expect(used.width <= scroll.contentSize.width && used.height > scroll.contentSize.height)
        #expect(pane.textView.frame.height >= used.height)
        pane.copyButton.performClick(nil)
        #expect(clipboard.string == expected)
    }
}
