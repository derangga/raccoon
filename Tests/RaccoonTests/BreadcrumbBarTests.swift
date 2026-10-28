import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

@MainActor
struct BreadcrumbBarTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    static func nested(_ names: [String] = ["Sociolla", "Beauty Journal", "Article", "Retry Share Social Media"]) -> Breadcrumb {
        var path = ""
        return Breadcrumb(segments: names.enumerated().map { index, name in
            path += (path.isEmpty ? "" : "/") + name
            return BreadcrumbSegment(title: name, target: index == names.count - 1 ? path + ".json" : path)
        })
    }

    func makeBar(_ breadcrumb: Breadcrumb, width: CGFloat = 800, select: @escaping (String) -> Void = { _ in }) -> BreadcrumbBar {
        let bar = BreadcrumbBar(theme: theme, select: select)
        bar.frame = NSRect(x: 0, y: 0, width: width, height: BreadcrumbBar.height)
        bar.show(breadcrumb)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    func click(_ crumb: CrumbView, in window: NSWindow? = nil) throws {
        let point = NSPoint(x: crumb.bounds.midX, y: crumb.bounds.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: crumb.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            type == .leftMouseDown ? crumb.mouseDown(with: event) : crumb.mouseUp(with: event)
        }
    }

    @Test func `it is 28 pt high and shows one view per segment, with no ellipsis when all fit`() {
        let bar = makeBar(Self.nested())
        #expect(BreadcrumbBar.height == 28)
        #expect(bar.visibleCrumbs.map(\.title) == ["Sociolla", "Beauty Journal", "Article", "Retry Share Social Media"])
        #expect(bar.visibleCrumbs.allSatisfy { $0.frame.height == 22 && $0.frame.minY == 3 })
    }

    @Test func `segments run left to right, 12 pt in, with room for the chevron between`() {
        let crumbs = makeBar(Self.nested()).visibleCrumbs
        #expect(crumbs[0].frame.minX == 12)
        for (left, right) in zip(crumbs, crumbs.dropFirst()) { #expect(right.frame.minX - left.frame.maxX == 12) }
    }

    @Test func `a narrow bar collapses the middle into an ellipsis whose tooltip is the full path`() throws {
        let bar = makeBar(Self.nested(), width: 330)
        let titles = bar.visibleCrumbs.map(\.title)
        #expect(titles.first == "Sociolla" && titles.last == "Retry Share Social Media")
        let more = try #require(bar.visibleCrumbs.first { $0.kind == .more })
        #expect(more.title == "…")
        #expect(more.toolTip == "Sociolla › Beauty Journal › Article › Retry Share Social Media")
        #expect(more.accessibilityLabel() == "Beauty Journal › Article")
        #expect(more.accessibilityRole() == .staticText)
        let frames = bar.visibleCrumbs.map(\.frame)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX < $1.minX })
        #expect(frames.last!.maxX <= 330 - 12)
    }

    @Test func `widening the bar restores the middle`() {
        let bar = makeBar(Self.nested(), width: 330)
        bar.frame.size.width = 800
        bar.layoutSubtreeIfNeeded()
        #expect(bar.visibleCrumbs.count == 4 && bar.visibleCrumbs.allSatisfy { $0.kind != .more })
    }

    @Test func `a 120-character name end-truncates, with the full name in its tooltip`() throws {
        let long = String(repeating: "Retry ", count: 20)
        let bar = makeBar(Self.nested(["Sociolla", long]), width: 400)
        let last = try #require(bar.visibleCrumbs.last)
        #expect(last.frame.maxX <= 400 - 12)
        #expect(last.toolTip == long)
        #expect(bar.visibleCrumbs[0].toolTip == nil)
    }

    @Test func `a Collection name alone fills no more than the line`() throws {
        let bar = makeBar(Self.nested([String(repeating: "Wide ", count: 40)]), width: 300)
        let only = try #require(bar.visibleCrumbs.first)
        #expect(only.frame.minX == 12 && only.frame.maxX <= 300 - 12)
        #expect(only.toolTip != nil)
    }

    @Test func `Japanese and emoji names are measured whole, not clipped`() throws {
        let bar = makeBar(Self.nested(["PROPFIND 🦝 Webhooks テスト 🚀"]), width: 800)
        let crumb = try #require(bar.visibleCrumbs.first)
        #expect(crumb.toolTip == nil)
        #expect(crumb.frame.width >= crumb.textWidth + 12)
    }

    @Test func `a Draft's title is static text, not a button`() throws {
        let bar = makeBar(Breadcrumb(segments: [BreadcrumbSegment(title: "Draft", target: nil)]))
        let crumb = try #require(bar.visibleCrumbs.first)
        #expect(crumb.kind == .text)
        #expect(crumb.accessibilityRole() == .staticText)
    }

    @Test func `clicking a segment selects its target, the last one included, and a Draft's does nothing`() throws {
        var selected: [String] = []
        let bar = makeBar(Self.nested(), select: { selected.append($0) })
        try click(bar.visibleCrumbs[1])
        try click(bar.visibleCrumbs[3])
        #expect(selected == ["Sociolla/Beauty Journal", "Sociolla/Beauty Journal/Article/Retry Share Social Media.json"])

        selected = []
        let draft = makeBar(Breadcrumb(segments: [BreadcrumbSegment(title: "Draft", target: nil)]), select: { selected.append($0) })
        try click(draft.visibleCrumbs[0])
        #expect(selected.isEmpty)
    }

    @Test func `a click does not move keyboard focus and no segment can take it`() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let field = NSTextField(frame: NSRect(x: 0, y: 100, width: 200, height: 24))
        let bar = makeBar(Self.nested())
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(bar)
        window.makeFirstResponder(field)
        let before = window.firstResponder
        try click(bar.visibleCrumbs[0], in: window)
        #expect(window.firstResponder === before)
        #expect(bar.visibleCrumbs.allSatisfy { !$0.acceptsFirstResponder && $0.focusRingType == .none })
    }

    @Test func `hover fills a button segment and leaving clears it; static text never hovers`() throws {
        let bar = makeBar(Self.nested())
        let crumb = bar.visibleCrumbs[0]
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                        windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        crumb.mouseEntered(with: enter)
        #expect(crumb.isHovered)
        crumb.mouseExited(with: enter)
        #expect(!crumb.isHovered)

        let draft = makeBar(Breadcrumb(segments: [BreadcrumbSegment(title: "Draft", target: nil)])).visibleCrumbs[0]
        draft.mouseEntered(with: enter)
        #expect(!draft.isHovered)
    }

    @Test func `the row is a Location group, each segment a button labelled by name, the last selected`() throws {
        let bar = makeBar(Self.nested())
        #expect(bar.accessibilityRole() == .group)
        #expect(bar.accessibilityLabel() == "Location")
        let crumbs = bar.visibleCrumbs
        #expect(crumbs.map { $0.accessibilityRole() } == Array(repeating: .button, count: 4))
        #expect(crumbs.map { $0.accessibilityLabel() ?? "" } == ["Sociolla", "Beauty Journal", "Article", "Retry Share Social Media"])
        #expect(crumbs.map { $0.isAccessibilitySelected() } == [false, false, false, true])
    }

    @Test func `showing a new Breadcrumb replaces the segments`() {
        let bar = makeBar(Self.nested())
        bar.show(Breadcrumb(segments: [BreadcrumbSegment(title: "Draft", target: nil)]))
        bar.layoutSubtreeIfNeeded()
        #expect(bar.visibleCrumbs.map(\.title) == ["Draft"])
        #expect(bar.subviews.filter { !$0.isHidden }.count == 1)
    }
}
