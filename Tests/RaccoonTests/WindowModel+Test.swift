import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting

extension WindowModel {
    /// A window over one fixed SessionStore and SecretStore, whatever Workspace is open.
    convenience init(
        dataFolder: DataFolderLocation, folderWatch: any FolderWatch, sessionStore: any SessionStore, secrets: any SecretStore,
        instants: any InstantSource, mockListening: any MockListening = ScriptedMockListening(),
        makeTab: @escaping () -> TabModel
    ) {
        self.init(
            dataFolder: dataFolder, folderWatch: folderWatch, sessionStore: { _ in sessionStore }, secrets: { _ in secrets },
            instants: instants, mockListening: mockListening, makeTab: { _ in makeTab() })
    }
}
