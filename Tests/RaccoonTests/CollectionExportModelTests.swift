import Foundation
@testable import Raccoon
import RaccoonDomain
import Testing

/// What the Collection Export sheet says (design-system §6): each string, from a plan.
@MainActor
struct CollectionExportModelTests {
    let model = CollectionExportModel(name: "Sociolla", folder: "~/Raccoon")

    func plan(
        requests: Int = 0, folders: Int = 0, findings: [CredentialFinding] = [], skipped: [ExportSkip] = [], dirty: [String] = []
    ) -> ExportPlan {
        ExportPlan(
            collection: ExportCollection(name: "Sociolla", nodes: []), requests: requests, folders: folders, findings: findings,
            skipped: skipped, dirtyRequests: dirty, data: Data()
        )
    }

    func findings(_ names: [String]) -> [CredentialFinding] {
        names.map { CredentialFinding(request: $0, place: .header("authorization")) }
    }

    @Test func `the title names the Collection`() {
        #expect(model.title == "Export “Sociolla”")
    }

    @Test func `each step says what it did`() {
        #expect(model.text(of: .read(count: 41)) == "Read 41 Requests from ~/Raccoon")
        #expect(model.text(of: .read(count: 1)) == "Read 1 Request from ~/Raccoon")
        #expect(model.text(of: .formatted) == "Formatted as Collection Format v2.1")
        #expect(model.text(of: .scanned(plan())) == "Scanned for credentials")
    }

    @Test(arguments: [
        (41, 11, "41 Requests · 11 Folders"), (1, 1, "1 Request · 1 Folder"), (0, 0, "0 Requests · 0 Folders"),
        (2_000, 0, "2,000 Requests · 0 Folders"),
    ])
    func `the counts are what the file holds`(requests: Int, folders: Int, text: String) {
        #expect(model.counts(plan(requests: requests, folders: folders)) == text)
    }

    @Test func `credentials: the count, a line saying the file keeps them, and each Request once in tree order`() throws {
        let notices = model.notices(plan(findings: findings(["Login", "Login", "Refresh"]) + findings(["Login"])))
        let credentials = try #require(notices.first)

        // One Request's findings sit together and show once; a second Request named Login still shows.
        #expect(credentials == .init(
            kind: .credentials, headline: "4 credentials in plain text", detail: "The file keeps them exactly as typed.",
            names: ["Login", "Refresh", "Login"]
        ))
        #expect(model.notices(plan(findings: findings(["A"]))).first?.headline == "1 credential in plain text")
        #expect(model.notices(plan()) == [])
    }

    @Test func `skipped files: the count, the promise, and the file names`() throws {
        let one = model.notices(plan(skipped: [ExportSkip(path: "Sociolla/Folder/Broken.json", reason: "Not valid JSON at line 1.")]))
        #expect(one == [.init(
            kind: .skipped, headline: "1 file is not exported", detail: "Raccoon can't read it as a Request, and won't change it.",
            names: ["Broken.json"], tooltip: "Broken.json: Not valid JSON at line 1."
        )])
        let three = model.notices(plan(skipped: ["a", "b", "c"].map { ExportSkip(path: "Sociolla/\($0).json", reason: "") }))
        #expect(three.first?.headline == "3 files are not exported")
    }

    @Test func `Dirty Requests: one info line, after the others`() {
        let notices = model.notices(plan(findings: findings(["A"]), skipped: [ExportSkip(path: "C/x.json", reason: "")], dirty: ["A", "B"]))
        #expect(notices.map(\.kind) == [.credentials, .skipped, .dirty])
        #expect(notices.last == .init(
            kind: .dirty, headline: "2 Requests have edits in Tabs. Export uses what is saved.", detail: nil, names: []
        ))
        #expect(model.notices(plan(dirty: ["A"])).first?.headline == "1 Request has edits in a Tab. Export uses what is saved.")
    }

    @Test func `a failed write is a red line with the reason as a sentence`() {
        #expect(model.failure(.unwritable(path: "/a/x.json", reason: "The folder “Archive” is not writable.")) == "Not exported. The folder “Archive” is not writable.")
        #expect(model.failure(.unwritable(path: "/a/x.json", reason: "the disk is full")) == "Not exported. The disk is full.")
    }

    @Test(arguments: [("Sociolla", "Sociolla.postman_collection.json"), ("A/B:C", "A-B-C.postman_collection.json")])
    func `the save panel's name is the Collection's, as a file name`(name: String, file: String) {
        #expect(CollectionExportModel(name: name, folder: "").fileName == file)
    }
}
