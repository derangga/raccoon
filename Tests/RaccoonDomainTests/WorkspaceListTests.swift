import RaccoonDomain
import Testing

struct WorkspaceListTests {
    @Test(arguments: [
        (["/Users/me/Raccoon"], ["Raccoon"]),
        (["/Users/me/work/api", "/Users/me/side/api"], ["api — side", "api — work"]),
        (["/Users/me/work/api", "/Users/me/Raccoon", "/Users/me/side/api"], ["api — side", "api — work", "Raccoon"]),
        (["/Users/me/api 10", "/Users/me/api 2"], ["api 2", "api 10"]),
    ])
    func `a unique name is bare, a shared one names its parent, and rows sort as the sidebar`(paths: [String], titles: [String]) {
        #expect(WorkspaceList.titles(paths).map(\.title) == titles)
    }

    @Test func `each title keeps its path`() {
        let rows = WorkspaceList.titles(["/Users/me/work/api", "/Users/me/side/api"])
        #expect(rows.map(\.path) == ["/Users/me/side/api", "/Users/me/work/api"])
    }
}
