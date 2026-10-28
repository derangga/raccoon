import AppKit
@testable import Raccoon
import Testing

/// Where each row's first element sits in the outline: one leading edge per level, whatever the row is.
@MainActor
struct SidebarLayoutTests {
    let base = SidebarTests()

    enum Row: Equatable { case collection, folder, request, unreadable }

    /// Every name has an "o" so one query keeps all of them in the filter view.
    /// Sociolla (0) > Top (1), Bad.json (1), Zalo Vietguy (1) > Get Zalo, Send SMS, Lookup, Broken.json (2),
    /// Photos (2) > Old shot, Old broken.json (3), Logos (3). Beauty Journal (1) is empty.
    func tree() throws -> SidebarViewController {
        try base.put("Top", at: "Sociolla/Top.json")
        try base.write(Data("nope".utf8), at: "Sociolla/Bad.json")
        try base.put("Get Zalo", at: "Sociolla/Zalo Vietguy/Get Zalo.json")
        try base.put("Send SMS", method: "POST", at: "Sociolla/Zalo Vietguy/Send SMS.json")
        try base.put("Lookup", method: "PROPFIND", at: "Sociolla/Zalo Vietguy/Lookup.json")
        try base.write(Data("nope".utf8), at: "Sociolla/Zalo Vietguy/Broken.json")
        try base.put("Old shot", at: "Sociolla/Zalo Vietguy/Photos/Old shot.json")
        try base.write(Data("nope".utf8), at: "Sociolla/Zalo Vietguy/Photos/Old broken.json")
        try FileManager.default.createDirectory(at: base.root.appending(path: "Sociolla/Zalo Vietguy/Photos/Logos"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.root.appending(path: "Sociolla/Beauty Journal"), withIntermediateDirectories: true)
        return base.sidebar(base.makeWindow())
    }

    /// The expected (kind, level) of every row, by name.
    static let expected: [String: (Row, Int)] = [
        "Sociolla": (.collection, 0),
        "Zalo Vietguy": (.folder, 1), "Beauty Journal": (.folder, 1), "Photos": (.folder, 2), "Logos": (.folder, 3),
        "Top": (.request, 1), "Get Zalo": (.request, 2), "Send SMS": (.request, 2), "Lookup": (.request, 2), "Old shot": (.request, 3),
        "Bad.json": (.unreadable, 1), "Broken.json": (.unreadable, 2), "Old broken.json": (.unreadable, 3),
    ]

    struct Frames {
        let name: String
        let kind: Row
        let level: Int
        /// The first element's leading edge, in the outline's coordinates.
        let edge: CGFloat
        /// The name field's frame, in the outline's coordinates.
        let nameFrame: NSRect
        let cell: NSView
    }

    func frames(_ sidebar: SidebarViewController) throws -> [Frames] {
        let outline = sidebar.outline
        var result: [Frames] = []
        for row in 0..<outline.numberOfRows {
            let item = try #require(outline.item(atRow: row) as? SidebarItem)
            let view = try #require(outline.view(atColumn: 0, row: row, makeIfNecessary: true))
            // A label keeps 2 pt of padding each side: its text starts 2 pt right of its frame.
            let (kind, first, name): (Row, NSRect, NSTextField)
            switch view {
            case let cell as NodeCell: (kind, first, name) = (item.kind == .collection ? .collection : .folder, cell.glyph.frame, cell.name)
            case let cell as RequestCell: (kind, first, name) = (.request, Self.drawnBadge(cell.badge), cell.name)
            case let cell as UnreadableCell: (kind, first, name) = (.unreadable, cell.glyph.frame, cell.name)
            default: throw CellError.unexpected(row)
            }
            result.append(Frames(name: item.name, kind: kind, level: outline.level(forRow: row), edge: view.convert(first, to: outline).minX,
                                 nameFrame: view.convert(name.frame, to: outline), cell: view))
        }
        return result
    }

    /// Where the badge's text is drawn: the label's 2 pt padding in from its frame, on the side its alignment names.
    static func drawnBadge(_ badge: NSTextField) -> NSRect {
        let text = badge.attributedStringValue
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let width = text.size().width
        let x = style?.alignment == .right ? badge.frame.maxX - 2 - width : badge.frame.minX + 2
        return NSRect(x: x, y: badge.frame.minY, width: width, height: badge.frame.height)
    }

    enum CellError: Error { case unexpected(Int) }

    func expectEdges(_ rows: [Frames], collectionEdge: CGFloat) {
        for row in rows {
            let (kind, level) = Self.expected[row.name]!
            #expect(row.kind == kind && row.level == level, "\(row.name) is a \(row.kind) at level \(row.level), expected \(kind) at \(level)")
            let want = collectionEdge + 16 * CGFloat(level)
            #expect(row.edge == want, "\(row.name) (\(row.kind), level \(row.level)): first element at \(row.edge), expected \(want)")
        }
    }

    @Test func `a row's first element is 16 pt per level right of the Collection's, for every kind`() throws {
        let rows = try frames(try tree())
        #expect(rows.count == Self.expected.count)
        let collection = try #require(rows.first { $0.kind == .collection })
        expectEdges(rows, collectionEdge: collection.edge)
    }

    @Test func `GET and POST start at the same x, and so do the two names`() throws {
        let sidebar = try tree()
        let rows = try frames(sidebar)
        func request(_ name: String) throws -> Frames { try #require(rows.first { $0.name == name }) }
        let get = try request("Get Zalo"), send = try request("Send SMS")
        let getCell = try #require(get.cell as? RequestCell), sendCell = try #require(send.cell as? RequestCell)
        let outline = sidebar.outline
        #expect(getCell.convert(Self.drawnBadge(getCell.badge), to: outline).minX == sendCell.convert(Self.drawnBadge(sendCell.badge), to: outline).minX,
                "GET and POST badges are drawn at different x")
        #expect(get.nameFrame.minX == send.nameFrame.minX)
        #expect(get.nameFrame.minX + 2 - get.edge == 56, "a Request's name text starts \(get.nameFrame.minX + 2 - get.edge) pt after its leading edge")
    }

    @Test func `a Folder's name starts 20 pt after its leading edge`() throws {
        let rows = try frames(try tree())
        let folder = try #require(rows.first { $0.name == "Zalo Vietguy" })
        #expect(folder.nameFrame.minX - folder.edge == 20)
    }

    @Test func `PROPFIND's badge cell is no wider than its frame`() throws {
        let rows = try frames(try tree())
        let cell = try #require(rows.first { $0.name == "Lookup" }?.cell as? RequestCell)
        #expect(cell.badge.stringValue == "PROPFIND")
        #expect((cell.badge.cell?.cellSize.width ?? .infinity) <= cell.badge.frame.width)
    }

    @Test func `an Unreadable row's reason starts where its name does`() throws {
        let rows = try frames(try tree())
        let cell = try #require(rows.first { $0.name == "Broken.json" }?.cell as? UnreadableCell)
        #expect(cell.reason.frame.minX == cell.name.frame.minX)
    }

    @Test func `the filter view keeps the same edges`() throws {
        let sidebar = try tree()
        let collection = try #require(frames(sidebar).first { $0.kind == .collection })
        sidebar.searchField.stringValue = "o"
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sidebar.searchField))
        sidebar.view.layoutSubtreeIfNeeded()

        let rows = try frames(sidebar)
        #expect(Set(rows.map(\.name)).isSuperset(of: ["Sociolla", "Zalo Vietguy", "Get Zalo", "Lookup", "Broken.json", "Old shot", "Old broken.json"]))
        expectEdges(rows, collectionEdge: collection.edge)
    }
}
