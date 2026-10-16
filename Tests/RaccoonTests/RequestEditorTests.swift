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

    @Test func `Settings has two checkboxes with their hints, and no compression row`() {
        let editor = editor()
        editor.select(.settings)
        let pane = editor.settingsPane
        #expect(!pane.isHidden)
        #expect(pane.checkboxes.map(\.title) == ["Allow insecure TLS", "Follow redirects"])
        #expect(pane.insecureTLSHint.stringValue == "Accept certificates the system does not trust, for this Request only.")
        #expect(pane.insecureTLSHint.textColor == theme.color(.textTertiary))
    }

    @Test func `each Settings checkbox writes the Tab's Request Settings and follows them`() {
        let editor = editor()
        let (insecure, redirects) = (editor.settingsPane.checkboxes[0], editor.settingsPane.checkboxes[1])
        #expect(insecure.state == .off && redirects.state == .off)

        insecure.performClick(nil)
        #expect(model.tab.definition.settings == RequestSettings(allowsInsecureTLS: true, followsRedirects: false))
        redirects.performClick(nil)
        #expect(model.tab.definition.settings == RequestSettings(allowsInsecureTLS: true, followsRedirects: true))

        // The failed state's fix turns the setting on from outside the pane.
        model.tab.definition.settings.allowsInsecureTLS = false
        editor.render()
        #expect(insecure.state == .off)
    }

    func pick(_ scheme: Int, in pane: AuthPane) {
        pane.scheme.selectedSegment = scheme
        pane.scheme.sendAction(pane.scheme.action, to: pane.scheme.target)
    }

    func type(_ text: String, in field: NSTextField, of pane: AuthPane) {
        field.stringValue = text
        pane.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    @Test func `Auth starts at None, which says no header is added`() {
        let pane = editor().authPane
        #expect((0..<3).map { pane.scheme.label(forSegment: $0) } == ["None", "Basic", "Bearer"])
        #expect(pane.scheme.selectedSegment == 0)
        #expect(!pane.noneNote.isHidden && pane.noneNote.stringValue == "No Authorization header is added.")
        #expect(pane.basicFields.isHidden && pane.bearerFields.isHidden)
    }

    @Test func `Basic writes the username and password, and the section label reads the scheme`() {
        let editor = editor()
        let pane = editor.authPane
        pick(1, in: pane)
        #expect(model.tab.definition.auth == .basic(user: "", password: ""))
        #expect(!pane.basicFields.isHidden && pane.bearerFields.isHidden && pane.noneNote.isHidden)

        type("ops-bot", in: pane.username, of: pane)
        type("hunter2", in: pane.password, of: pane)
        #expect(model.tab.definition.auth == .basic(user: "ops-bot", password: "hunter2"))
        #expect(EditorSection.auth.title(in: model.tab.definition) == "Auth Basic")
        #expect(pane.username.font == .monospacedSystemFont(ofSize: 12, weight: .regular))
    }

    @Test func `the password is bullets, unless it holds a Variable, which shows its name`() {
        let editor = editor()
        let pane = editor.authPane
        model.tab.definition.auth = .basic(user: "ops-bot", password: "hunter2")
        editor.render()
        #expect(!pane.password.isHidden && pane.passwordVariable.isHidden)

        model.tab.definition.auth = .basic(user: "ops-bot", password: "{{ops_password}}")
        editor.render()
        #expect(pane.password.isHidden && !pane.passwordVariable.isHidden)
        #expect(pane.passwordVariable.stringValue == "{{ops_password}}")
    }

    @Test func `Bearer writes its token, and switching schemes away and back keeps what was typed`() {
        let editor = editor()
        let pane = editor.authPane
        pick(2, in: pane)
        type("{{api_key}}", in: pane.token, of: pane)
        #expect(model.tab.definition.auth == .bearer(token: "{{api_key}}"))
        #expect(EditorSection.auth.title(in: model.tab.definition) == "Auth Bearer")

        editor.select(.auth)
        editor.layoutSubtreeIfNeeded()
        #expect(pane.token.frame.width > 200 && pane.token.superview!.frame.height == 26)

        pick(0, in: pane)
        #expect(model.tab.definition.auth == .none)
        pick(2, in: pane)
        #expect(model.tab.definition.auth == .bearer(token: "{{api_key}}"))
    }
}

@MainActor
struct BodyPaneTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), instants: FixedInstantSource(.now))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [], backing: .buffered, defer: false)

    func pane() -> (RequestEditor, BodyPane) {
        let editor = RequestEditor(model: model, theme: theme)
        editor.frame = window.contentView!.bounds
        window.contentView!.addSubview(editor)
        editor.select(.body)
        editor.layoutSubtreeIfNeeded()
        return (editor, editor.bodyPane)
    }

    func pick(_ title: String, in menu: NSMenu) {
        let item = try! #require(menu.item(withTitle: title))
        menu.performActionForItem(at: menu.index(of: item))
    }

    func type(_ text: String, in pane: BodyPane) {
        pane.textView.string = text
        pane.textView.didChangeText()
    }

    @Test func `none says the request has no body`() {
        let (_, pane) = pane()
        #expect(pane.typeButton.attributedTitle.string.hasPrefix("none"))
        #expect(!pane.noneNote.isHidden && pane.noneNote.stringValue == "This request has no body.")
        #expect(pane.kindButton.isHidden && pane.textBox.isHidden && pane.formTable.isHidden)
        #expect(pane.typeMenu.items.map(\.title) == ["none", "raw", "form-urlencoded", "multipart"])
    }

    @Test func `picking raw JSON opens the editor and writes the Content-Type row`() {
        let (editor, pane) = pane()
        pick("raw", in: pane.typeMenu)
        #expect(model.tab.definition.body == .raw(.json, ""))
        #expect(model.tab.definition.headers == [Row(name: "Content-Type", value: "application/json")])
        editor.render()
        #expect(!pane.textBox.isHidden && pane.noneNote.isHidden && !pane.kindButton.isHidden)
        #expect(pane.kindButton.attributedTitle.string.hasPrefix("JSON"))
        #expect(pane.kindMenu.items.map(\.title) == ["JSON", "text", "XML"])
        #expect(EditorSection.body.title(in: model.tab.definition) == "Body JSON")
    }

    @Test func `typing raw JSON writes the body and colors it, text stays uncolored`() {
        let (editor, pane) = pane()
        model.tab.definition.body = .raw(.json, "")
        editor.render()
        type(#"{"a": 1}"#, in: pane)
        #expect(model.tab.definition.body == .raw(.json, #"{"a": 1}"#))
        let storage = pane.textView.textStorage!
        #expect(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == theme.color(.jsonKey))
        #expect(storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont == .monospacedSystemFont(ofSize: 12, weight: .regular))

        pick("text", in: pane.kindMenu)
        editor.render()
        #expect(model.tab.definition.body == .raw(.text, #"{"a": 1}"#))
        #expect(pane.textView.textStorage!.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == theme.color(.text))
    }

    @Test func `JSON to none to JSON gives the text back through Undo`() throws {
        let (editor, pane) = pane()
        model.tab.definition.body = .raw(.json, #"{"a": 1}"#)
        model.tab.definition.headers = [Row(name: "Content-Type", value: "application/json")]
        editor.render()
        let undo = try #require(window.undoManager)
        undo.groupsByEvent = false
        for title in ["none", "raw"] {
            undo.beginUndoGrouping()
            pick(title, in: pane.typeMenu)
            undo.endUndoGrouping()
        }
        #expect(model.tab.definition.body == .raw(.json, ""))

        undo.undo()
        #expect(model.tab.definition.body == .none && model.tab.definition.headers.isEmpty)
        undo.undo()
        editor.render()
        #expect(model.tab.definition.body == .raw(.json, #"{"a": 1}"#))
        #expect(model.tab.definition.headers == [Row(name: "Content-Type", value: "application/json")])
        #expect(pane.textView.string == #"{"a": 1}"#)
    }

    @Test func `form-urlencoded edits rows in the key/value table`() {
        let (editor, pane) = pane()
        pick("form-urlencoded", in: pane.typeMenu)
        editor.render()
        #expect(!pane.formTable.isHidden && pane.textBox.isHidden && pane.kindButton.isHidden)
        pane.formTable.onChange([Row(name: "q", value: "a b")])
        #expect(model.tab.definition.body == .formURLEncoded([Row(name: "q", value: "a b")]))
    }

    @Test func `Japanese and emoji in a raw body render, color and edit`() {
        let (editor, pane) = pane()
        let text = #"{"名前": "🦝 ラクーン"}"#
        model.tab.definition.body = .raw(.json, text)
        editor.render()
        #expect(pane.textView.string == text)
        let value = (text as NSString).range(of: "\"🦝 ラクーン\"")
        #expect(pane.textView.textStorage!.attribute(.foregroundColor, at: value.location + value.length - 1, effectiveRange: nil) as? NSColor
            == theme.color(.jsonString))
        type(text + " ", in: pane)
        #expect(model.tab.definition.body == .raw(.json, text + " "))
    }

    @Test func `the raw editor has line numbers and no wrapping`() {
        let (editor, pane) = pane()
        model.tab.definition.body = .raw(.json, "{\n}")
        editor.render()
        #expect(pane.textView.enclosingScrollView?.rulersVisible == true)
        #expect(pane.textView.enclosingScrollView?.verticalRulerView is LineNumberRuler)
        #expect(pane.textView.textContainer?.widthTracksTextView == false)
        #expect(pane.textView.layoutManager?.allowsNonContiguousLayout == true)
        pane.textView.enclosingScrollView?.verticalRulerView?.display()
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
