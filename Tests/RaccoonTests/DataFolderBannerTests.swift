import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct DataFolderBannerTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")

    func makeWindow(root: URL) -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support")), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func readOnlyRoot() throws -> URL {
        let root = temp.appending(path: "ReadOnly")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        return root
    }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func `the banner spans the window above the sidebar and the content`() throws {
        let controller = MainWindowController(theme: theme, reduceMotion: { true })
        let window = try #require(controller.window)
        controller.banner.show(try #require(DataFolderBanner.content(for: .unwritable(path: "/x", reason: ""))), animated: false)
        window.layoutIfNeeded()

        let banner = controller.banner.convert(controller.banner.bounds, to: nil)
        let split = controller.split.view.convert(controller.split.view.bounds, to: nil)
        #expect(banner.width == window.contentLayoutRect.width)
        #expect(banner.height == 36)
        #expect(banner.minY == split.maxY)
        #expect(banner.maxY == window.contentLayoutRect.maxY)
    }

    @Test func `a read-only Data Folder shows the banner; Choose Folder… loads another and hides it`() async throws {
        let root = try readOnlyRoot()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let model = makeWindow(root: root)
        model.loadDataFolder()
        let banner = BannerView(theme: theme, reduceMotion: { true })
        let chosen = temp.appending(path: "Writable")
        let binding = DataFolderBannerBinding(window: model, banner: banner, chooseFolder: { chosen.path })

        #expect(!banner.isHidden)
        #expect(banner.content?.lead == "Raccoon can't write to the Data Folder.")

        banner.onButton?(0)
        await settle()

        #expect(model.dataFolderError == nil)
        #expect(banner.content == nil)
        withExtendedLifetime(binding) {}
    }

    @Test func `cancelling the panel changes nothing`() async throws {
        let root = try readOnlyRoot()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let model = makeWindow(root: root)
        model.loadDataFolder()
        let banner = BannerView(theme: theme, reduceMotion: { true })
        let binding = DataFolderBannerBinding(window: model, banner: banner, chooseFolder: { nil })

        banner.onButton?(0)
        await settle()

        #expect(model.dataFolderError != nil)
        #expect(!banner.isHidden)
        withExtendedLifetime(binding) {}
    }
}
