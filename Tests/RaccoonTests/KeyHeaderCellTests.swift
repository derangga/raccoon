import AppKit
@testable import Raccoon
import Testing

@MainActor
struct KeyHeaderCellTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    /// NSCell's copy is bitwise: the copy must retain what the cell holds, or it releases it once too often.
    @Test func `a copy of a header cell retains its theme`() {
        let cell = KeyHeaderCell(theme: theme, ruleBefore: true)
        let before = CFGetRetainCount(theme)
        let copy = cell.copy()
        #expect(CFGetRetainCount(theme) == before + 1)
        _ = copy
    }
}
