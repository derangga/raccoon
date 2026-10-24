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
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path), secrets: InMemorySecretStore(),
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
        let controller = MainWindowController(theme: theme, inspector: InspectorMemory(), reduceMotion: { true })
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

    @Test func `Remove from List is offered only when another Workspace is listed`() throws {
        let error = StoreError.unreadable(path: "/x", reason: "gone")
        #expect(DataFolderBanner.content(for: error, canRemove: false)?.buttons.map(\.title) == ["Open Workspace…"])
        let both = DataFolderBanner.content(for: error, canRemove: true)?.buttons
        #expect(both?.map(\.title) == ["Remove from List", "Open Workspace…"])
        #expect(both?.map(\.isPrimary) == [false, true])
    }

    @Test func `Remove from List forgets the unreadable Workspace and opens the other`() async throws {
        let (gone, other) = (temp.appending(path: "gone"), temp.appending(path: "other"))
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let model = WindowModel(
            dataFolder: DataFolderLocation(root: gone.path, workspaces: [gone.path, other.path], open: { DiskDataFolderStore(root: URL(filePath: $0)) }, remember: { _ in }),
            folderWatch: ManualFolderWatch(), sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: gone.path),
            secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        model.loadDataFolder()
        let banner = BannerView(theme: theme, reduceMotion: { true })
        let binding = DataFolderBannerBinding(window: model, banner: banner, chooseFolder: { nil })
        #expect(banner.content?.buttons.map(\.title) == ["Remove from List", "Open Workspace…"])

        banner.onButton?(0)
        await settle()

        #expect(model.workspaces == [other.path])
        #expect(model.dataFolderRoot == other.path)
        #expect(banner.content == nil)
        withExtendedLifetime(binding) {}
    }

    @Test func `a read-only Data Folder shows the banner; Open Workspace… loads another and hides it`() async throws {
        let root = try readOnlyRoot()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let model = makeWindow(root: root)
        model.loadDataFolder()
        let banner = BannerView(theme: theme, reduceMotion: { true })
        let chosen = temp.appending(path: "Writable")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
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
