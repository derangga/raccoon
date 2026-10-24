import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// `{{name}}` highlighting in the URL field, the tables, the raw body, Auth and the section counts.
@MainActor
struct VariableHighlightTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }

    /// Globals: host (plain), key (secret). Dev: tenant. Prod: nothing.
    func makeWindow() throws -> WindowModel {
        func put(_ entries: [VariableEntry], _ path: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try EnvironmentFile.encode(entries).write(to: url)
        }
        try put([VariableEntry(name: VariableName("host")!, value: .plain("h")), VariableEntry(name: VariableName("key")!, value: .secret)], "globals.json")
        try put([VariableEntry(name: VariableName("tenant")!, value: .plain("t"))], "environments/Dev.json")
        try put([], "environments/Prod.json")
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        window.pickActiveEnvironment("Dev")
        return window
    }

    func color(_ text: NSAttributedString, at location: Int) -> NSColor? {
        text.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    func isDotted(_ text: NSAttributedString, at location: Int) -> Bool {
        (text.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int).map { $0 & NSUnderlineStyle.patternDot.rawValue != 0 } ?? false
    }

    func isWavy(_ text: NSAttributedString, at location: Int) -> Bool {
        text.attribute(.wavyUnderline, at: location, effectiveRange: nil) != nil
    }

    @Test func `defined, secret and undefined each get their colour, and undefined a wave, not colour alone`() {
        let kinds = VariableKinds(active: nil, globals: Globals(entries: [
            VariableEntry(name: VariableName("a")!, value: .plain("1")), VariableEntry(name: VariableName("s")!, value: .secret),
        ]))
        let text = NSMutableAttributedString(string: "{{a}} {{s}} {{u}}")

        VariableStyle.apply(kinds, to: text, disabled: false, theme: theme)

        #expect(color(text, at: 0) == theme.color(.variableDefined))
        #expect(!isDotted(text, at: 0) && !isWavy(text, at: 0))
        #expect(color(text, at: 6) == theme.color(.variableSecret) && isDotted(text, at: 6))
        #expect(color(text, at: 12) == theme.color(.variableUndefined) && isWavy(text, at: 12))

        let disabled = NSMutableAttributedString(string: "{{a}} {{s}} {{u}}")
        VariableStyle.apply(kinds, to: disabled, disabled: true, theme: theme)
        #expect([0, 6, 12].allSatisfy { color(disabled, at: $0) == theme.color(.textDisabled) })
        #expect(isWavy(disabled, at: 12))
    }

    @Test func `the URL field is coloured, and switching the Active Environment re-colours it`() async throws {
        let window = try makeWindow()
        let model = try #require(window.selectedTab)
        model.typeInURLBar("https://{{host}}/{{tenant}}?k={{key}}")
        let bar = URLBar(model: model, theme: theme)
        let field = { bar.urlField.attributedStringValue }

        #expect(color(field(), at: 8) == theme.color(.variableDefined))
        #expect(color(field(), at: 17) == theme.color(.variableDefined))
        #expect(isDotted(field(), at: 31))

        window.pickActiveEnvironment("Prod")
        for _ in 0..<100 where !isWavy(field(), at: 17) { await Task.yield() }
        #expect(color(field(), at: 17) == theme.color(.variableUndefined) && isWavy(field(), at: 17))
    }

    @Test func `a table cell holds all three kinds, a Disabled Row is textDisabled, and the count turns undefined`() async throws {
        let window = try makeWindow()
        let model = try #require(window.selectedTab)
        model.tab.definition.headers = [
            Row(name: "X-Mixed", value: "{{host}} {{key}} {{nope}}"),
            Row(name: "X-Off", value: "{{tenant}}", isEnabled: false),
        ]
        let editor = RequestEditor(model: model, theme: theme)
        let table = editor.table(.headers)
        func value(_ row: Int) throws -> NSAttributedString {
            let cell = try #require(table.table.view(atColumn: 2, row: table.leadRows + row, makeIfNecessary: true) as? NSTableCellView)
            return try #require(cell.textField).attributedStringValue
        }

        let mixed = try value(0)
        #expect(color(mixed, at: 0) == theme.color(.variableDefined))
        #expect(isDotted(mixed, at: 9))
        #expect(isWavy(mixed, at: 17))
        #expect(color(try value(1), at: 0) == theme.color(.textDisabled))
        #expect(editor.sectionButton(.headers).detailColor == theme.color(.variableUndefined))
        #expect(editor.sectionButton(.params).detailColor == nil)

        // The Disabled Row's {{tenant}} does not count; Prod leaves only the enabled {{nope}}.
        model.tab.definition.headers.removeFirst()
        for _ in 0..<100 where editor.sectionButton(.headers).detailColor != theme.color(.textTertiary) { await Task.yield() }
        #expect(editor.sectionButton(.headers).detailColor == theme.color(.textTertiary))
    }

    @Test func `the raw body and the Auth fields are coloured`() throws {
        let window = try makeWindow()
        let model = try #require(window.selectedTab)
        model.tab.definition.body = .raw(.json, #"{"t": "{{tenant}}", "n": "{{nope}}"}"#)
        model.tab.definition.auth = .bearer(token: "{{key}}")
        let editor = RequestEditor(model: model, theme: theme)

        let body = try #require(editor.bodyPane.textView.textStorage)
        #expect(color(body, at: 8) == theme.color(.variableDefined))
        #expect(isWavy(body, at: 27))
        #expect(isDotted(editor.authPane.token.attributedStringValue, at: 0))
    }

    @Test func `typing re-colours on every keystroke, in an editor that draws the waves`() throws {
        let field = VariableField()
        field.theme = theme
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.kinds = VariableKinds(active: nil, globals: Globals(entries: [VariableEntry(name: VariableName("host")!, value: .plain("h"))]))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView?.addSubview(field)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 22)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(editor.layoutManager is WavyLayoutManager)

        editor.insertText("{{nope}} {{host}}", replacementRange: NSRange(location: 0, length: 0))

        let storage = try #require(editor.textStorage)
        #expect(isWavy(storage, at: 0))
        #expect(color(storage, at: 9) == theme.color(.variableDefined))
        window.makeFirstResponder(nil)
        #expect(isWavy(field.attributedStringValue, at: 0))
    }
}
