import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Switching, opening and removing Workspaces over live stores in a temp dir.
@MainActor
struct WorkspaceSwitchTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let watch = ManualFolderWatch()
    let transport = ScriptedTransport(.failure(.timedOut))
    var a: URL { temp.appending(path: "a") }
    var b: URL { temp.appending(path: "b") }

    final class Remembered {
        var root: [String] = []
        var list: [[String]] = []
    }

    func makeWindow(open: URL, listed: [URL], remembered: Remembered = Remembered()) -> WindowModel {
        for folder in listed { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return WindowModel(
            dataFolder: DataFolderLocation(
                root: open.path, workspaces: listed.map(\.path), open: { DiskDataFolderStore(root: URL(filePath: $0)) },
                remember: { remembered.root.append($0) }, rememberWorkspaces: { remembered.list.append($0) }),
            folderWatch: watch, sessionStore: { [temp] in DiskSessionStore(directory: temp.appending(path: "Support"), root: $0) },
            secrets: { _ in InMemorySecretStore() }, instants: FixedInstantSource(.now),
            makeTab: { [transport] secrets in
                TabModel(transport: transport, secrets: secrets, files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func session(_ root: URL) -> DiskSessionStore {
        DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path)
    }

    @Test func `switching A to B to A restores A's Tabs, Drafts, Dirty edits and Active Environment`() async throws {
        let window = makeWindow(open: a, listed: [a, b])
        window.loadDataFolder()
        window.selectedTab?.typeInURLBar("https://a.example/draft")
        window.newTab()
        window.selectedTab?.typeInURLBar("https://a.example/second")
        let environment = try window.newEnvironment()
        window.pickActiveEnvironment(environment)
        let before = window.tabs.map(\.tab.snapshot)

        await window.switchWorkspace(b.path)
        #expect(window.tabs.count == 1)
        #expect(window.tabs[0].tab.definition == .empty)
        #expect(window.activeEnvironment == nil)

        await window.switchWorkspace(a.path)
        #expect(window.tabs.map(\.tab.snapshot) == before)
        #expect(window.activeEnvironment == environment)
    }

    @Test func `switching to the open Workspace does nothing`() async throws {
        let window = makeWindow(open: a, listed: [a, b])
        window.loadDataFolder()
        let scans = window.scanCount

        await window.switchWorkspace(a.path + "/")

        #expect(window.scanCount == scans)
        #expect(watch.log == ["start \(a.path)"])
    }

    @Test func `the old watch ends before the new one starts, and its events no longer reach the index`() async throws {
        let window = makeWindow(open: a, listed: [a, b])
        window.loadDataFolder()

        await window.switchWorkspace(b.path)
        let scans = window.scanCount
        watch.emit(["x.json"])
        for _ in 0..<20 { await Task.yield() }

        #expect(watch.log == ["start \(a.path)", "end \(a.path)", "start \(b.path)"])
        #expect(window.scanCount == scans + 1)
    }

    @Test func `a send in flight on switch is cancelled`() async throws {
        let window = makeWindow(open: a, listed: [a, b])
        window.loadDataFolder()
        let tab = try #require(window.selectedTab)
        tab.typeInURLBar("https://example.com")
        tab.send()
        #expect(tab.inFlight != nil)

        await window.switchWorkspace(b.path)

        #expect(tab.inFlight == nil)
        #expect(tab.tab.response == .idle)
    }

    @Test func `the root is remembered even when it failed to load`() async throws {
        let remembered = Remembered()
        let window = makeWindow(open: a, listed: [a], remembered: remembered)
        window.loadDataFolder()
        let gone = temp.appending(path: "gone")

        await window.openWorkspace(gone.path)

        #expect(remembered.root == [gone.path])
        #expect(window.dataFolderError != nil)
        #expect(window.workspaces == [a.path, gone.path])
        #expect(!FileManager.default.fileExists(atPath: gone.path))
    }

    @Test func `opening a listed folder switches to it without adding a second row`() async throws {
        let remembered = Remembered()
        let window = makeWindow(open: a, listed: [a, b], remembered: remembered)
        window.loadDataFolder()

        await window.openWorkspace(b.path + "/")

        #expect(window.workspaces == [a.path, b.path])
        #expect(remembered.list.isEmpty)
        #expect(remembered.root == [b.path + "/"])
    }

    @Test func `removing another Workspace keeps its folder and deletes its Session file`() async throws {
        let remembered = Remembered()
        let window = makeWindow(open: a, listed: [a, b], remembered: remembered)
        window.loadDataFolder()
        await window.switchWorkspace(b.path)
        window.newTab()
        await window.switchWorkspace(a.path)
        #expect(try session(b).read() != nil)

        await window.removeWorkspace(b.path)

        #expect(window.workspaces == [a.path])
        #expect(remembered.list.last == [a.path])
        #expect(try session(b).read() == nil)
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test func `removing the open Workspace switches to the first other by name`() async throws {
        let c = temp.appending(path: "c")
        let window = makeWindow(open: b, listed: [a, b, c])
        window.loadDataFolder()

        await window.removeWorkspace(b.path)

        #expect(window.dataFolderRoot == a.path)
        #expect(window.workspaces == [a.path, c.path])
    }

    @Test func `a lone Workspace cannot be removed`() async throws {
        let window = makeWindow(open: a, listed: [a])
        window.loadDataFolder()

        await window.removeWorkspace(a.path)

        #expect(window.workspaces == [a.path])
        #expect(window.dataFolderRoot == a.path)
    }

    @Test func `New Workspace… creates the folder, lists it and opens it with a raccoon.json`() async throws {
        let window = makeWindow(open: a, listed: [a])
        window.loadDataFolder()

        let failure = await window.newWorkspace(b.path)

        #expect(failure == nil)
        #expect(window.workspaces == [a.path, b.path])
        #expect(window.dataFolderRoot == b.path)
        #expect(FileManager.default.fileExists(atPath: b.appending(path: "raccoon.json").path))
    }

    @Test func `New Workspace… on an existing name says so and writes nothing`() async throws {
        let window = makeWindow(open: a, listed: [a, b])
        window.loadDataFolder()

        let failure = await window.newWorkspace(b.path)

        #expect(failure == "A folder named “b” already exists. Use Open Workspace… to add it.")
        #expect(window.dataFolderRoot == a.path)
        #expect(!FileManager.default.fileExists(atPath: b.appending(path: "raccoon.json").path))
    }

    @Test func `New Workspace… that cannot create the folder says why`() async throws {
        let window = makeWindow(open: a, listed: [a])
        window.loadDataFolder()
        let locked = temp.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let failure = await window.newWorkspace(locked.appending(path: "new").path)

        #expect(failure?.hasPrefix("Couldn't create “new”: ") == true)
        #expect(window.workspaces == [a.path])
        #expect(window.dataFolderRoot == a.path)
    }
}
