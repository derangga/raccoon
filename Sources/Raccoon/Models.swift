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

    /// Read again once 150 ms have passed; Observation does not see time move.
    var showsSpinner: Bool { tab.response.showsSpinner(at: instants.now) }

    /// The in-flight send (§8). The Tab is the only thing holding it.
    private(set) var inFlight: Task<Void, Never>?

    /// Resolution runs first, so a request that cannot be sent never shows `.sending`.
    /// One send at a time (§7): a second ⌘↩ while sending does nothing.
    func send() {
        guard inFlight == nil else { return }
        let resolved: ResolvedRequest
        do throws(ResolveError) {
            resolved = try VariableResolver.resolve(tab.definition)
        } catch {
            tab.response = .notSent(error)
            return
        }
        tab.response = .sending(since: instants.now)
        inFlight = Task {
            do throws(SendError) {
                tab.response = .received(try await transport.send(resolved))
            } catch {
                tab.response = .failed(error)
            }
            inFlight = nil
        }
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
