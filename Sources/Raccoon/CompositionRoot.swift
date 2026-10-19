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
        let secrets = KeychainSecretStore(service: "Raccoon")
        let instants = ContinuousInstantSource()
        let clipboard = SystemClipboardWriter(name: .general)
        return WindowModel(
            dataFolder: DataFolderLocation(
                root: defaults.string(forKey: "DataFolder") ?? URL.homeDirectory.appending(path: "Raccoon").path,
                open: { DiskDataFolderStore(root: URL(filePath: $0)) },
                remember: { defaults.set($0, forKey: "DataFolder") }
            ),
            folderWatch: FSEventsFolderWatch(),
            sessionStore: DiskSessionStore(directory: DiskSessionStore.applicationSupportDirectory),
            secrets: secrets,
            instants: instants,
            makeTab: { TabModel(transport: transport, secrets: secrets, files: files, instants: instants, clipboard: clipboard) }
        )
    }
}
