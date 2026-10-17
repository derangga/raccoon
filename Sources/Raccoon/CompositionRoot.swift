import Foundation
import RaccoonData
import RaccoonDomain

/// The one place the live ports are built. Each is built once and handed down through
/// initializers; nothing below reaches for a shared instance. Building touches no disk or
/// Keychain: every store does its I/O when a feature first calls it.
enum CompositionRoot {
    static func live() -> WindowModel {
        let files = DiskFileReading()
        let transport = URLSessionTransport(files: files)
        let secrets = KeychainSecretStore(service: "Raccoon")
        let instants = ContinuousInstantSource()
        return WindowModel(
            dataFolder: DiskDataFolderStore(root: URL.homeDirectory.appending(path: "Raccoon")),
            folderWatch: FSEventsFolderWatch(),
            sessionStore: DiskSessionStore(directory: DiskSessionStore.applicationSupportDirectory),
            secrets: secrets,
            newTab: { TabModel(transport: transport, secrets: secrets, files: files, instants: instants) }
        )
    }
}
