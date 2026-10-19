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
}
