import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

struct TabStripLayoutTests {
    @Test(arguments: [
        // count, selected index, width available, each Tab's width to 0.1 pt, scrolls
        (3, 0, 1_000.0, [196.0, 196, 196], false),
        (5, 0, 600.0, [168.0, 108, 108, 108, 108], false),
        (6, 5, 900.0, [146.4, 146.4, 146.4, 146.4, 146.4, 168], false),
        (6, 2, 600.0, [104.0, 104, 168, 104, 104, 104], true),
        (4, 1, 400.0, [104.0, 168, 104, 104], true),
    ])
    func `Tabs shrink from 196 pt to 104 pt, the selected one to 168 pt, then the strip scrolls`(
        count: Int, selected: Int, available: Double, widths: [Double], scrolls: Bool
    ) {
        let layout = TabStripLayout(count: count, selected: selected, available: available)
        #expect(layout.widths.map { Double(($0 * 10).rounded() / 10) } == widths)
        #expect(layout.scrolls == scrolls)
    }
}

@MainActor
struct TabStripViewTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let now = ContinuousClock.now
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(temp.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: temp.appending(path: "Raccoon").path), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(now),
            makeTab: { [now] in
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func strip(_ window: WindowModel, width: CGFloat = 1_000) -> TabStripView {
        let strip = TabStripView(window: window, theme: theme)
        strip.frame = NSRect(x: 0, y: 0, width: width, height: 34)
        strip.layoutSubtreeIfNeeded()
        return strip
    }

    func settle(_ strip: TabStripView) async {
        for _ in 0..<5 { await Task.yield() }
        strip.layoutSubtreeIfNeeded()
    }

    func requestTab(_ model: TabModel, url: String) {
        model.tab.definition.url = url
        model.tab.source = .request(RequestID(UUID()))
        model.tab.baseline = model.tab.definition
    }

    @Test func `one Tab per TabModel in order, the selected one marked, and a press selects`() async {
        let window = makeWindow()
        window.newTab()
        window.tabs[1].typeInURLBar("https://api.example.com/v1/webhooks")
        let strip = strip(window)
        #expect(strip.items.map(\.name.stringValue) == ["Draft", "/v1/webhooks"])
        #expect(strip.items.map(\.isSelected) == [false, true])

        _ = strip.items[0].accessibilityPerformPress()
        await settle(strip)
        #expect(window.selected == window.tabs[0].tab.id)
        #expect(strip.items.map(\.isSelected) == [true, false])

        strip.newTabButton.performClick(nil)
        await settle(strip)
        #expect(strip.items.count == 3)
        #expect(strip.items[1].isSelected)
    }

    @Test func `a Draft is italic, a Dirty Tab shows the dot, and hover swaps it for the close button`() async throws {
        let window = makeWindow()
        window.newTab()
        requestTab(window.tabs[1], url: "https://api.example.com/charges")
        window.tabs[1].tab.definition.method = "POST"
        let strip = strip(window)
        let (draft, dirty) = (strip.items[0], strip.items[1])

        #expect(NSFontManager.shared.traits(of: try #require(draft.name.font)).contains(.italicFontMask))
        #expect(!NSFontManager.shared.traits(of: try #require(dirty.name.font)).contains(.italicFontMask))
        #expect(draft.dot.isHidden && draft.closeButton.isHidden)
        #expect(!dirty.dot.isHidden && dirty.closeButton.isHidden)
        #expect(dirty.badge.stringValue == "POST")

        dirty.isHovered = true
        #expect(dirty.dot.isHidden && !dirty.closeButton.isHidden)
        draft.isHovered = true
        #expect(!draft.closeButton.isHidden)
    }

    @Test(arguments: ["GET", "DELETE", "OPTIONS", "PROPFIND"])
    func `the method badge shows the whole method`(method: String) throws {
        let window = makeWindow()
        window.tabs[0].tab.definition.method = method
        let badge = strip(window).items[0].badge
        let needed = try #require(badge.cell).cellSize.width
        #expect(badge.frame.width >= needed)
    }

    @Test func `a method longer than 64 pt end-truncates`() throws {
        let window = makeWindow()
        window.tabs[0].tab.definition.method = "MKCALENDAR-EXTENDED"
        #expect(strip(window).items[0].badge.frame.width == 64)
    }

    @Test func `a Draft has an accent dot before its badge, a Request Tab has none`() {
        let window = makeWindow()
        window.newTab()
        requestTab(window.tabs[1], url: "https://api.example.com/charges")
        let strip = strip(window)
        let (draft, request) = (strip.items[0], strip.items[1])

        #expect(!draft.draftDot.isHidden && request.draftDot.isHidden)
        #expect(draft.draftDot.frame.size == NSSize(width: 6, height: 6))
        #expect(draft.draftDot.frame.maxX <= draft.badge.frame.minX)
        #expect(draft.draftDot.layer?.backgroundColor == theme.color(.accent).cgColor)
    }

    @Test func `sending replaces the method badge with the spinner only after 150 ms`() async {
        let window = makeWindow()
        let strip = strip(window)
        let item = strip.items[0]
        window.tabs[0].tab.response = .sending(since: now)
        await settle(strip)
        #expect(item.spinner.isHidden && !item.badge.isHidden)

        window.tabs[0].tab.response = .sending(since: now - .milliseconds(200))
        await settle(strip)
        #expect(!item.spinner.isHidden && item.badge.isHidden)
    }

    @Test func `Changed on Disk shows the warning glyph before the badge, and the dot`() async {
        let window = makeWindow()
        requestTab(window.tabs[0], url: "https://api.example.com/charges/1")
        window.tabs[0].tab.definition.method = "PATCH"
        window.tabs[0].tab.isChangedOnDisk = true
        let strip = strip(window)
        let item = strip.items[0]
        #expect(!item.glyph.isHidden && !item.dot.isHidden)
        #expect(item.glyph.frame.maxX <= item.badge.frame.minX)
    }

    @Test func `each Tab is an accessibility tab titled by method and name, valued by its states`() async {
        let window = makeWindow()
        window.newTab()
        requestTab(window.tabs[1], url: "https://api.example.com/charges/1")
        window.tabs[1].tab.definition.method = "PATCH"
        window.tabs[1].tab.isChangedOnDisk = true
        window.tabs[1].tab.response = .sending(since: now)
        let strip = strip(window)

        #expect(strip.items[0].accessibilityRole() == .radioButton)
        #expect(strip.items[0].accessibilitySubrole() == .tabButtonSubrole)
        #expect(strip.items[0].accessibilityTitle() == "GET Draft")
        #expect(strip.items[0].accessibilityValue() as? String == "Draft")
        #expect(strip.items[1].accessibilityTitle() == "PATCH /charges/1")
        #expect(strip.items[1].accessibilityValue() as? String == "Edited, Sending, Changed on Disk")
        #expect(strip.accessibilityRole() == .tabGroup)
    }

    @Test func `30 Tabs scroll with fade masks, and the selected Tab is kept in view`() async throws {
        let window = makeWindow()
        for _ in 1..<30 { window.newTab() }
        let strip = strip(window, width: 800)
        #expect(strip.scrolls)
        #expect(strip.scrollView.layer?.mask != nil)
        #expect(strip.items.filter { !$0.isSelected }.allSatisfy { $0.frame.width == 104 })
        #expect(strip.items[29].frame.width == 168)
        let visible = { strip.scrollView.documentVisibleRect }
        #expect(visible().contains(strip.items[29].frame))

        window.select(number: 1)
        await settle(strip)
        #expect(visible().contains(strip.items[0].frame))
        #expect(!visible().contains(strip.items[29].frame))
    }

    @Test func `a few Tabs do not scroll and have no fade masks`() {
        let strip = strip(makeWindow())
        #expect(!strip.scrolls)
        #expect(strip.scrollView.layer?.mask == nil)
        #expect(strip.items[0].frame.width == 196)
    }

    @Test func `a Japanese and emoji name end-truncates, with the full name in the tooltip`() async {
        let window = makeWindow()
        let name = "/🦝 Webhooks テスト 🚀/請求書の一覧を取得する"
        window.tabs[0].typeInURLBar("https://api.example.com" + name)
        let strip = strip(window, width: 400)
        let item = strip.items[0]
        #expect(item.name.stringValue == name)
        #expect(item.name.lineBreakMode == .byTruncatingTail)
        #expect(item.toolTip == name)
        #expect(item.name.frame.width < item.name.intrinsicContentSize.width)
    }
}

@MainActor
struct ContentLayoutTests {
    @Test func `the tab strip sits 34 pt tall, the Breadcrumb 28 pt under it, then the selected Tab's editor`() {
        let window = TabStripViewTests().makeWindow()
        let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
        let tab = TabViewController(model: window.tabs[0], theme: theme)
        let content = ContentViewController(strip: TabStripView(window: window, theme: theme),
                                            breadcrumb: BreadcrumbBinding(window: window, theme: theme, select: { _ in }), tab: tab,
                                            banner: TabBannerBinding(window: window, theme: theme, reduceMotion: { true }),
                                            emptyState: EmptyStateView(theme: theme, menu: nil))
        content.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        content.view.layoutSubtreeIfNeeded()

        #expect(content.strip.frame == NSRect(x: 0, y: 566, width: 900, height: 34))
        #expect(content.breadcrumb.bar.frame == NSRect(x: 0, y: 538, width: 900, height: 28))
        #expect(tab.view.frame == NSRect(x: 0, y: 0, width: 900, height: 538))
    }
}
