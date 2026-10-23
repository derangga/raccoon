import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

struct BannerMotionTests {
    @Test(arguments: [
        (true, false, 0.2, true),
        (false, false, 0.15, true),
        (true, true, 0.15, false),
        (false, true, 0.15, false),
    ])
    func `a banner grows in 200 ms and leaves in 150 ms; Reduce Motion fades only`(
        appearing: Bool, reduceMotion: Bool, duration: Double, animatesHeight: Bool
    ) {
        let motion = BannerMotion(appearing: appearing, reduceMotion: reduceMotion)
        #expect(motion.duration == duration)
        #expect(motion.animatesHeight == animatesHeight)
    }
}

@MainActor
struct BannerViewTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    func banner(_ content: Banner, width: CGFloat) -> BannerView {
        let view = BannerView(theme: theme, reduceMotion: { true })
        view.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        view.show(content, animated: false)
        view.frame.size.height = view.height(forWidth: width)
        view.layoutSubtreeIfNeeded()
        return view
    }

    static let readOnly = DataFolderBanner.content(for: .unwritable(path: NSHomeDirectory() + "/Raccoon", reason: "x"))

    @Test func `the Data Folder banner reads as board 09`() throws {
        let content = try #require(Self.readOnly)
        #expect(content.glyph == .error)
        #expect(content.lead == "Raccoon can't write to the Data Folder.")
        #expect(content.detail == [.text(" "), .code("~/Raccoon"), .text(" is read-only. Collections are unavailable; Drafts and sending still work.")])
        #expect(content.buttons == [Banner.Button(title: "Open Workspace…", isPrimary: true)])
    }

    @Test func `an unreadable folder says it can't be read, with the reason`() throws {
        let content = try #require(DataFolderBanner.content(for: .unreadable(path: "/Volumes/X/Raccoon", reason: "Permission denied.")))
        #expect(content.lead == "Raccoon can't read the Data Folder.")
        #expect(content.detail == [.text(" "), .code("/Volumes/X/Raccoon"), .text(" can't be read: Permission denied. Collections are unavailable; Drafts and sending still work.")])
    }

    @Test func `one line is 36 pt, and the button gets the width its title needs`() throws {
        let view = banner(try #require(Self.readOnly), width: 1_400)
        #expect(view.frame.height == 36)
        let button = try #require(view.buttons.first)
        #expect(button.frame.width >= (button.cell?.cellSize.width ?? 0))
        #expect(button.frame.height == 24)
        #expect(button.frame.maxX == 1_388)
    }

    @Test func `break-ui: a long path wraps to two lines without clipping the button`() throws {
        let path = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/Work/Clients/Northwind/API Collections/Raccoon"
        let view = banner(try #require(DataFolderBanner.content(for: .unwritable(path: path, reason: "x"))), width: 760)
        let line = NSFont.systemFont(ofSize: 13).boundingRectForFont.height
        #expect(view.text.frame.height > line * 1.5)
        #expect(view.frame.height == view.text.frame.height + 12)
        let button = try #require(view.buttons.first)
        #expect(button.frame.width >= (button.cell?.cellSize.width ?? 0))
        #expect(button.frame.maxX <= 760 - 12)
        #expect(view.text.frame.maxX <= button.frame.minX - 8)
    }

    @Test func `hidden, it takes no height`() throws {
        let view = banner(try #require(Self.readOnly), width: 800)
        view.hide(animated: false)
        #expect(view.height(forWidth: 800) == 0)
        #expect(view.isHidden)
    }
}
