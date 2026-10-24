import Foundation

/// What Import did: the Collections that landed, by folder name, in plan order, and every
/// problem. Everything else in the plan landed.
public struct ImportResult: Equatable, Sendable {
    public var collections: [String]
    public var problems: [ImportError]

    public init(collections: [String] = [], problems: [ImportError] = []) {
        self.collections = collections
        self.problems = problems
    }
}

extension ImportCollection {
    /// Its Folders and Request files by path inside the Collection's folder, as writeDirectory
    /// takes them. Names become file names as New Folder and Save make them: sanitised, " 2" on a
    /// clash with a sibling Folder or file, ignoring case. An empty Folder name is "New Folder",
    /// an empty Request name "Request" (postman.md).
    public var contents: DataFolderScan {
        var contents = DataFolderScan(files: [:], folders: [])
        func add(_ nodes: [ImportNode], in folder: String) {
            var taken: Set<String> = []
            let path = { (name: String) in folder.isEmpty ? name : folder + "/" + name }
            for node in nodes {
                switch node {
                case .folder(let name, let children):
                    let name = RequestFileName.unique(RequestFileName.sanitised(name.isEmpty ? "New Folder" : name), taken: taken)
                    taken.insert(name)
                    contents.folders.insert(path(name))
                    add(children, in: path(name))
                case .request(var request):
                    if request.name.isEmpty { request.name = "Request" }
                    let file = RequestFileName.make(request.name, taken: taken)
                    taken.insert(file)
                    contents.files[path(file)] = RequestFile.encode(request)
                }
            }
        }
        add(nodes, in: "")
        return contents
    }
}
