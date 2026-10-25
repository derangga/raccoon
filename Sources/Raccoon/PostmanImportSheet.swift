import AppKit
import RaccoonDomain

/// A file picked for Postman Import: what PostmanImporter made of it, or why it could not be
/// read. Either way it gets a row; only a Postman export can be ticked (§4).
struct PickedFile: Equatable {
    enum Content: Equatable {
        case read(PostmanFile)
        case unreadable(String)
    }

    var name: String
    var content: Content

    static func read(_ paths: [String], from files: any FileReading) -> [PickedFile] {
        paths.map { path in
            let name = URL(filePath: path).lastPathComponent
            do throws(StoreError) {
                return PickedFile(name: name, content: .read(PostmanImporter.read(try files.read(path))))
            } catch {
                return PickedFile(name: name, content: .unreadable(EnvironmentsSheet.reason(error)))
            }
        }
    }

    /// The export, when it is one Raccoon reads.
    var postman: PostmanFile? {
        guard case .read(let file) = content, file != .notPostman else { return nil }
        return file
    }
}

/// What the Postman Import sheet shows (design-system §6, postman.md The Import sheet): a row
/// per picked file, the notes and the footer, all from the ticked files' plan.
struct PostmanImport {
    struct Row: Equatable {
        enum Kind { case collection, environment, globals, other }
        var kind: Kind
        var title: String
        var detail: String
        var source: String
        var isEnabled: Bool
        var isTicked: Bool
    }

    /// One "What won't come across" line, and the names it applies to, blanks left out.
    struct NoteLine: Equatable {
        var isWarning: Bool
        var text: String
        var names: [String]
    }

    /// The sheet after Import.
    struct Outcome: Equatable {
        struct Line: Equatable {
            /// Red: not written. Otherwise orange: written without a secret's value.
            var isFailure: Bool
            var text: String
        }

        var heading: String
        var landed: String?
        var lines: [Line]
        /// The Collection the sidebar selects when the sheet closes.
        var reveal: String?
        var isComplete: Bool
    }

    let files: [PickedFile]
    var isTicked: [Bool]
    /// Why Import can't write, from the window's checkWritable; nil when it can.
    var writeProblem: String?
    private let window: WindowModel

    init(files: [PickedFile], window: WindowModel) {
        self.files = files
        self.window = window
        isTicked = files.map { $0.postman != nil }
        do throws(StoreError) {
            try window.checkWritable()
        } catch {
            writeProblem = EnvironmentsSheet.reason(error)
        }
    }

    /// What Import writes: the ticked files, planned afresh, so a rename follows the ticks.
    var plan: ImportPlan { plan(ticked) }

    var canImport: Bool { writeProblem == nil && !ticked.isEmpty }

    /// The Data Folder as the footer names it, set in mono there.
    var folder: String { (window.dataFolderRoot as NSString).abbreviatingWithTildeInPath }

    var footer: String {
        guard let writeProblem else { return "Imports into \(folder). Secrets go to the Keychain." }
        return "Can't import into \(folder). \(EnvironmentsSheet.sentence(writeProblem))"
    }

    private var ticked: [PostmanFile] {
        files.indices.filter { isTicked[$0] }.compactMap { files[$0].postman }
    }

    /// The Workspace's names: an unreadable Environment's too, so a rename never takes it.
    private func plan(_ files: [PostmanFile]) -> ImportPlan {
        PostmanMapping.plan(
            files, dataFolder: window.index, globals: window.globals,
            environments: window.environments + window.brokenEnvironments.map { Environment(name: $0.name, entries: []) },
            newID: { RequestID(UUID()) }
        )
    }

    // MARK: Rows

    var rows: [Row] {
        files.indices.map { index in
            let file = files[index]
            guard let postman = file.postman else {
                let detail = switch file.content {
                case .unreadable(let reason): "Can't be read: \(reason)"
                case .read: "Not a Postman export Raccoon reads"
                }
                return Row(kind: .other, title: file.name, detail: detail, source: "", isEnabled: false, isTicked: false)
            }
            // What this file adds after the ticked files the planner reads first.
            let before = ticked(before: index)
            let after = plan(before + [postman])
            var row = Row(kind: .other, title: "", detail: "", source: file.name, isEnabled: true, isTicked: isTicked[index])
            switch postman {
            case .collection(let collection):
                let planned = after.collections[after.collections.count - 1]
                row.kind = .collection
                row.title = Self.title(collection.name, planned.name, shown: window.importName(ofCollection:))
                row.detail = "Collection · " + Self.contents(planned.nodes) + Self.taken(collection.name, planned.name)
            case .environment(let environment):
                let planned = after.environments[after.environments.count - 1]
                let secrets = planned.variables.filter { if case .secret = $0.value { true } else { false } }.count
                row.kind = .environment
                row.title = Self.title(environment.name, planned.name, shown: window.importName(ofEnvironment:))
                row.detail = "Environment · " + Self.plural(planned.variables.count, "Variable")
                    + (secrets == 0 ? "" : ", " + Self.plural(secrets, "secret")) + Self.taken(environment.name, planned.name)
            case .globals:
                let earlier = plan(before)
                let kept = Self.kept(after).dropFirst(Self.kept(earlier).count)
                row.kind = .globals
                row.title = "Globals"
                row.detail = "\(Self.number(after.globals.count - earlier.globals.count)) new"
                    + (kept.isEmpty ? "" : " · \(Self.number(kept.count)) kept as \(kept.count == 1 ? "it is" : "they are") in Raccoon (\(kept.joined(separator: ", ")))")
            case .notPostman:
                preconditionFailure("postman is nil for a file that is not a Postman export")
            }
            return row
        }
    }

    /// The ticked files PostmanMapping reads before `index`: Collections, then Environments, then
    /// Globals, each in pick order.
    private func ticked(before index: Int) -> [PostmanFile] {
        let order = { (i: Int) in (files[i].postman.map(Self.rank) ?? 3, i) }
        return files.indices.filter { isTicked[$0] && order($0) < order(index) }.compactMap { files[$0].postman }
    }

    private static func rank(_ file: PostmanFile) -> Int {
        switch file {
        case .collection: 0
        case .environment: 1
        case .globals: 2
        case .notPostman: 3
        }
    }

    private static func title(_ name: String, _ planned: String, shown: (String) -> String) -> String {
        name == planned ? shown(planned) : "\(shown(name)) → \(planned)"
    }

    /// Renamed because the name is taken, not because it had a / or a :.
    private static func taken(_ name: String, _ planned: String) -> String {
        name.isEmpty || RequestFileName.sanitised(name) == planned ? "" : " · “\(name)” already exists"
    }

    private static func contents(_ nodes: [ImportNode]) -> String {
        func count(_ nodes: [ImportNode]) -> (requests: Int, folders: Int) {
            nodes.reduce((0, 0)) { total, node in
                switch node {
                case .request: return (total.0 + 1, total.1)
                case .folder(_, let children):
                    let inner = count(children)
                    return (total.0 + inner.requests, total.1 + 1 + inner.folders)
                }
            }
        }
        let (requests, folders) = count(nodes)
        let text = requests == 0 ? "No Requests" : plural(requests, "Request")
        return folders == 0 ? text : text + " in " + plural(folders, "Folder")
    }

    /// The names Globals keeps, in the order they were met.
    private static func kept(_ plan: ImportPlan) -> [String] {
        plan.notes.first { $0.kind == .globalSkipped }?.names ?? []
    }

    // MARK: Notes

    /// Every note of the ticked files' plan. Globals keeps a Globals file's names on its row; the
    /// Collection variables it keeps are a note of their own.
    var notes: [NoteLine] {
        var lines = Self.lines(plan.notes)
        let kept = Self.kept(plan(ticked.filter { if case .globals = $0 { false } else { true } }))
        if !kept.isEmpty {
            let one = kept.count == 1
            lines.append(NoteLine(
                isWarning: false,
                text: "\(Self.plural(kept.count, "Collection variable")) \(one ? "is" : "are") not added: Globals already has \(one ? "it" : "them").",
                names: kept
            ))
        }
        return lines
    }

    /// One line per note, in the plan's order; the dynamic variables share the first one's. A
    /// rename is on its row, and what Globals keeps on the Globals row or in `notes`.
    static func lines(_ notes: [ImportNote]) -> [NoteLine] {
        var lines: [NoteLine] = []
        var dynamic: (line: Int, variables: [String], names: [String])?
        for note in notes {
            let n = note.names.count
            let requests = plural(n, "Request")
            let one = n == 1
            let add = { (isWarning: Bool, text: String) in
                lines.append(NoteLine(isWarning: isWarning, text: text, names: note.names.filter { !$0.isEmpty }))
            }
            switch note.kind {
            case .scriptsDropped:
                add(true, "Scripts in \(requests) are not imported. Raccoon runs no pre-request or test scripts.")
            case .authNotSupported(let type):
                add(true, "\(requests) \(one ? "uses" : "use") \(authName(type)) and \(one ? "is" : "are") imported with no Auth.")
            case .authInherited:
                add(false, "Auth inherited from Folders is copied onto \(requests).")
            case .binaryBody:
                add(true, "\(requests) \(one ? "has" : "have") a binary body and \(one ? "is" : "are") imported with no body.")
            case .pathVariable:
                add(false, "Path variables are written into the URL of \(requests).")
            case .pathVariableEmpty(let name):
                add(true, ":\(name) has no value in \(requests), so it stays in the URL as typed.")
            case .dynamicVariable(let name):
                if dynamic == nil {
                    dynamic = (lines.count, [], [])
                    add(true, "")
                }
                dynamic?.variables.append("{{\(name)}}")
                for request in note.names where !(dynamic?.names.contains(request) ?? true) { dynamic?.names.append(request) }
            case .fileOnlyName(let path):
                add(true, "The file “\(path)” in \(requests) has only a name, so \(one ? "it won't" : "they won't") send until you pick it again.")
            case .examplesDropped:
                add(true, "Saved examples in \(requests) are not imported.")
            case .descriptionsDropped:
                add(true, "\(plural(n, "description")) \(one ? "is" : "are") not imported. Raccoon keeps no descriptions.")
            case .itemsSkipped:
                add(true, one ? "1 Postman item that is neither a Request nor a Folder is skipped."
                    : "\(number(n)) Postman items that are neither a Request nor a Folder are skipped.")
            case .variableNameInvalid:
                add(true, one ? "1 Variable is not imported: its name can't be used as {{name}}."
                    : "\(number(n)) Variables are not imported: their names can't be used as {{name}}.")
            case .collectionVariables:
                add(false, "Collection variables of \(plural(n, "Collection")) are added to Globals.")
            case .renamed, .globalSkipped:
                break
            }
        }
        if let (line, variables, names) = dynamic {
            let listed = variables.count == 1 ? variables[0] : variables.dropLast().joined(separator: ", ") + " and " + variables[variables.count - 1]
            let those = names.count == 1 ? "that Request won't" : "those Requests won't"
            lines[line].text = variables.count == 1
                ? "\(listed) in \(plural(names.count, "Request")) is a Postman dynamic variable. It stays undefined, so \(those) send until you replace it."
                : "\(listed) in \(plural(names.count, "Request")) are Postman dynamic variables. They stay undefined, so \(those) send until you replace them."
            lines[line].names = names
        }
        return lines
    }

    /// As many names as fit `width` on one line, then "and N more". At least one name: the label
    /// cuts a long one in the middle, so the count stays readable.
    static func namesLine(_ names: [String], width: CGFloat, measure: (String) -> CGFloat) -> String {
        for shown in stride(from: names.count, through: 1, by: -1) {
            let rest = names.count - shown
            let line = names.prefix(shown).joined(separator: " · ") + (rest == 0 ? "" : " and \(number(rest)) more")
            if shown == 1 || measure(line) <= width { return line }
        }
        return ""
    }

    private static func authName(_ type: String) -> String {
        switch type {
        case "oauth2": "OAuth 2.0"
        case "oauth1": "OAuth 1.0"
        case "digest": "Digest"
        case "awsv4": "AWS Signature"
        case "ntlm": "NTLM"
        case "jwt": "JWT"
        case "hawk": "Hawk"
        case "akamai", "edgegrid": "Akamai EdgeGrid"
        default: type
        }
    }

    // MARK: Import

    /// The ticked files' plan, written. Throws when the Data Folder refuses before anything is
    /// written; the footer then says why.
    func importTicked() throws(StoreError) -> Outcome {
        let plan = plan
        // Before writing: afterwards an empty name's fallback is taken by itself.
        let planned = plan.collections.map { window.importName(ofCollection: $0.name) }
            + plan.environments.map { window.importName(ofEnvironment: $0.name) } + (plan.globals.isEmpty ? [] : ["Globals"])
        return Self.outcome(try window.importPostman(plan), planned: planned)
    }

    /// `planned` is every Collection, Environment and Globals of the plan, by the name written.
    static func outcome(_ result: ImportResult, planned: [String]) -> Outcome {
        var failed: Set<String> = []
        var lines: [Outcome.Line] = []
        for problem in result.problems {
            switch problem {
            case .collectionUnwritable(let name, let error), .environmentUnwritable(let name, let error):
                failed.insert(name)
                lines.append(.init(isFailure: true, text: "\(name) was not written: \(clause(error)). Nothing of it was left in the Data Folder."))
            case .globalsUnwritable(let error):
                failed.insert("Globals")
                lines.append(.init(isFailure: true, text: "Globals were not written: \(clause(error)). No Global was added."))
            case .secretNotStored(let name, let environment, _):
                lines.append(.init(isFailure: false, text: "The Keychain refused 1 secret (\(name.rawValue) in \(environment ?? "Globals")). It is imported with no value."))
            }
        }
        let landed = planned.filter { !failed.contains($0) }
        return Outcome(
            heading: "Imported \(number(landed.count)) of \(number(planned.count))",
            landed: landed.isEmpty ? nil : landed.joined(separator: " · "),
            lines: lines, reveal: result.collections.first, isComplete: result.problems.isEmpty
        )
    }

    /// A reason in the middle of a sentence: "the disk is full".
    private static func clause(_ error: StoreError) -> String {
        var reason = EnvironmentsSheet.reason(error)
        if reason.hasSuffix(".") { reason.removeLast() }
        return reason.prefix(1).lowercased() + reason.dropFirst()
    }

    private static func number(_ n: Int) -> String { n.formatted(.number.locale(Locale(identifier: "en"))) }

    private static func plural(_ n: Int, _ word: String) -> String { "\(number(n)) \(word)\(n == 1 ? "" : "s")" }
}

/// The Postman Import sheet (design-system §6, board 12): native, 620 pt wide, so system colours.
/// It shows the plan; Import writes it and either closes or shows the result.
final class PostmanImportSheet: NSViewController {
    static let width: CGFloat = 620
    /// The body's width inside the 18 pt margins.
    private static let bodyWidth = width - 36
    private static let noteNamesFont = NSFont.systemFont(ofSize: 11)

    let heading = NSTextField(labelWithString: "Import from Postman")
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let importButton = NSButton(title: "Import", target: nil, action: nil)
    let doneButton = NSButton(title: "Done", target: nil, action: nil)
    let footerLabel = NSTextField(labelWithString: "")
    private(set) var rowViews: [ImportRowView] = []
    let notesHeading = NSTextField(labelWithString: "What won't come across")
    let notesStack = NSStackView()
    private let body = NSStackView()
    private let scroll = NSScrollView()
    private lazy var scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 0)

    private var model: PostmanImport
    private let onImported: (String?) -> Void

    /// `onImported` runs when the sheet closes after Import, with the Collection to select.
    init(model: PostmanImport, onImported: @escaping (String?) -> Void) {
        self.model = model
        self.onImported = onImported
        super.init(nibName: nil, bundle: nil)
        title = "Import from Postman"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// After the open panel. A sheet still ending on `parent` queues this one behind it.
    static func present(on parent: NSWindow, files: [PickedFile], window: WindowModel, onImported: @escaping (String?) -> Void) {
        let sheet = PostmanImportSheet(model: PostmanImport(files: files, window: window), onImported: onImported)
        let restore = EnvironmentsSheet.rememberFocus(in: parent)
        // surfaces.md §8: Cancel gives focus back; after Import the sidebar takes it.
        parent.beginSheet(sheetPanel(sheet, focus: sheet.importButton)) { response in
            if response == .cancel { restore() }
        }
    }

    // MARK: Layout

    override func loadView() {
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        notesHeading.font = .systemFont(ofSize: 11, weight: .semibold)
        notesHeading.textColor = .secondaryLabelColor
        notesStack.orientation = .vertical
        notesStack.alignment = .leading
        notesStack.spacing = 6

        let list = NSBox()
        list.boxType = .custom
        list.cornerRadius = 6
        list.borderWidth = 0.5
        list.borderColor = .separatorColor
        list.fillColor = .controlBackgroundColor
        list.contentViewMargins = .zero
        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.spacing = 0
        for (index, row) in model.rows.enumerated() {
            if index > 0 { rowsStack.addArrangedSubview(Self.separator()) }
            let view = ImportRowView(row: row)
            view.checkbox.tag = index
            view.checkbox.target = self
            view.checkbox.action = #selector(tick(_:))
            rowsStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            rowViews.append(view)
        }
        list.contentView = rowsStack

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(list)
        body.addArrangedSubview(notesHeading)
        body.addArrangedSubview(notesStack)
        list.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        let document = FlippedView()
        document.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: document.topAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            body.widthAnchor.constraint(equalToConstant: Self.bodyWidth),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        // One line: a long path or reason is cut in the middle, and the tooltip has it whole.
        footerLabel.cell?.usesSingleLineMode = true
        footerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        importButton.keyEquivalent = "\r"
        importButton.target = self
        importButton.action = #selector(importFiles)
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.isHidden = true
        let rule = NSBox()
        rule.boxType = .separator

        let view = NSView()
        for child in [heading, scroll, rule, footerLabel, cancelButton, importButton, doneButton] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Self.width),
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            scrollHeight,
            rule.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 16),
            rule.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            importButton.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 12),
            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            importButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: importButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: importButton.leadingAnchor, constant: -8),
            doneButton.centerYAnchor.constraint(equalTo: importButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footerLabel.centerYAnchor.constraint(equalTo: importButton.centerYAnchor),
            footerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12),
        ])
        self.view = view
        render()
    }

    private static func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    /// Rows, notes and footer from the model; the body grows until 440 pt, then scrolls.
    private func render() {
        for (view, row) in zip(rowViews, model.rows) { view.show(row) }
        notesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let notes = model.notes
        for note in notes {
            let names = PostmanImport.namesLine(note.names, width: Self.bodyWidth - 22) { text in
                NSAttributedString(string: text, attributes: [.font: Self.noteNamesFont]).size().width
            }
            notesStack.addArrangedSubview(NoteView(
                glyph: note.isWarning ? .warning : .info, text: note.text, names: names, width: Self.bodyWidth,
                allNames: note.names.joined(separator: " · ")
            ))
        }
        notesHeading.isHidden = notes.isEmpty
        notesStack.isHidden = notes.isEmpty
        let footer = NSMutableAttributedString(attributedString: mono(model.footer.ranges(of: model.folder), in: model.footer, size: 11, color: .secondaryLabelColor))
        let oneLine = NSMutableParagraphStyle()
        oneLine.lineBreakMode = .byTruncatingMiddle
        footer.addAttribute(.paragraphStyle, value: oneLine, range: NSRange(location: 0, length: footer.length))
        footerLabel.attributedStringValue = footer
        footerLabel.toolTip = model.footer
        importButton.isEnabled = model.canImport
        fitScroll()
    }

    private func fitScroll() {
        body.layoutSubtreeIfNeeded()
        scrollHeight.constant = min(body.fittingSize.height, 440)
        // Past 440 pt the body scrolls: show the scroller once so that is not a surprise.
        if body.fittingSize.height > 440 { scroll.flashScrollers() }
    }

    @objc private func tick(_ sender: NSButton) {
        model.isTicked[sender.tag] = sender.state == .on
        render()
    }

    // MARK: Cancel, Import, Done

    @objc private func cancel() {
        close(.cancel)
    }

    @objc private func importFiles() {
        do throws(StoreError) {
            let outcome = try model.importTicked()
            if outcome.isComplete {
                close(.OK)
                return onImported(outcome.reveal)
            }
            show(outcome)
        } catch {
            // Refused before anything was written.
            model.writeProblem = EnvironmentsSheet.reason(error)
            render()
        }
    }

    @objc private func done() {
        close(.OK)
        onImported(revealed)
    }

    private var revealed: String?

    /// The same sheet, replaced: a check line for what landed, a line per problem, and Done.
    private func show(_ outcome: PostmanImport.Outcome) {
        revealed = outcome.reveal
        heading.stringValue = outcome.heading
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        body.spacing = 8
        if let landed = outcome.landed {
            body.addArrangedSubview(NoteView(glyph: .landed, text: landed, names: "", width: Self.bodyWidth))
        }
        for line in outcome.lines {
            body.addArrangedSubview(NoteView(glyph: line.isFailure ? .failed : .warning, text: line.text, names: "", width: Self.bodyWidth))
        }
        for button in [cancelButton, importButton] {
            button.isHidden = true
            button.keyEquivalent = ""
        }
        footerLabel.isHidden = true
        doneButton.isHidden = false
        fitScroll()
    }

    private func close(_ response: NSApplication.ModalResponse) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel, returnCode: response) }
    }
}

/// One picked file (design-system §6): checkbox, kind glyph, name over what it holds, and the
/// source file on the trailing edge. 38 pt at least.
final class ImportRowView: NSView {
    let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let glyph = NSImageView()
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let source = NSTextField(labelWithString: "")

    init(row: PostmanImport.Row) {
        super.init(frame: .zero)
        glyph.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        glyph.contentTintColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        source.font = .systemFont(ofSize: 11)
        source.textColor = .secondaryLabelColor
        source.alignment = .right
        for label in [title, detail, source] {
            label.lineBreakMode = .byTruncatingTail
            label.cell?.truncatesLastVisibleLine = true
        }
        // The name and what it holds yield first; the file name only past half the row.
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        source.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        source.setContentHuggingPriority(.required, for: .horizontal)
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for child in [checkbox, glyph, text, source] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            glyph.widthAnchor.constraint(equalToConstant: 18),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 8),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            source.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 8),
            source.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            source.centerYAnchor.constraint(equalTo: centerYAnchor),
            source.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.5),
        ])
        show(row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ row: PostmanImport.Row) {
        let symbol = switch row.kind {
        case .collection: "square.3.layers.3d"
        case .environment: "curlybraces"
        case .globals: "globe"
        case .other: "doc"
        }
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        checkbox.state = row.isTicked ? .on : .off
        checkbox.isEnabled = row.isEnabled
        checkbox.setAccessibilityLabel(row.title)
        title.stringValue = row.title
        title.font = .systemFont(ofSize: 13, weight: row.isEnabled ? .semibold : .regular)
        title.textColor = row.isEnabled ? .labelColor : .secondaryLabelColor
        title.toolTip = row.title
        detail.stringValue = row.detail
        detail.toolTip = row.detail
        source.stringValue = row.source
        source.toolTip = row.source
    }
}

/// A note or a result line: a 14 pt glyph, the sentence wrapping, and under it the names it
/// applies to on one 11 pt line.
private final class NoteView: NSView {
    enum Glyph { case warning, info, landed, failed }

    /// `allNames` is the tooltip of the names line: every name, where the line has room for some.
    init(glyph: Glyph, text: String, names: String, width: CGFloat, allNames: String = "") {
        super.init(frame: .zero)
        let (symbol, color): (String, NSColor) = switch glyph {
        case .warning: ("exclamationmark.triangle", .systemOrange)
        case .info: ("info.circle", .secondaryLabelColor)
        case .landed: ("checkmark", .labelColor)
        case .failed: ("exclamationmark.circle", .systemRed)
        }
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        image.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        image.contentTintColor = color
        let sentence = NSTextField(wrappingLabelWithString: "")
        sentence.attributedStringValue = mono(text.matches(of: /\{\{[^{}]*\}\}/).map(\.range), in: text, size: 12, color: .labelColor)
        sentence.preferredMaxLayoutWidth = width - 22
        let column = NSStackView(views: [sentence])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        if !names.isEmpty {
            let line = NSTextField(labelWithString: names)
            line.font = .systemFont(ofSize: 11)
            line.textColor = .secondaryLabelColor
            line.lineBreakMode = .byTruncatingMiddle
            line.toolTip = allNames
            line.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            column.addArrangedSubview(line)
        }
        for child in [image, column] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            image.leadingAnchor.constraint(equalTo: leadingAnchor),
            image.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            image.widthAnchor.constraint(equalToConstant: 16),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// `text` in the system font, with `code` in SF Mono, as board 12 sets a path and a `{{name}}`.
private func mono(_ code: [Range<String.Index>], in text: String, size: CGFloat, color: NSColor) -> NSAttributedString {
    let styled = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
    for range in code {
        styled.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), range: NSRange(range, in: text))
    }
    return styled
}
