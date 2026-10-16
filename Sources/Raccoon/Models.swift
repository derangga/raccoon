import Foundation
import Observation
import RaccoonDomain

/// One Tab's editing state and the ports its send needs. Saving goes through the window, which
/// owns the index and the WriteLedger, so a Tab can never write a file the index does not know.
@Observable
final class TabModel {
    var tab: Tab
    private let transport: any HTTPTransport
    private let secrets: any SecretStore
    private let instants: any InstantSource

    init(transport: any HTTPTransport, secrets: any SecretStore, instants: any InstantSource) {
        tab = Tab(id: TabID(UUID()), source: .draft, definition: .empty, baseline: nil)
        self.transport = transport
        self.secrets = secrets
        self.instants = instants
    }
}

/// The window's Tabs and the ports that touch the Data Folder, the Session and the Keychain.
@Observable
final class WindowModel {
    private(set) var tabs: [TabModel]
    private let dataFolder: any DataFolderStore
    private let folderWatch: any FolderWatch
    private let sessionStore: any SessionStore
    private let secrets: any SecretStore
    private let newTab: () -> TabModel

    /// `newTab` builds a TabModel with its own ports; the window never hands a Tab its stores.
    init(
        dataFolder: any DataFolderStore, folderWatch: any FolderWatch, sessionStore: any SessionStore,
        secrets: any SecretStore, newTab: @escaping () -> TabModel
    ) {
        self.dataFolder = dataFolder
        self.folderWatch = folderWatch
        self.sessionStore = sessionStore
        self.secrets = secrets
        self.newTab = newTab
        tabs = [newTab()]
    }
}
