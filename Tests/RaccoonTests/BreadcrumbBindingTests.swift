import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

@MainActor
struct BreadcrumbBindingTests {
    let folders = FolderOperationTests()
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    func crumbs(_ binding: BreadcrumbBinding) -> [CrumbView] {
        binding.bar.layoutSubtreeIfNeeded()
        return binding.bar.visibleCrumbs
    }

    func titles(_ binding: BreadcrumbBinding) -> [String] { crumbs(binding).map(\.title) }

    /// The window of FolderOperationTests with the charge Request open, and a binding over it.
    func make(select: @escaping (String) -> Void = { _ in }) throws -> (WindowModel, TabModel, BreadcrumbBinding) {
        let (window, tab) = try folders.setUp()
        let binding = BreadcrumbBinding(window: window, theme: theme, select: select)
        binding.bar.frame = NSRect(x: 0, y: 0, width: 900, height: BreadcrumbBar.height)
        binding.bar.layoutSubtreeIfNeeded()
        return (window, tab, binding)
    }

    @Test func `the selected Request Tab shows its Collection, Folders and name`() throws {
        let (_, _, binding) = try make()
        #expect(titles(binding) == ["Payments API", "Refunds", "Create charge"])
    }

    @Test func `a Draft shows its title alone, and follows the URL typed into it`() async throws {
        let (window, _, binding) = try make()
        window.newTab()
        await settle()
        #expect(titles(binding) == ["Draft"])
        #expect(crumbs(binding).first?.kind == .text)

        window.selectedTab?.tab.definition.url = "https://example.test/anything/webhooks"
        await settle()
        #expect(titles(binding) == ["/anything/webhooks"])
    }

    @Test func `selecting another Tab swaps the segments`() async throws {
        let (window, tab, binding) = try make()
        window.newTab()
        await settle()
        window.select(tab.tab.id)
        await settle()
        #expect(titles(binding) == ["Payments API", "Refunds", "Create charge"])
    }

    @Test func `renaming a Folder or a Request in the sidebar updates it with nothing done to the Tab`() async throws {
        let (window, _, binding) = try make()
        try window.rename("Payments API/Refunds", to: "Charges")
        await settle()
        #expect(titles(binding) == ["Payments API", "Charges", "Create charge"])

        try window.rename("Payments API/Charges/Create charge.json", to: "Charge a card")
        await settle()
        #expect(titles(binding) == ["Payments API", "Charges", "Charge a card"])
    }

    @Test func `a segment's click hands its path to select, a Draft's does nothing`() async throws {
        var paths: [String] = []
        let (window, _, binding) = try make { paths.append($0) }
        crumbs(binding)[1].onClick()
        crumbs(binding)[2].onClick()
        #expect(paths == ["Payments API/Refunds", folders.chargePath])

        window.newTab()
        await settle()
        crumbs(binding)[0].onClick()
        #expect(paths.count == 2)
    }

    @Test func `a file that becomes unreadable keeps its Breadcrumb, and its last segment still targets the file`() async throws {
        var paths: [String] = []
        let (window, _, binding) = try make { paths.append($0) }
        try Data("{".utf8).write(to: folders.root.appending(path: folders.chargePath))
        await folders.echo([folders.chargePath])
        #expect(window.index.path(of: FolderOperationTests.charge.id) == nil)
        #expect(titles(binding) == ["Payments API", "Refunds", "Create charge"])
        crumbs(binding)[2].onClick()
        #expect(paths == [folders.chargePath])
    }

    @Test func `the last known segments are kept per RequestID, and dropped when the Tab closes`() async throws {
        let (window, tab, binding) = try make()
        #expect(binding.lastKnown.keys.contains(FolderOperationTests.charge.id))

        window.newTab()
        window.close(tab.tab.id)
        await settle()
        #expect(binding.lastKnown.isEmpty)
    }

    @Test func `saving a Draft shows its full location at once`() async throws {
        let (window, _, binding) = try make()
        window.newTab()
        await settle()
        let id = try #require(window.selectedTab?.tab.id)
        window.selectedTab?.tab.definition.url = "https://example.test/hook"
        window.saveDraft(id, name: "Hook", in: .folder("Orders"))
        await settle()
        #expect(titles(binding) == ["Orders", "Hook"])
    }
}
