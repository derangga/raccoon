import Foundation
import RaccoonDomain
import RaccoonTesting
import Testing

@Suite struct ScriptedMockListeningTests {
    private let reply = MockReply(status: 200, headers: [], body: Data("ok".utf8), delay: .zero)
    private var head: MockRequestHead {
        guard case .head(let head, _, _) = MockRequestHead.parse(Data("GET /users HTTP/1.1\r\nHost: x\r\n\r\n".utf8)) else {
            preconditionFailure("fixture does not parse")
        }
        return head
    }

    @Test func `listen reports the requested port, or the picked one for nil`() async throws {
        let listening = ScriptedMockListening(picked: 51_234)
        let fixed = try await listening.listen(port: 8080) { _ in reply }
        let free = try await listening.listen(port: nil) { _ in reply }
        #expect(fixed.port == 8080)
        #expect(free.port == 51_234)
        #expect(listening.requestedPorts == [8080, nil])
    }

    @Test func `answer returns what the handler replied for the head it was given`() async throws {
        let listening = ScriptedMockListening()
        #expect(await listening.answer(head) == nil)
        let listener = try await listening.listen(port: nil) { [reply] head in
            MockReply(status: reply.status, headers: [], body: Data(head.path.joined(separator: "/").utf8), delay: .zero)
        }
        #expect(await listening.answer(head)?.body == Data("users".utf8))
        _ = listener
    }

    @Test func `a scripted failure is thrown and still recorded`() async {
        let listening = ScriptedMockListening(failing: .portInUse(8080))
        await #expect(throws: MockError.portInUse(8080)) { try await listening.listen(port: 8080) { _ in reply } }
        #expect(listening.requestedPorts == [8080])
    }

    @Test func `stop is observable`() async throws {
        let listening = ScriptedMockListening()
        let listener = try await listening.listen(port: nil) { _ in reply }
        listener.stop()
        #expect(listening.stops == 1)
    }
}
