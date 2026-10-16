import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct RequestEditorTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), instants: FixedInstantSource(.now))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [], backing: .buffered, defer: false)

    func editor() -> RequestEditor {
        let editor = RequestEditor(model: model, theme: theme)
        editor.frame = window.contentView!.bounds
        window.contentView!.addSubview(editor)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    @Test func `the section bar counts every row, Disabled Rows too, and shows no count for none`() {
        var definition = RequestDefinition.empty
        definition.params = [Row(name: "a", value: "1"), Row(name: "b", value: "2", isEnabled: false), Row(name: "c", value: "")]
        definition.headers = [Row(name: "Accept", value: "*/*")]
        #expect(EditorSection.allCases.map { $0.title(in: definition) }
            == ["Params 3", "Headers 1", "Body", "Auth", "Cookies", "Settings"])
    }

    @Test func `Body shows its Body Type and Auth its scheme`() {
        var definition = RequestDefinition.empty
        definition.body = .raw(.json, "{}")
        definition.auth = .bearer(token: "t")
        #expect((EditorSection.body.title(in: definition), EditorSection.auth.title(in: definition)) == ("Body JSON", "Auth Bearer"))
        definition.body = .formURLEncoded([])
        definition.auth = .basic(user: "u", password: "p")
        #expect((EditorSection.body.title(in: definition), EditorSection.auth.title(in: definition)) == ("Body form", "Auth Basic"))
    }

    @Test func `a count needs no plural change`() {
        var definition = RequestDefinition.empty
        definition.headers = (1...60).map { Row(name: "X-\($0)", value: "") }
        #expect(EditorSection.headers.title(in: definition) == "Headers 60")
    }

    @Test func `Params is shown first, and picking a section shows only its pane`() {
        let editor = editor()
        #expect(editor.selected == .params)
        #expect(!editor.table(.params).isHidden && editor.table(.headers).isHidden)
        editor.select(.headers)
        #expect(editor.table(.params).isHidden && !editor.table(.headers).isHidden)
    }

    @Test(arguments: [EditorSection.params, .headers, .cookies])
    func `editing a table writes the Tab's definition`(section: EditorSection) {
        let editor = editor()
        let rows = [Row(name: "a", value: "1", isEnabled: false)]
        editor.table(section).onChange(rows)
        let written = switch section {
        case .params: model.tab.definition.params
        case .headers: model.tab.definition.headers
        default: model.tab.definition.cookies
        }
        #expect(written == rows)
    }

    @Test func `the Headers table shows what URLSession adds, and nothing while the URL cannot resolve`() {
        let editor = editor()
        let headers = editor.table(.headers).table
        #expect(headers.numberOfRows == 1)

        model.tab.definition.url = "https://example.com"
        editor.render()
        #expect(headers.numberOfRows == 7)
        #expect(((headers.view(atColumn: 2, row: 1, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue) == "example.com")

        model.tab.definition.headers = [Row(name: "host", value: "other")]
        editor.render()
        #expect(headers.numberOfRows == 7)  // one row, the trailing row, five automatic
    }
}

@MainActor
struct EditorSplitTests {
    @Test func `each pane keeps 160 pt`() {
        let split = EditorSplitView()
        split.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        split.addSubview(NSView())
        split.addSubview(NSView())
        #expect(split.delegate?.splitView?(split, constrainMinCoordinate: 0, ofSubviewAt: 0) == 160)
        #expect(split.delegate?.splitView?(split, constrainMaxCoordinate: 494, ofSubviewAt: 0) == 334)
        #expect(split.dividerThickness == 6)
    }
}
