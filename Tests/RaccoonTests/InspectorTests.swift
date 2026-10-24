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
    /// The window's Keychain: counts reads, and can refuse a write.
    let secrets = FlakySecretStore()

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
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    /// Board 04's window: Staging active, a Tab using two names nothing defines.
    func board04() throws -> (WindowModel, InspectorViewController) {
        let window = try makeWindow(
            environments: ["Staging": [entry("host", .plain("https://api.staging")), entry("access_token", .plain(jwt)), entry("api_key", .secret)]],
            globals: [entry("host", .plain("http://localhost:4000")), entry("user_agent", .plain("Raccoon/1.0"))]
        )
        window.pickActiveEnvironment("Staging")
        let tab = try #require(window.selectedTab)
        tab.tab.definition.url = "{{host}}/v1/charges/{{charge_id}}"
        tab.tab.definition.headers = [Row(name: "Authorization", value: "Bearer {{access_token}}"), Row(name: "X-Tenant", value: "{{tenant_id}}")]
        let inspector = InspectorViewController(window: window, theme: theme)
        inspector.view.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        inspector.view.layoutSubtreeIfNeeded()
        return (window, inspector)
    }

    @Test func `the header names the pane; Variables is selected and Curl waits for its pane`() throws {
        let (_, inspector) = try board04()
        #expect(inspector.paneTitle.stringValue == "Variables")
        #expect(inspector.paneSwitch.selectedSegment == 0)
        #expect(inspector.paneSwitch.label(forSegment: 0) == "Variables" && inspector.paneSwitch.label(forSegment: 1) == "Curl")
        #expect(!inspector.paneSwitch.isEnabled(forSegment: 1))
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
        #expect(segments.map { $0.isAccessibilityEnabled() } == [true, false])
    }

    @Test func `the switch swaps the pane under the header and the title follows; a reveal comes back to Variables`() throws {
        let (_, inspector) = try board04()
        let footer = try #require(inspector.editButton.superview)

        inspector.showPane(1)
        #expect(inspector.paneTitle.stringValue == "Curl" && inspector.paneSwitch.selectedSegment == 1)
        #expect(inspector.variables.isHidden && footer.isHidden)

        inspector.reveal(VariableName("host")!)
        #expect(inspector.paneTitle.stringValue == "Variables" && inspector.paneSwitch.selectedSegment == 0)
        #expect(!inspector.variables.isHidden && !footer.isHidden)
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
        let inspector = InspectorViewController(window: window, theme: theme)
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
}
