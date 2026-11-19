import Foundation
import RaccoonDomain
import Testing

struct TabStateTests {
    static let saved = RequestDefinition(
        method: "GET", url: "https://api.example.com/users", params: [], headers: [], cookies: [],
        body: .none, auth: .none, settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false)
    )
    static var edited: RequestDefinition {
        var definition = saved
        definition.method = "POST"
        return definition
    }
    static let request = Tab.Source.request(RequestID(UUID()))

    @Test(arguments: [
        // source, definition, baseline, isDirty, hasLosableContent
        (Tab.Source.draft, RequestDefinition.empty, nil as RequestDefinition?, false, false),
        (.draft, saved, nil, false, true),
        (request, saved, saved, false, false),
        (request, edited, saved, true, true),
        (request, .empty, .empty, false, false),
    ])
    func `Dirty is against the baseline, and a Draft loses content only when not empty`(
        source: Tab.Source, definition: RequestDefinition, baseline: RequestDefinition?, isDirty: Bool, hasLosableContent: Bool
    ) {
        let tab = Tab(id: TabID(UUID()), source: source, definition: definition, baseline: baseline)
        #expect(tab.isDirty == isDirty)
        #expect(tab.hasLosableContent == hasLosableContent)
    }

    @Test func `a Request Tab is clean again once its definition returns to the baseline`() {
        var tab = Tab(id: TabID(UUID()), source: Self.request, definition: Self.saved, baseline: Self.saved)
        tab.definition.url += "/42"
        #expect(tab.isDirty)
        tab.definition.url = Self.saved.url
        #expect(!tab.isDirty)
    }
}

struct ExampleTabStateTests {
    static let saved = Example(id: ExampleID(UUID()), name: "200 OK", status: 200, body: .text("{}"))
    static var edited: Example {
        var example = saved
        example.status = 404
        return example
    }
    static let source = Tab.Source.example(RequestID(UUID()), saved.id)

    @Test(arguments: [
        // content, baseline, isDirty
        (saved, saved as Example?, false),
        (edited, saved, true),
        // no baseline on an Example Tab means "not on disk": it has something to lose
        (saved, nil, true),
    ])
    func `an Example Tab is Dirty against its baseline, and with none it is not on disk`(content: Example, baseline: Example?, isDirty: Bool) {
        let tab = Tab(id: TabID(UUID()), source: Self.source, content: .example(content), baseline: baseline.map { .example($0) })
        #expect(tab.isDirty == isDirty)
        #expect(tab.hasLosableContent == isDirty)
    }

    @Test func `an Example Tab's definition is empty and ignores assignment`() {
        var tab = Tab(id: TabID(UUID()), source: Self.source, content: .example(Self.saved), baseline: .example(Self.saved))
        #expect(tab.definition == .empty)
        tab.definition.url = "https://a.b"
        #expect(tab.content == .example(Self.saved))
        #expect(!tab.isDirty)
    }

    @Test func `the snapshot carries the content and the baseline`() {
        let tab = Tab(id: TabID(UUID()), source: Self.source, content: .example(Self.edited), baseline: .example(Self.saved))
        #expect(tab.snapshot == TabSnapshot(id: tab.id, source: Self.source, content: .example(Self.edited), baseline: .example(Self.saved)))
    }
}

struct TabTitleTests {
    @Test(arguments: [
        // the URL as typed, the Draft's title
        ("", "Draft"),
        ("   ", "Draft"),
        ("https://api.example.com/v1/webhooks", "/v1/webhooks"),
        ("https://api.example.com/v1/charges?limit=10#top", "/v1/charges"),
        ("{{base_url}}/v1/charges/{{charge_id}}", "/v1/charges/{{charge_id}}"),
        ("localhost:8080/health", "/health"),
        ("https://api.example.com", "https://api.example.com"),
        ("/relative", "/relative"),
    ])
    func `a Draft is titled by its URL path, and "Draft" while it has no URL`(url: String, title: String) {
        var definition = RequestDefinition.empty
        definition.url = url
        let tab = Tab(id: TabID(UUID()), source: .draft, definition: definition, baseline: nil)
        #expect(tab.title == title)
    }
}
