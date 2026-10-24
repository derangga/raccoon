import Foundation
import RaccoonDomain
import Testing

/// Postman export files and the ImportPlan Postman Import must make of them, planned into an
/// empty Workspace with RequestIDs counted from 1.
struct PostmanFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let files: [String]
    let expected: ImportPlan

    var testDescription: String { name }

    init(_ name: String, _ files: String..., plan: ImportPlan) {
        self.name = name
        self.files = files
        self.expected = plan
    }
}

/// A plan of one Collection.
func imported(_ name: String, _ nodes: [ImportNode], globals: [ImportVariable] = [], notes: [ImportNote] = []) -> ImportPlan {
    ImportPlan(collections: [ImportCollection(name: name, nodes: nodes)], environments: [], globals: globals, notes: notes)
}

/// A planned Request whose RequestID is the nth: Postman's default follows redirects.
func planned(
    _ n: Int, _ name: String, _ method: String = "GET", _ url: String = "", params: [Row] = [], headers: [Row] = [],
    cookies: [Row] = [], body: Body = .none, auth: Auth = .none, insecure: Bool = false, redirects: Bool = true
) -> ImportNode {
    .request(Request(id: PostmanMappingTests.id(n), name: name, definition: RequestDefinition(
        method: method, url: url, params: params, headers: headers, cookies: cookies, body: body, auth: auth,
        settings: RequestSettings(allowsInsecureTLS: insecure, followsRedirects: redirects)
    )))
}

func note(_ kind: ImportNote.Kind, _ names: String...) -> ImportNote {
    ImportNote(kind, names: names)
}

func variable(_ name: String, _ value: String, enabled: Bool = true) -> ImportVariable {
    ImportVariable(name: VariableName(name)!, isEnabled: enabled, value: .plain(value))
}

extension PostmanMappingTests {
    static let fixtures = YaakPostmanFixtures.all + BrunoPostmanFixtures.all

    @Test(arguments: fixtures)
    func `a Postman export copied from Yaak or Bruno plans as expected`(fixture: PostmanFixture) {
        let plan = plan(fixture.files.map { PostmanImporter.read(Data($0.utf8)) })
        #expect(plan.collections == fixture.expected.collections)
        #expect(plan.environments == fixture.expected.environments)
        #expect(plan.globals == fixture.expected.globals)
        #expect(plan.notes == fixture.expected.notes)
    }

    @Test func `every fixture has its own name`() {
        #expect(Set(Self.fixtures.map(\.name)).count == Self.fixtures.count)
    }
}
