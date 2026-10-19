import Foundation
@testable import Raccoon
import RaccoonData

extension DataFolderLocation {
    /// A live store over `root`, a temp dir; nothing is remembered.
    static func test(_ root: URL) -> DataFolderLocation {
        DataFolderLocation(root: root.path, open: { DiskDataFolderStore(root: URL(filePath: $0)) }, remember: { _ in })
    }
}
