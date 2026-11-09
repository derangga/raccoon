@testable import Raccoon
import Testing

/// The keyboard and pick rules of the Dropdown's list, over entries alone.
@MainActor
struct DropdownListTests {
    static let entries: [DropdownEntry] = [
        .option(id: "a", title: "A", detail: nil, isChosen: false),
        .option(id: "b", title: "B", detail: nil, isChosen: true),
        .option(id: "c", title: "C", detail: nil, isChosen: false),
        .separator,
        .action(id: "new", title: "New…"),
    ]

    @Test func `it opens on the chosen option, else on the first row you can pick`() {
        #expect(DropdownList(entries: Self.entries).highlighted == 1)

        let none: [DropdownEntry] = [.separator, .option(id: "a", title: "A", detail: nil, isChosen: false), .action(id: "x", title: "X")]
        #expect(DropdownList(entries: none).highlighted == 1)
    }

    @Test func `down and up skip separators and stop at the ends`() {
        var list = DropdownList(entries: Self.entries)
        list.move(.down)
        #expect(list.highlighted == 2)
        list.move(.down)
        #expect(list.highlighted == 4)
        list.move(.down)
        #expect(list.highlighted == 4)
        list.move(.up)
        #expect(list.highlighted == 2)
        list.move(.up)
        list.move(.up)
        list.move(.up)
        #expect(list.highlighted == 0)
    }

    @Test func `pick answers the highlighted row as an option or an action`() {
        var list = DropdownList(entries: Self.entries)
        #expect(list.pick() == .option("b"))
        list.highlight(4)
        #expect(list.pick() == .action("new"))
    }

    @Test func `the pointer highlights only rows you can pick`() {
        var list = DropdownList(entries: Self.entries)
        list.highlight(3)
        #expect(list.highlighted == 1)
        list.highlight(99)
        #expect(list.highlighted == 1)
        list.highlight(0)
        #expect(list.highlighted == 0)
    }

    @Test func `a list of separators has nothing to highlight or pick`() {
        var list = DropdownList(entries: [.separator])
        #expect(list.highlighted == nil)
        list.move(.down)
        #expect(list.highlighted == nil)
        #expect(list.pick() == nil)
    }

    @Test func `the title is the chosen option's, empty when none is chosen`() {
        #expect(DropdownEntry.title(of: Self.entries) == "B")
        #expect(DropdownEntry.title(of: [.action(id: "x", title: "X")]) == "")
    }
}
