import Foundation
import RaccoonDomain
import Testing

struct DataFolderScanTests {
    static let scan = DataFolderScan(
        files: ["A/r.json": Data("r".utf8), "A/F/s.json": Data("s".utf8), "A/F/G/t.json": Data("t".utf8), "B/u.json": Data("u".utf8)],
        folders: ["A", "A/F", "A/F/G", "B"]
    )

    @Test func `moving a folder moves everything under it, and nothing that only shares its prefix`() {
        let scan = DataFolderScan(files: Self.scan.files.merging(["A/Fx.json": Data("x".utf8)]) { $1 }, folders: Self.scan.folders)
        #expect(scan.moving("A/F", to: "B/F") == DataFolderScan(
            files: ["A/r.json": Data("r".utf8), "A/Fx.json": Data("x".utf8), "B/F/s.json": Data("s".utf8), "B/F/G/t.json": Data("t".utf8), "B/u.json": Data("u".utf8)],
            folders: ["A", "B", "B/F", "B/F/G"]
        ))
    }

    @Test func `moving a file`() {
        #expect(Self.scan.moving("A/r.json", to: "B/r.json").files["B/r.json"] == Data("r".utf8))
        #expect(Self.scan.moving("A/r.json", to: "B/r.json").files["A/r.json"] == nil)
    }

    @Test func `removing a folder removes everything under it`() {
        #expect(Self.scan.removing("A/F") == DataFolderScan(files: ["A/r.json": Data("r".utf8), "B/u.json": Data("u".utf8)], folders: ["A", "B"]))
    }

    @Test func `the paths a change touches`() {
        #expect(Self.scan.paths(under: "A/F") == ["A/F", "A/F/G", "A/F/s.json", "A/F/G/t.json"])
        #expect(Self.scan.paths(under: "A/r.json") == ["A/r.json"])
    }
}
