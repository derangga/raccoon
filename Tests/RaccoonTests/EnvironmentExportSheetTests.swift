import AppKit
import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Environment Export sheet over a real window and a recording SecretStore, with a recording
/// FileWriting and a save panel that answers what the test says.
@MainActor
struct EnvironmentExportSheetTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let store = FlakySecretStore()
    let target = URL(filePath: "/tmp/raccoon-export/Staging.postman_environment.json")
    let other = URL(filePath: "/tmp/raccoon-export/Other.postman_environment.json")
    let token = VariableName("token")!
    let key = VariableName("key")!
    let pin = VariableName("pin")!
    // Not real provider keys: words that say what they are.
    let tokenValue = "example-token-value"
    let keyValue = "example-key-value"

    func makeWindow() -> WindowModel {
        let root = temp.appending(path: "Raccoon")
        return WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: store, instants: FixedInstantSource(.now),
            makeTab: { [store] in
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: store, files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    /// Two plain Variables (one Disabled), and three secrets: token, key (Disabled) and pin.
    var staging: Environment {
        Environment(name: "Staging", entries: [
            VariableEntry(name: VariableName("host")!, value: .plain("https://api.example.com")),
            VariableEntry(name: token, value: .secret),
            VariableEntry(name: key, isEnabled: false, value: .secret),
            VariableEntry(name: pin, value: .secret),
            VariableEntry(name: VariableName("debug")!, isEnabled: false, value: .plain("true")),
        ])
    }

    @MainActor final class Harness {
        let sheet: EnvironmentExportSheet
        let window: NSWindow
        let files: RecordingFileWriting
        var asked: [String] = []
        /// How many Keychain reads had happened each time the save panel was asked for.
        var getsWhenAsked: [Int] = []
        var exported = 0

        init(environment: Environment, readSecrets: @escaping () -> EnvironmentSecrets, store: FlakySecretStore, files: RecordingFileWriting, answers: [URL?]) {
            self.files = files
            var answers = answers
            var box: Harness?
            let sheet = EnvironmentExportSheet(
                model: EnvironmentExportModel(environment), readSecrets: readSecrets, writer: files,
                choose: { _, name in
                    box?.asked.append(name)
                    box?.getsWhenAsked.append(store.gets)
                    return answers.isEmpty ? nil : answers.removeFirst()
                },
                id: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! },
                now: { Date(timeIntervalSince1970: 1_793_000_000) }, version: "1.2.3"
            )
            sheet.onExported = { box?.exported += 1 }
            self.sheet = sheet
            window = sheetPanel(sheet, focus: sheet.exportButton)
            box = self
            _ = sheet.view
        }
    }

    func harness(_ environment: Environment? = nil, files: RecordingFileWriting = RecordingFileWriting(), answers: [URL?] = []) -> Harness {
        let environment = environment ?? staging
        let model = makeWindow()
        return Harness(environment: environment, readSecrets: { model.readSecrets(of: environment) }, store: store, files: files, answers: answers)
    }

    /// The file's `values`, by key: (value, type, enabled).
    func values(_ data: Data) throws -> [String: (String, String, Bool)] {
        let file = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let list = try #require(file["values"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: list.map { ($0["key"] as! String, ($0["value"] as! String, $0["type"] as! String, $0["enabled"] as! Bool)) })
    }

    /// The one file written.
    func written(_ files: RecordingFileWriting) throws -> Data {
        try #require(files.writes.first).data
    }

    // MARK: Opening

    @Test func `the sheet says what it exports, with the checkbox off and its hint, and nothing else yet`() {
        let h = harness()
        #expect(h.sheet.titleLabel.stringValue == "Export “Staging”")
        #expect(h.sheet.countsLabel.stringValue == "5 Variables, 3 secrets")
        #expect(h.sheet.includeBox.title == "Include secret values")
        #expect(h.sheet.includeBox.state == .off)
        #expect(!h.sheet.includeBox.isHidden && !h.sheet.hintLabel.isHidden)
        #expect(h.sheet.hintLabel.stringValue == "Secrets are exported empty.")
        #expect(h.sheet.cancelButton.title == "Cancel")
        #expect(h.sheet.exportButton.title == "Export…" && h.sheet.exportButton.isEnabled)
        #expect(h.sheet.failureLabel.isHidden)
        #expect(h.sheet.doneButton.isHidden)
    }

    @Test func `ticking the box changes the hint to say the values are written in plain text`() {
        let h = harness()
        h.sheet.includeBox.performClick(nil)
        #expect(h.sheet.includeBox.state == .on)
        #expect(h.sheet.hintLabel.stringValue == "Secret values are written to the file in plain text.")
        h.sheet.includeBox.performClick(nil)
        #expect(h.sheet.hintLabel.stringValue == "Secrets are exported empty.")
    }

    @Test func `an Environment with no secret has no checkbox and no hint`() {
        let h = harness(Environment(name: "Dev", entries: [VariableEntry(name: VariableName("host")!, value: .plain("x"))]))
        #expect(h.sheet.countsLabel.stringValue == "1 Variable, 0 secrets")
        #expect(h.sheet.includeBox.isHidden)
        #expect(h.sheet.hintLabel.isHidden)
    }

    @Test func `the sheet is 380 pt wide`() {
        let h = harness()
        h.sheet.view.layoutSubtreeIfNeeded()
        #expect(h.sheet.view.fittingSize.width == 380)
    }

    // MARK: Cancel

    @Test func `Cancel on the sheet writes nothing, reads no secret and opens no save panel`() async throws {
        let h = harness(answers: [target])
        h.sheet.includeBox.performClick(nil)
        h.sheet.cancelButton.performClick(nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(h.files.writes.isEmpty)
        #expect(h.asked.isEmpty)
        #expect(store.gets == 0)
        #expect(h.exported == 0)
    }

    @Test func `Cancel in the save panel, box ticked: back on the sheet, nothing written, no Keychain read`() async {
        let h = harness(answers: [nil])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()

        #expect(h.asked == ["Staging.postman_environment.json"])
        #expect(h.files.writes.isEmpty)
        #expect(store.gets == 0)
        #expect(h.exported == 0)
        #expect(h.sheet.failureLabel.isHidden)
        #expect(h.sheet.exportButton.isEnabled)
        #expect(h.sheet.includeBox.state == .on)
    }

    @Test func `a second press while the save panel is being asked for does nothing`() async {
        let h = harness(answers: [target, target])
        h.sheet.exportButton.performClick(nil)
        #expect(!h.sheet.exportButton.isEnabled)
        h.sheet.exportButton.performClick(nil)
        for _ in 0..<50 { await Task.yield() }
        #expect(h.asked.count == 1)
    }

    // MARK: The box off

    @Test func `Export… with the box off asks the Keychain nothing, and writes every secret empty`() async throws {
        try store.inner.set(tokenValue, environment: "Staging", name: token)
        let h = harness(answers: [target])
        await h.sheet.export()

        #expect(store.gets == 0 && store.inner.gets.isEmpty)
        #expect(h.files.writes.map(\.url) == [target])
        let written = try values(try written(h.files))
        #expect(written["token"]! == ("", "secret", true))
        #expect(written["key"]! == ("", "secret", false))
        #expect(written["host"]! == ("https://api.example.com", "default", true))
        #expect(written["debug"]! == ("true", "default", false))
        #expect(h.exported == 1)
    }

    @Test func `the file is the exporter's, with the id, date and version the sheet was given`() async throws {
        let h = harness(answers: [target])
        await h.sheet.export()
        let file = try #require(try JSONSerialization.jsonObject(with: try written(h.files)) as? [String: Any])
        #expect(file["id"] as? String == "11111111-2222-3333-4444-555555555555")
        #expect(file["name"] as? String == "Staging")
        #expect(file["_postman_exported_using"] as? String == "Raccoon/1.2.3")
        #expect(file["_postman_exported_at"] as? String == Date(timeIntervalSince1970: 1_793_000_000).ISO8601Format(.init(includingFractionalSeconds: true)))
    }

    // MARK: The box ticked

    @Test func `ticked, the Keychain is read once per Secret Variable and only after the save panel returned`() async throws {
        try store.inner.set(tokenValue, environment: "Staging", name: token)
        try store.inner.set(keyValue, environment: "Staging", name: key)
        let h = harness(answers: [target])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()

        #expect(h.getsWhenAsked == [0])
        #expect(store.inner.gets == [token, key, pin].map { .init(environment: "Staging", name: $0) })
        let written = try values(try written(h.files))
        #expect(written["token"]! == (tokenValue, "secret", true))
        #expect(written["key"]! == (keyValue, "secret", false))
        // Never given a value: empty, and with nothing to report the sheet just closes.
        #expect(written["pin"]! == ("", "secret", true))
        #expect(h.exported == 1)
        #expect(h.sheet.doneButton.isHidden)
    }

    // MARK: A refused read

    @Test func `a refused read exports that secret empty, names it after the write, and the others are read`() async throws {
        try store.inner.set(tokenValue, environment: "Staging", name: token)
        try store.inner.set(keyValue, environment: "Staging", name: key)
        store.refuseGets(of: [key], with: .unavailable(-128))
        let h = harness(answers: [target])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()

        let written = try values(try written(h.files))
        #expect(written["token"]! == (tokenValue, "secret", true))
        #expect(written["key"]! == ("", "secret", false))
        // The sheet shows the result instead of closing, and never reports a failed export.
        #expect(h.exported == 0)
        #expect(h.sheet.failureLabel.isHidden)
        #expect(h.sheet.resultLabel.stringValue == "Exported to Staging.postman_environment.json")
        #expect(h.sheet.unreadableLabel.stringValue == "1 secret could not be read from the Keychain and is empty in the file.")
        #expect(h.sheet.namesLabel.stringValue == "key")
        #expect(h.sheet.namesLabel.font == .monospacedSystemFont(ofSize: 11, weight: .regular))
        #expect(!h.sheet.resultStack.isHidden && !h.sheet.doneButton.isHidden)
        #expect(h.sheet.titleLabel.isHidden && h.sheet.exportButton.isHidden && h.sheet.cancelButton.isHidden && h.sheet.includeBox.isHidden)
    }

    @Test func `once the result shows, the hidden Export… stays disabled`() async throws {
        store.refuseGets(of: [key], with: .unavailable(-128))
        let h = harness(answers: [target])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()
        #expect(h.sheet.exportButton.isHidden)
        #expect(!h.sheet.exportButton.isEnabled)
    }

    @Test func `Done on the result closes the sheet`() async throws {
        store.refuseGets(of: [token, key, pin], with: .unavailable(-128))
        let h = harness(answers: [target])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()
        #expect(h.sheet.unreadableLabel.stringValue == "3 secrets could not be read from the Keychain and are empty in the file.")
        #expect(h.sheet.namesLabel.stringValue == "token · key · pin")

        // The order matters: the result is swapped in first, the sheet attached to its parent after.
        // Attached to an unshown parent first, changing the sheet's layout makes the test runner
        // exit 0 mid-run with no summary. Do not "fix" this order; manual scenario 9 watches the
        // real one (a visible window, the swap while attached).
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        parent.beginSheet(h.window, completionHandler: nil)
        h.sheet.doneButton.performClick(nil)
        for _ in 0..<50 { await Task.yield() }
        #expect(parent.attachedSheet == nil)
    }

    @Test func `break-ui: 40 unreadable secrets stay on one line, then and N more`() async throws {
        let many = (1...40).map { VariableName("secret_number_\($0)")! }
        let environment = Environment(name: "Big", entries: many.map { VariableEntry(name: $0, value: .secret) })
        store.refuseGets(of: many, with: .unavailable(-128))
        let h = harness(environment, answers: [target])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()
        h.sheet.view.layoutSubtreeIfNeeded()

        let names = h.sheet.namesLabel
        #expect(names.stringValue.hasPrefix("secret_number_1 · secret_number_2"))
        #expect(names.stringValue.range(of: #" and \d+ more$"#, options: .regularExpression) != nil)
        #expect(names.maximumNumberOfLines == 1)
        #expect(NSAttributedString(string: names.stringValue, attributes: [.font: names.font!]).size().width <= 340 - 22)
        #expect(names.toolTip?.contains("secret_number_40") == true)
        #expect(h.sheet.unreadableLabel.stringValue.hasPrefix("40 secrets could not be read"))
    }

    // MARK: A failed write

    @Test func `a target that is not writable: the reason on the sheet, the sheet stays, and another place still works`() async throws {
        try store.inner.set(tokenValue, environment: "Staging", name: token)
        let files = RecordingFileWriting(failing: [target: .unwritable(path: target.path, reason: "The folder “raccoon-export” is not writable.")])
        let h = harness(files: files, answers: [target, other])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()

        #expect(files.writes.isEmpty)
        #expect(h.exported == 0)
        #expect(!h.sheet.failureLabel.isHidden)
        #expect(h.sheet.failureLabel.stringValue == "Not exported. The folder “raccoon-export” is not writable.")
        #expect(h.sheet.exportButton.isEnabled)
        #expect(h.sheet.resultStack.isHidden)

        await h.sheet.export()
        #expect(files.writes.map(\.url) == [other])
        #expect(h.sheet.failureLabel.isHidden)
        #expect(h.exported == 1)
        // Each attempt reads again; nothing is cached.
        #expect(store.gets == 6)
        #expect(try values(try written(files))["token"]! == (tokenValue, "secret", true))
    }

    // MARK: Round trip

    @Test func `the file imports back as the same Environment, secret values with it`() async throws {
        try store.inner.set(tokenValue, environment: "Staging", name: token)
        try store.inner.set(keyValue, environment: "Staging", name: key)
        let h = harness(answers: [target])
        h.sheet.includeBox.performClick(nil)
        await h.sheet.export()

        let data = try written(h.files)
        var next = 0
        let plan = PostmanMapping.plan(
            [PostmanImporter.read(data)], dataFolder: DataFolderIndex([]), globals: Globals(entries: []), environments: []
        ) {
            next += 1
            return RequestID(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(next)")!)
        }

        let imported = try #require(plan.environments.first)
        #expect(plan.environments.count == 1 && plan.collections.isEmpty && plan.globals.isEmpty)
        #expect(plan.notes.isEmpty)
        #expect(imported.name == "Staging")
        #expect(imported.variables.map(\.entry) == staging.entries)
        #expect(imported.variables.map(\.value) == [
            .plain("https://api.example.com"), .secret(tokenValue), .secret(keyValue), .secret(""), .plain("true"),
        ])
    }
}
