import Foundation

/// One row of a Dropdown's list (design-system §6 Dropdown). An option is a choice and shows the
/// check when chosen; an action runs something and never becomes the title.
enum DropdownEntry: Equatable {
    case option(id: String, title: String, detail: String?, isChosen: Bool)
    case separator
    case action(id: String, title: String)

    var isPickable: Bool {
        if case .separator = self { return false }
        return true
    }

    /// What the trigger shows: the chosen option's title.
    static func title(of entries: [DropdownEntry]) -> String {
        for case let .option(_, title, _, isChosen) in entries where isChosen { return title }
        return ""
    }
}

enum DropdownPick: Equatable {
    case option(String)
    case action(String)
}

/// The highlight of an open list: which row ↑ ↓ and the pointer are on, and what Return picks.
struct DropdownList {
    enum Step { case up, down }

    let entries: [DropdownEntry]
    private(set) var highlighted: Int?

    /// Opens on the chosen option, else on the first row that can be picked.
    init(entries: [DropdownEntry]) {
        self.entries = entries
        highlighted = entries.firstIndex { if case .option(_, _, _, true) = $0 { true } else { false } }
            ?? entries.firstIndex { $0.isPickable }
    }

    /// Skips separators and stops at the ends.
    mutating func move(_ step: Step) {
        guard let current = highlighted else { return }
        let next = switch step {
        case .down: entries.indices.dropFirst(current + 1).first { entries[$0].isPickable }
        case .up: entries.indices.prefix(current).last { entries[$0].isPickable }
        }
        highlighted = next ?? current
    }

    /// The pointer; a separator or a row past the end leaves the highlight where it was.
    mutating func highlight(_ index: Int) {
        if entries.indices.contains(index), entries[index].isPickable { highlighted = index }
    }

    func pick() -> DropdownPick? {
        guard let highlighted else { return nil }
        switch entries[highlighted] {
        case let .option(id, _, _, _): return .option(id)
        case let .action(id, _): return .action(id)
        case .separator: return nil
        }
    }
}
