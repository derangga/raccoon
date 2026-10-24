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
        let instants = ContinuousInstantSource()
        let clipboard = SystemClipboardWriter(name: .general)
        let root = defaults.string(forKey: "DataFolder") ?? URL.homeDirectory.appending(path: "Raccoon").path
        return WindowModel(
            dataFolder: DataFolderLocation(
                root: root,
                workspaces: defaults.stringArray(forKey: "Workspaces") ?? [],
                open: { DiskDataFolderStore(root: URL(filePath: $0)) },
                remember: { defaults.set($0, forKey: "DataFolder") },
                rememberWorkspaces: { defaults.set($0, forKey: "Workspaces") }
            ),
            folderWatch: FSEventsFolderWatch(),
            sessionStore: { DiskSessionStore(directory: DiskSessionStore.applicationSupportDirectory, root: $0) },
            // No id: raccoon.json was undecodable or could not be written.
            secrets: { (id: WorkspaceID?) -> any SecretStore in id.map { KeychainSecretStore(id: $0) } ?? NoWorkspaceIDSecretStore() },
            instants: instants,
            makeTab: { TabModel(transport: transport, secrets: $0, files: files, instants: instants, clipboard: clipboard) }
        )
    }

    /// A value of the wrong type reads as absent; the split clamps the width.
    static func inspectorMemory(defaults: UserDefaults) -> InspectorMemory {
        InspectorMemory(
            isShown: defaults.object(forKey: "InspectorShown") as? Bool ?? false,
            width: (defaults.object(forKey: "InspectorWidth") as? Double).flatMap { $0.isFinite ? CGFloat($0) : nil },
            pane: defaults.object(forKey: "InspectorPane") as? String,
            rememberShown: { defaults.set($0, forKey: "InspectorShown") },
            rememberWidth: { defaults.set(Double($0), forKey: "InspectorWidth") },
            rememberPane: { defaults.set($0, forKey: "InspectorPane") }
        )
    }
}
