import Foundation
import RaccoonDomain
import Testing

struct RequestFileTests {
    static let id = RequestID(UUID(uuidString: "6F1C2B3A-0000-4000-8000-000000000001")!)

    @Test func `a file with only method and url decodes, absence meaning the defaults`() throws {
        let json = #"{"version": 1, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "Create charge", "method": "POST", "url": "https://api.example.com/charges"}"#
        var definition = RequestDefinition.empty
        definition.method = "POST"
        definition.url = "https://api.example.com/charges"
        #expect(try RequestFile.decode(Data(json.utf8)) == Request(id: Self.id, name: "Create charge", definition: definition))
    }

    /// Canonical files, written by hand: what a save must produce, byte for byte.
    static let fixtures = [
        """
        {
          "id" : "6F1C2B3A-0000-4000-8000-000000000001",
          "method" : "GET",
          "name" : "List charges",
          "settings" : {
            "allowsInsecureTLS" : false,
            "followsRedirects" : false
          },
          "url" : "https://api.example.com/charges",
          "version" : 1
        }

        """,
        """
        {
          "auth" : {
            "password" : "{{password}}",
            "type" : "basic",
            "user" : "ana"
          },
          "body" : {
            "parts" : [
              {
                "isEnabled" : true,
                "name" : "note",
                "text" : "café ☕"
              },
              {
                "file" : "~/Documents/receipt.pdf",
                "isEnabled" : false,
                "name" : "receipt"
              }
            ],
            "type" : "multipart"
          },
          "cookies" : [
            {
              "isEnabled" : true,
              "name" : "sid",
              "value" : "abc"
            }
          ],
          "headers" : [
            {
              "isEnabled" : true,
              "name" : "Idempotency-Key",
              "value" : "{{key}}"
            },
            {
              "isEnabled" : false,
              "name" : "X-Debug",
              "value" : "1"
            }
          ],
          "id" : "6F1C2B3A-0000-4000-8000-000000000002",
          "method" : "POST",
          "name" : "Create charge / 注文",
          "params" : [
            {
              "isEnabled" : true,
              "name" : "expand",
              "value" : "customer"
            }
          ],
          "settings" : {
            "allowsInsecureTLS" : true,
            "followsRedirects" : true
          },
          "url" : "https://api.example.com/v1/charges",
          "version" : 1
        }

        """,
        """
        {
          "auth" : {
            "token" : "{{token}}",
            "type" : "bearer"
          },
          "body" : {
            "kind" : "json",
            "text" : "{\\n  \\"amount\\": 100\\n}",
            "type" : "raw"
          },
          "id" : "6F1C2B3A-0000-4000-8000-000000000003",
          "method" : "PURGE",
          "name" : "Refund",
          "settings" : {
            "allowsInsecureTLS" : false,
            "followsRedirects" : true
          },
          "url" : "https://api.example.com/refunds",
          "version" : 1
        }

        """,
        """
        {
          "id" : "6F1C2B3A-0000-4000-8000-000000000004",
          "method" : "GET",
          "name" : "Retry share",
          "pathVariables" : {
            "id" : "689eba19be47b88f9d590367",
            "other" : "{{other}}"
          },
          "settings" : {
            "allowsInsecureTLS" : false,
            "followsRedirects" : false
          },
          "url" : "http://localhost:3061/posts/:id/retry/:other",
          "version" : 1
        }

        """,
    ]

    @Test(arguments: fixtures)
    func `an unchanged save writes the same bytes`(fixture: String) throws {
        #expect(String(decoding: RequestFile.encode(try RequestFile.decode(Data(fixture.utf8))), as: UTF8.self) == fixture)
    }

    @Test func `changing one header changes one line of the file`() throws {
        var request = try RequestFile.decode(Data(Self.fixtures[1].utf8))
        request.definition.headers[0].value = "{{idempotencyKey}}"
        let before = Self.fixtures[1].split(separator: "\n", omittingEmptySubsequences: false)
        let after = String(decoding: RequestFile.encode(request), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before.count == after.count)
        #expect(zip(before, after).filter { $0 != $1 }.map(\.1) == [#"      "value" : "{{idempotencyKey}}""#])
    }

    @Test func `version 3 is an unknown version, never guessed at`() {
        let json = #"{"version": 3, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "A", "method": "GET", "url": "x"}"#
        #expect(throws: RequestFileError.unknownVersion(3)) { try RequestFile.decode(Data(json.utf8)) }
    }

    // MARK: Docs

    @Test func `no docs writes no key, and docs survive a round trip character for character`() throws {
        var request = try RequestFile.decode(Data(Self.fixtures[0].utf8))
        #expect(!String(decoding: RequestFile.encode(request), as: UTF8.self).contains("docs"))
        request.definition.docs = "# Charges\n\nSend `{{token}}` — **café** ☕\r\n- a \"quote\" and a / slash\n"
        let file = RequestFile.encode(request)
        #expect(String(decoding: file, as: UTF8.self).contains(#""docs" : "#))
        #expect(try RequestFile.decode(file) == request)
        #expect(try RequestFile.decode(file).definition.docs == request.definition.docs)
    }

    @Test func `docs that are not a string make the file malformed`() {
        let json = #"{"version": 1, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "A", "method": "GET", "url": "x", "docs": 3}"#
        #expect(throws: RequestFileError.malformed("“docs” has the wrong type")) { try RequestFile.decode(Data(json.utf8)) }
    }

    // MARK: Request Settings

    @Test func `the four newer Request Settings round-trip, and a file without them has the defaults`() throws {
        var request = try RequestFile.decode(Data(Self.fixtures[0].utf8))
        request.definition.settings = RequestSettings(
            allowsInsecureTLS: false, followsRedirects: true, followsOriginalMethod: true,
            followsAuthorizationHeader: true, maxRedirects: 5, timeoutSeconds: 30
        )
        #expect(try RequestFile.decode(RequestFile.encode(request)) == request)

        let bare = try RequestFile.decode(Data(Self.fixtures[0].utf8)).definition.settings
        #expect(bare == RequestSettings(allowsInsecureTLS: false, followsRedirects: false))
    }

    /// A default is absent, so no existing Request file gains a line.
    @Test func `settings at their defaults write no key`() throws {
        let text = String(decoding: RequestFile.encode(try RequestFile.decode(Data(Self.fixtures[0].utf8))), as: UTF8.self)
        for key in ["followsOriginalMethod", "followsAuthorizationHeader", "maxRedirects", "timeoutSeconds"] {
            #expect(!text.contains(key))
        }
    }

    @Test func `a Redirect Limit out of range is clamped when the file is read`() throws {
        let json = #"{"version": 1, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "A", "method": "GET", "url": "x", "settings": {"maxRedirects": 9007199254740991}}"#
        #expect(try RequestFile.decode(Data(json.utf8)).definition.settings.maxRedirects == 20)
    }

    // MARK: pathVariables

    @Test func `Path Variable values round-trip, and a file without the key has none`() throws {
        let with = try RequestFile.decode(Data(Self.fixtures[3].utf8))
        #expect(with.definition.pathVariables == ["id": "689eba19be47b88f9d590367", "other": "{{other}}"])
        #expect(try RequestFile.decode(RequestFile.encode(with)) == with)
        for absent in Self.fixtures[..<3] {
            #expect(try RequestFile.decode(Data(absent.utf8)).definition.pathVariables == [:])
        }
    }

    @Test func `no values means no key in the file`() throws {
        var request = try RequestFile.decode(Data(Self.fixtures[3].utf8))
        request.definition.pathVariables = [:]
        #expect(!String(decoding: RequestFile.encode(request), as: UTF8.self).contains("pathVariables"))
    }

    @Test func `changing one value changes one line of the file`() throws {
        var request = try RequestFile.decode(Data(Self.fixtures[3].utf8))
        request.definition.pathVariables["id"] = "7"
        let before = Self.fixtures[3].split(separator: "\n", omittingEmptySubsequences: false)
        let after = String(decoding: RequestFile.encode(request), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before.count == after.count)
        #expect(zip(before, after).filter { $0 != $1 }.map(\.1) == [#"    "id" : "7","#])
    }

    @Test func `a value for a name the URL no longer has is kept, and an empty value is absent`() throws {
        let json = #"{"version": 1, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "A", "method": "GET", "url": "http://h/x", "pathVariables": {"gone": "1", "empty": ""}}"#
        #expect(try RequestFile.decode(Data(json.utf8)).definition.pathVariables == ["gone": "1"])
    }

    @Test(arguments: [#"["id"]"#, #"{"id": 7}"#, #""id""#, #"{"id": null}"#, #"{"id": {"a": "b"}}"#])
    func `pathVariables that is not an object of strings is malformed`(value: String) {
        let json = #"{"version": 1, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "A", "method": "GET", "url": "x", "pathVariables": \#(value)}"#
        #expect {
            try RequestFile.decode(Data(json.utf8))
        } throws: { error in
            if case .malformed = error as? RequestFileError { true } else { false }
        }
    }
}
