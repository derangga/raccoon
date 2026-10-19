import Foundation
import RaccoonData
import RaccoonDomain

/// The one place the live ports are built. Each is built once and handed down through
/// initializers; nothing below reaches for a shared instance. Building touches no disk or
/// Keychain: every store does its I/O when a feature first calls it.
enum CompositionRoot {
    static func live(defaults: UserDefaults) -> WindowModel {
        let files = DiskFileReading()
        let transport = URLSessionTransport(files: files)
        // ponytail: no raccoon.json is read yet, so no id. Loading a Workspace builds its
        // KeychainSecretStore; nothing reads a secret before then.
        let secrets = NoWorkspaceIDSecretStore()
        let instants = ContinuousInstantSource()
        let clipboard = SystemClipboardWriter(name: .general)
        let root = defaults.string(forKey: "DataFolder") ?? URL.homeDirectory.appending(path: "Raccoon").path
        return WindowModel(
            dataFolder: DataFolderLocation(
                root: root,
                open: { DiskDataFolderStore(root: URL(filePath: $0)) },
                remember: { defaults.set($0, forKey: "DataFolder") }
            ),
            folderWatch: FSEventsFolderWatch(),
            // ponytail: keyed by the launch root; Choose Folder… keeps writing here until loading
            // a Workspace builds its own SessionStore.
            sessionStore: DiskSessionStore(directory: DiskSessionStore.applicationSupportDirectory, root: root),
            secrets: secrets,
            instants: instants,
            makeTab: { TabModel(transport: transport, secrets: secrets, files: files, instants: instants, clipboard: clipboard) }
        )
    }
}
