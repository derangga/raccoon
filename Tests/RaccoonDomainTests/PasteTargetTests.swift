import Foundation
import RaccoonDomain
import Testing

struct PasteTargetTests {
    static let response = Response(status: 200, headers: [], body: Data(), elapsed: .milliseconds(5), byteCount: 0)
    static var edited: RequestDefinition {
        var definition = RequestDefinition.empty
        definition.url = "http://h/"
        return definition
    }

    @Test(arguments: [
        (Tab.Source.draft, RequestDefinition.empty, ResponseState.idle, PasteTarget.currentTab),
        (.draft, edited, .idle, .newDraftTab),
        (.draft, .empty, .received(response), .newDraftTab),
        (.request(RequestID(UUID())), .empty, .idle, .newDraftTab),
    ])
    func `a curl lands in the current Tab only when it is the empty Draft with no Response`(
        source: Tab.Source, definition: RequestDefinition, response: ResponseState, target: PasteTarget
    ) {
        let tab = Tab(id: TabID(UUID()), source: source, definition: definition, baseline: nil, response: response)
        #expect(PasteTarget.for(tab) == target)
    }
}
