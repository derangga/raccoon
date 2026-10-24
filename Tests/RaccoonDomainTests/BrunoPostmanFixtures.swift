// The inputs below are copied from Bruno's Postman import tests in
// bruno/packages/bruno-converters/tests/postman, and each case is named after its Bruno test (a
// name Bruno uses twice gets " (2)"). Bruno writes its inputs as JS objects, so each is the JSON
// that object serialises to: a key whose value is `undefined` is absent, and NaN and Infinity are
// `null`. The three overflowing maxRedirects literals are copied as the JSON text the test parses.
// The expected outputs are rewritten as Raccoon's ImportPlan; where Raccoon differs on purpose, the
// comment names the row of design/entry-points/postman.md that says why.
//
// MIT License
//
// Copyright (c) 2022 Anoop M D, Anusree P S and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import RaccoonDomain

enum BrunoPostmanFixtures {
    static let all: [PostmanFixture] = collectionAuth + folderAuth + requestAuth + processAuth
        + disabledSystemHeaders + maxRedirects + partialImport + postmanToBruno
        + transformDescription + environments + edgegrid + preserveScripts

    private static let form = Row(name: "Content-Type", value: "application/x-www-form-urlencoded")
    private static let multipart = Row(name: "Content-Type", value: "multipart/form-data")

    /// A processAuth input on the one Request of a Collection that has no auth of its own.
    private static func auth(_ name: String, _ json: String, auth: Auth = .none, headers: [Row] = [], notSupported type: String? = nil) -> PostmanFixture {
        PostmanFixture(name, #"""
            {"info": {"name": "Auth", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
             "item": [{"name": "Request", "request": {"method": "GET", "url": "https://example.com", "auth": \#(json)}}]}
            """#, plan: imported(
                "Auth", [planned(1, "Request", "GET", "https://example.com", headers: headers, auth: auth)],
                notes: type.map { [note(.authNotSupported(type: $0), "Request")] } ?? []
            ))
    }

    private static func environment(_ name: String, _ variables: [ImportVariable]) -> ImportPlan {
        ImportPlan(collections: [], environments: [ImportEnvironment(name: name, variables: variables)], globals: [], notes: [])
    }

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/collection-auth.spec.js
    // Differs from Bruno throughout: Raccoon has no Collection auth (auth `inherit`, or no auth on the
    // item). It is written onto each Request under the Collection, and these Collections have none.
    static let collectionAuth: [PostmanFixture] = [
        PostmanFixture("should handle no auth at collection level (when auth property is absent)", #"""
            {
              "info": {
                "name": "Collection level no auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [],
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Collection level no auth", [])),
        PostmanFixture("should handle basic auth at collection level", #"""
            {
              "info": {
                "name": "Collection level basic auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [],
              "auth": {
                "type": "basic",
                "basic": [
                  {"key": "password", "value": "testpass", "type": "string"},
                  {"key": "username", "value": "testuser", "type": "string"}
                ]
              },
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Collection level basic auth", [])),
        PostmanFixture("should handle bearer token auth at collection level", #"""
            {
              "info": {
                "name": "Collection level bearer token",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [],
              "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "token", "type": "string"}]},
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Collection level bearer token", [])),
        PostmanFixture("should handle API key auth at collection level", #"""
            {
              "info": {
                "name": "Collection level api key",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [],
              "auth": {
                "type": "apikey",
                "apikey": [
                  {"key": "value", "value": "apikey", "type": "string"},
                  {"key": "key", "value": "apikey", "type": "string"}
                ]
              },
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Collection level api key", [])),
        PostmanFixture("should handle digest auth at collection level", #"""
            {
              "info": {
                "name": "Collection level digest auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [],
              "auth": {
                "type": "digest",
                "digest": [
                  {"key": "password", "value": "digest auth", "type": "string"},
                  {"key": "username", "value": "digest auth", "type": "string"},
                  {"key": "algorithm", "value": "MD5", "type": "string"}
                ]
              },
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Collection level digest auth", [])),
        PostmanFixture("should handle missing auth values when auth.type exists", #"""
            {
              "info": {
                "name": "Collection with missing auth values",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [],
              "auth": {"type": "basic"},
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Collection with missing auth values", [])),
        PostmanFixture("should handle missing auth values for different auth types", #"""
            {
              "info": {
                "name": "Collection with missing auth values for different types",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [],
              "auth": {"type": "bearer"},
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Collection with missing auth values for different types", [])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/folder-auth.spec.js
    // Differs from Bruno throughout: Raccoon has no Folder auth (auth `inherit`, or no auth on the item).
    // It is written onto each Request under the Folder, and these Folders have none.
    static let folderAuth: [PostmanFixture] = [
        // Differs: the item has `items`, not `item`, so it is neither a folder nor a request: skipped and counted
        // (Rules carried over: an item with neither `item` nor `request`). Bruno makes it a folder.
        PostmanFixture("should handle \"Inherit Auth\" at folder level (auth property absent)", #"""
            {
              "info": {
                "name": "Folder Inherit Auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [{"name": "Inheriting Folder", "items": []}],
              "auth": {
                "type": "basic",
                "basic": [
                  {"key": "password", "value": "testpass", "type": "string"},
                  {"key": "username", "value": "testuser", "type": "string"}
                ]
              },
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Folder Inherit Auth", [], notes: [note(.itemsSkipped, "Inheriting Folder")])),
        PostmanFixture("should handle explicit \"No Auth\" at folder level", #"""
            {
              "info": {
                "name": "Folder No Auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [{"name": "No Auth Folder", "item": [], "auth": {"type": "noauth"}}],
              "auth": {
                "type": "basic",
                "basic": [
                  {"key": "password", "value": "testpass", "type": "string"},
                  {"key": "username", "value": "testuser", "type": "string"}
                ]
              },
              "event": [
                {"listen": "prerequest", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}},
                {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
              ]
            }
            """#, plan: imported("Folder No Auth", [.folder(name: "No Auth Folder", children: [])])),
        PostmanFixture("should handle basic auth at folder level", #"""
            {
              "info": {
                "name": "Folder level basic auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "folder",
                  "item": [],
                  "auth": {
                    "type": "basic",
                    "basic": [
                      {"key": "password", "value": "testpass", "type": "string"},
                      {"key": "username", "value": "testuser", "type": "string"}
                    ]
                  },
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {"type": "text/javascript", "packages": {}, "exec": [""]}
                    },
                    {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
                  ]
                }
              ]
            }
            """#, plan: imported("Folder level basic auth", [.folder(name: "folder", children: [])])),
        PostmanFixture("should handle bearer token auth at folder level", #"""
            {
              "info": {
                "name": "Folder level bearer token",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "folder",
                  "item": [],
                  "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "token", "type": "string"}]},
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {"type": "text/javascript", "packages": {}, "exec": [""]}
                    },
                    {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
                  ]
                }
              ]
            }
            """#, plan: imported("Folder level bearer token", [.folder(name: "folder", children: [])])),
        PostmanFixture("should handle API key auth at folder level", #"""
            {
              "info": {
                "name": "Folder level API key",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "folder",
                  "item": [],
                  "auth": {
                    "type": "apikey",
                    "apikey": [
                      {"key": "value", "value": "apikey", "type": "string"},
                      {"key": "key", "value": "apikey", "type": "string"}
                    ]
                  },
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {"type": "text/javascript", "packages": {}, "exec": [""]}
                    },
                    {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
                  ]
                }
              ]
            }
            """#, plan: imported("Folder level API key", [.folder(name: "folder", children: [])])),
        PostmanFixture("should handle digest auth at folder level", #"""
            {
              "info": {
                "name": "Folder level digest auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "folder",
                  "item": [],
                  "auth": {
                    "type": "digest",
                    "digest": [
                      {"key": "password", "value": "digest pass", "type": "string"},
                      {"key": "username", "value": "digest user", "type": "string"},
                      {"key": "algorithm", "value": "MD5", "type": "string"}
                    ]
                  },
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {"type": "text/javascript", "packages": {}, "exec": [""]}
                    },
                    {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
                  ]
                }
              ]
            }
            """#, plan: imported("Folder level digest auth", [.folder(name: "folder", children: [])])),
        PostmanFixture("should handle missing auth values in folder level auth", #"""
            {
              "info": {
                "name": "Folder with missing auth values",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "folder",
                  "item": [],
                  "auth": {"type": "basic"},
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {"type": "text/javascript", "packages": {}, "exec": [""]}
                    },
                    {"listen": "test", "script": {"type": "text/javascript", "packages": {}, "exec": [""]}}
                  ]
                }
              ]
            }
            """#, plan: imported("Folder with missing auth values", [.folder(name: "folder", children: [])])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/request-auth.spec.js
    // Differs from Bruno: where Bruno keeps `inherit`, the nearest Folder's or the Collection's auth is
    // written onto the Request and noted (auth `inherit`, or no auth on the item); oauth1 is none, noted
    // (auth `oauth1`, …); apikey is a header or a Param (auth `apikey`).
    static let requestAuth: [PostmanFixture] = [
        PostmanFixture("should handle basic auth at request level", #"""
            {
              "info": {
                "name": "Request Auth Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Basic Auth Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "auth": {
                      "type": "basic",
                      "basic": [{"key": "username", "value": "requestuser"}, {"key": "password", "value": "requestpass"}]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("Request Auth Collection", [planned(1, "Basic Auth Request", "GET", "https://api.example.com/test", auth: .basic(user: "requestuser", password: "requestpass"))])),
        PostmanFixture("should inherit folder auth when request has no auth", #"""
            {
              "info": {
                "name": "Inherit Request Auth Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Auth Folder",
                  "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "foldertoken"}]},
                  "item": [
                    {
                      "name": "Inherit Auth Request",
                      "request": {"method": "GET", "url": "https://api.example.com/test"}
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Inherit Request Auth Collection", [.folder(name: "Auth Folder", children: [planned(1, "Inherit Auth Request", "GET", "https://api.example.com/test", auth: .bearer(token: "foldertoken"))])], notes: [note(.authInherited, "Inherit Auth Request")])),
        PostmanFixture("should handle \"Inherit Auth\" for request (auth property absent, inherits from folder)", #"""
            {
              "info": {
                "name": "Request Inherit Auth from Folder",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Auth Folder",
                  "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "foldertoken"}]},
                  "item": [
                    {
                      "name": "Inheriting Request",
                      "request": {"method": "GET", "url": "https://api.example.com/test"}
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Request Inherit Auth from Folder", [.folder(name: "Auth Folder", children: [planned(1, "Inheriting Request", "GET", "https://api.example.com/test", auth: .bearer(token: "foldertoken"))])], notes: [note(.authInherited, "Inheriting Request")])),
        PostmanFixture("should handle \"Inherit Auth\" for request (auth property absent, inherits from collection if folder also inherits)", #"""
            {
              "info": {
                "name": "Request Inherit Auth from Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {
                "type": "basic",
                "basic": [{"key": "username", "value": "requestuser"}, {"key": "password", "value": "requestpass"}]
              },
              "item": [
                {
                  "name": "Inheriting Folder",
                  "item": [
                    {
                      "name": "Inheriting Request",
                      "request": {"method": "GET", "url": "https://api.example.com/test"}
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Request Inherit Auth from Collection", [.folder(name: "Inheriting Folder", children: [planned(1, "Inheriting Request", "GET", "https://api.example.com/test", auth: .basic(user: "requestuser", password: "requestpass"))])], notes: [note(.authInherited, "Inheriting Request")])),
        PostmanFixture("should handle explicit \"No Auth\" at request level", #"""
            {
              "info": {
                "name": "Request No Auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Auth Folder",
                  "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "foldertoken"}]},
                  "item": [
                    {
                      "name": "Explicit No Auth Request",
                      "request": {"method": "GET", "url": "https://api.example.com/test", "auth": {"type": "noauth"}}
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Request No Auth", [.folder(name: "Auth Folder", children: [planned(1, "Explicit No Auth Request", "GET", "https://api.example.com/test")])])),
        PostmanFixture("should handle \"Inherit Auth\" for a request nested under multiple inheriting folders", #"""
            {
              "info": {
                "name": "Multi-Level Inherit Auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {
                "type": "basic",
                "basic": [{"key": "username", "value": "collectionUser"}, {"key": "password", "value": "collectionPass"}]
              },
              "item": [
                {
                  "name": "Folder Level 1 (Inherit)",
                  "item": [
                    {
                      "name": "Folder Level 2 (Inherit)",
                      "item": [
                        {
                          "name": "Deeply Nested Request (Inherit)",
                          "request": {"method": "GET", "url": "https://api.example.com/deep"}
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Multi-Level Inherit Auth", [.folder(name: "Folder Level 1 (Inherit)", children: [.folder(name: "Folder Level 2 (Inherit)", children: [planned(1, "Deeply Nested Request (Inherit)", "GET", "https://api.example.com/deep", auth: .basic(user: "collectionUser", password: "collectionPass"))])])], notes: [note(.authInherited, "Deeply Nested Request (Inherit)")])),
        PostmanFixture("should handle \"Inherit Auth\" where an intermediate folder has explicit auth", #"""
            {
              "info": {
                "name": "Multi-Level Inherit with Override",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {
                "type": "basic",
                "basic": [{"key": "username", "value": "collectionUser"}, {"key": "password", "value": "collectionPass"}]
              },
              "item": [
                {
                  "name": "Folder Level 1 (Explicit Bearer)",
                  "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "folder1Token"}]},
                  "item": [
                    {
                      "name": "Folder Level 2 (Inherit from Folder 1)",
                      "item": [
                        {
                          "name": "Deeply Nested Request (Inherit from Folder 1 via Folder 2)",
                          "request": {"method": "GET", "url": "https://api.example.com/deep_override"}
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Multi-Level Inherit with Override", [.folder(name: "Folder Level 1 (Explicit Bearer)", children: [.folder(name: "Folder Level 2 (Inherit from Folder 1)", children: [planned(1, "Deeply Nested Request (Inherit from Folder 1 via Folder 2)", "GET", "https://api.example.com/deep_override", auth: .bearer(token: "folder1Token"))])])], notes: [note(.authInherited, "Deeply Nested Request (Inherit from Folder 1 via Folder 2)")])),
        PostmanFixture("should handle oauth1 auth with HMAC-SHA1 and placement query (addParamsToHeader false)", #"""
            {
              "info": {
                "name": "OAuth1 HMAC Query Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "OAuth1 HMAC Query Request",
                  "request": {
                    "method": "GET",
                    "url": "http://www.example.com",
                    "auth": {
                      "type": "oauth1",
                      "oauth1": [
                        {"key": "consumerKey", "value": "consumer_key", "type": "string"},
                        {"key": "consumerSecret", "value": "consumer_secret", "type": "string"},
                        {"key": "token", "value": "access_token", "type": "string"},
                        {"key": "tokenSecret", "value": "token_secret", "type": "string"},
                        {"key": "signatureMethod", "value": "HMAC-SHA1", "type": "string"},
                        {"key": "version", "value": "1.0", "type": "string"},
                        {"key": "addParamsToHeader", "value": false, "type": "boolean"},
                        {"key": "includeBodyHash", "value": true, "type": "boolean"},
                        {"key": "callback", "value": "https://www.example.com", "type": "string"},
                        {"key": "verifier", "value": "verifier", "type": "string"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("OAuth1 HMAC Query Collection", [planned(1, "OAuth1 HMAC Query Request", "GET", "http://www.example.com")], notes: [note(.authNotSupported(type: "oauth1"), "OAuth1 HMAC Query Request")])),
        PostmanFixture("should handle oauth1 auth with HMAC-SHA1 and placement header (addParamsToHeader true)", #"""
            {
              "info": {
                "name": "OAuth1 HMAC Header Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "OAuth1 HMAC Header Request",
                  "request": {
                    "method": "GET",
                    "url": "http://www.example.com",
                    "auth": {
                      "type": "oauth1",
                      "oauth1": [
                        {"key": "consumerKey", "value": "consumer_key", "type": "string"},
                        {"key": "consumerSecret", "value": "consumer_secret", "type": "string"},
                        {"key": "token", "value": "access_token", "type": "string"},
                        {"key": "tokenSecret", "value": "token_secret", "type": "string"},
                        {"key": "signatureMethod", "value": "HMAC-SHA1", "type": "string"},
                        {"key": "version", "value": "1.0", "type": "string"},
                        {"key": "addParamsToHeader", "value": true, "type": "boolean"},
                        {"key": "includeBodyHash", "value": true, "type": "boolean"},
                        {"key": "callback", "value": "https://www.example.com", "type": "string"},
                        {"key": "verifier", "value": "verifier", "type": "string"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("OAuth1 HMAC Header Collection", [planned(1, "OAuth1 HMAC Header Request", "GET", "http://www.example.com")], notes: [note(.authNotSupported(type: "oauth1"), "OAuth1 HMAC Header Request")])),
        PostmanFixture("should handle oauth1 auth with RSA-SHA1 and private key", #"""
            {
              "info": {
                "name": "OAuth1 RSA Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "OAuth1 RSA Request",
                  "request": {
                    "method": "GET",
                    "url": "http://www.example.com",
                    "auth": {
                      "type": "oauth1",
                      "oauth1": [
                        {"key": "consumerKey", "value": "consumer_key", "type": "string"},
                        {"key": "consumerSecret", "value": "consumer_secret", "type": "string"},
                        {"key": "token", "value": "access_token", "type": "string"},
                        {"key": "tokenSecret", "value": "token_secret", "type": "string"},
                        {"key": "signatureMethod", "value": "RSA-SHA1", "type": "string"},
                        {
                          "key": "privateKey",
                          "value": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg...\n-----END PRIVATE KEY-----",
                          "type": "string"
                        },
                        {"key": "version", "value": "1.0", "type": "string"},
                        {"key": "addParamsToHeader", "value": true, "type": "boolean"},
                        {"key": "includeBodyHash", "value": true, "type": "boolean"},
                        {"key": "callback", "value": "https://www.example.com", "type": "string"},
                        {"key": "verifier", "value": "verifier", "type": "string"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("OAuth1 RSA Collection", [planned(1, "OAuth1 RSA Request", "GET", "http://www.example.com")], notes: [note(.authNotSupported(type: "oauth1"), "OAuth1 RSA Request")])),
        PostmanFixture("should handle oauth1 auth at collection level", #"""
            {
              "info": {
                "name": "OAuth1 Collection Level",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {
                "type": "oauth1",
                "oauth1": [
                  {"key": "consumerKey", "value": "col_consumer_key", "type": "string"},
                  {"key": "consumerSecret", "value": "col_consumer_secret", "type": "string"},
                  {"key": "token", "value": "col_access_token", "type": "string"},
                  {"key": "tokenSecret", "value": "col_token_secret", "type": "string"},
                  {"key": "signatureMethod", "value": "HMAC-SHA1", "type": "string"},
                  {"key": "addParamsToHeader", "value": true, "type": "boolean"}
                ]
              },
              "item": [{"name": "Inheriting Request", "request": {"method": "GET", "url": "http://www.example.com"}}]
            }
            """#, plan: imported("OAuth1 Collection Level", [planned(1, "Inheriting Request", "GET", "http://www.example.com")], notes: [note(.authInherited, "Inheriting Request"), note(.authNotSupported(type: "oauth1"), "Inheriting Request")])),
        PostmanFixture("should handle \"Inherit Auth\" where an intermediate folder has explicit \"No Auth\"", #"""
            {
              "info": {
                "name": "Multi-Level Inherit with No Auth Stop",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {
                "type": "basic",
                "basic": [{"key": "username", "value": "collectionUser"}, {"key": "password", "value": "collectionPass"}]
              },
              "item": [
                {
                  "name": "Folder Level 1 (Explicit No Auth)",
                  "auth": {"type": "noauth"},
                  "item": [
                    {
                      "name": "Folder Level 2 (Inherit from Folder 1 - so No Auth)",
                      "item": [
                        {
                          "name": "Deeply Nested Request (Inherit from Folder 1 via Folder 2 - so No Auth)",
                          "request": {"method": "GET", "url": "https://api.example.com/deep_no_auth_stop"}
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Multi-Level Inherit with No Auth Stop", [.folder(name: "Folder Level 1 (Explicit No Auth)", children: [.folder(name: "Folder Level 2 (Inherit from Folder 1 - so No Auth)", children: [planned(1, "Deeply Nested Request (Inherit from Folder 1 via Folder 2 - so No Auth)", "GET", "https://api.example.com/deep_no_auth_stop")])])])),
        PostmanFixture("should map Postman in=query to Bruno placement=queryparams", #"""
            {
              "info": {
                "name": "API Key Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "API Key Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "auth": {
                      "type": "apikey",
                      "apikey": [
                        {"key": "key", "value": "X-API-Key"},
                        {"key": "value", "value": "secret-token"},
                        {"key": "in", "value": "query"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("API Key Collection", [planned(1, "API Key Request", "GET", "https://api.example.com/test", params: rows(("X-API-Key", "secret-token")))])),
        PostmanFixture("should map Postman in=header to Bruno placement=header", #"""
            {
              "info": {
                "name": "API Key Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "API Key Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "auth": {
                      "type": "apikey",
                      "apikey": [
                        {"key": "key", "value": "X-API-Key"},
                        {"key": "value", "value": "secret-token"},
                        {"key": "in", "value": "header"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("API Key Collection", [planned(1, "API Key Request", "GET", "https://api.example.com/test", headers: rows(("X-API-Key", "secret-token")))])),
        PostmanFixture("should default placement to header when Postman in is absent", #"""
            {
              "info": {
                "name": "API Key Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "API Key Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "auth": {
                      "type": "apikey",
                      "apikey": [{"key": "key", "value": "X-API-Key"}, {"key": "value", "value": "secret-token"}]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("API Key Collection", [planned(1, "API Key Request", "GET", "https://api.example.com/test", headers: rows(("X-API-Key", "secret-token")))])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/process-auth.spec.js
    // processAuth's tests pass an auth object alone; each is copied into `auth(_:_:)`, which puts it on
    // the one Request of a Collection that has no auth. Differs from Bruno: awsv4, digest, ntlm, oauth1,
    // oauth2, edgegrid and an unknown type are none, noted per type (auth `oauth2`, …); apikey is a
    // header (auth `apikey`), and with no key adds nothing; an auth with no type is none, as Bruno has it.
    static let processAuth: [PostmanFixture] = [
        auth("should handle no auth", #"null"#),
        auth("should handle noauth type", #"{"type":"noauth"}"#),
        auth("should handle basic auth", #"{"type":"basic","basic":[{"key":"username","value":"testuser","type":"string"},{"key":"password","value":"testpass","type":"string"}]}"#, auth: .basic(user: "testuser", password: "testpass")),
        auth("should handle basic auth with missing values", #"{"type":"basic","basic":{}}"#, auth: .basic(user: "", password: "")),
        auth("should handle basic auth with missing basic key", #"{"type":"basic"}"#, auth: .basic(user: "", password: "")),
        auth("should handle bearer auth", #"{"type":"bearer","bearer":{"token":"test-token"}}"#, auth: .bearer(token: "test-token")),
        auth("should handle bearer auth with missing values", #"{"type":"bearer","bearer":{}}"#, auth: .bearer(token: "")),
        auth("should handle bearer auth with missing bearer key", #"{"type":"bearer"}"#, auth: .bearer(token: "")),
        auth("should handle awsv4 auth", #"{"type":"awsv4","awsv4":{"accessKey":"test-access-key","secretKey":"test-secret-key","sessionToken":"test-session-token","service":"test-service","region":"test-region"}}"#, notSupported: "awsv4"),
        auth("should handle awsv4 auth with missing values", #"{"type":"awsv4","awsv4":{}}"#, notSupported: "awsv4"),
        auth("should handle awsv4 auth with missing awsv4 key", #"{"type":"awsv4"}"#, notSupported: "awsv4"),
        auth("should handle apikey auth", #"{"type":"apikey","apikey":{"key":"test-key","value":"test-value"}}"#, headers: rows(("test-key", "test-value"))),
        auth("should handle apikey auth with missing values", #"{"type":"apikey","apikey":{}}"#),
        auth("should handle apikey auth with missing apikey key", #"{"type":"apikey"}"#),
        auth("should handle digest auth", #"{"type":"digest","digest":{"username":"testuser","password":"testpass"}}"#, notSupported: "digest"),
        auth("should handle digest auth with missing values", #"{"type":"digest","digest":{}}"#, notSupported: "digest"),
        auth("should handle digest auth with missing digest key", #"{"type":"digest"}"#, notSupported: "digest"),
        auth("should handle ntlm auth", #"{"type":"ntlm","ntlm":{"username":"testuser","password":"testpass","domain":"testdomain"}}"#, notSupported: "ntlm"),
        auth("should handle ntlm auth with v2.1 array format", #"{"type":"ntlm","ntlm":[{"key":"username","value":"testuser","type":"string"},{"key":"password","value":"testpass","type":"string"},{"key":"domain","value":"testdomain","type":"string"}]}"#, notSupported: "ntlm"),
        auth("should handle ntlm auth with missing values", #"{"type":"ntlm","ntlm":{}}"#, notSupported: "ntlm"),
        auth("should handle ntlm auth with missing ntlm key", #"{"type":"ntlm"}"#, notSupported: "ntlm"),
        auth("should handle oauth2 auth with authorization_code grant type", #"{"type":"oauth2","oauth2":{"grant_type":"authorization_code","authUrl":"https://auth.example.com","redirect_uri":"https://callback.example.com","accessTokenUrl":"https://token.example.com","refreshTokenUrl":"https://refresh.example.com","clientId":"test-client-id","clientSecret":"test-client-secret","scope":"test-scope","state":"test-state","addTokenTo":"header","client_authentication":"body","tokenName":"test-token-name"}}"#, notSupported: "oauth2"),
        auth("should handle oauth2 auth with password_credentials grant type", #"{"type":"oauth2","oauth2":{"grant_type":"password_credentials","accessTokenUrl":"https://token.example.com","refreshTokenUrl":"https://refresh.example.com","username":"testuser","password":"testpass","clientId":"test-client-id","clientSecret":"test-client-secret","scope":"test-scope","state":"test-state","addTokenTo":"header","client_authentication":"body","tokenName":"test-token-name"}}"#, notSupported: "oauth2"),
        auth("should handle oauth2 auth with client_credentials grant type", #"{"type":"oauth2","oauth2":{"grant_type":"client_credentials","accessTokenUrl":"https://token.example.com","refreshTokenUrl":"https://refresh.example.com","clientId":"test-client-id","clientSecret":"test-client-secret","scope":"test-scope","state":"test-state","addTokenTo":"header","client_authentication":"body","tokenName":"test-token-name"}}"#, notSupported: "oauth2"),
        auth("should handle oauth2 auth with missing values", #"{"type":"oauth2","oauth2":{}}"#, notSupported: "oauth2"),
        auth("should handle oauth2 auth with missing oauth2 key", #"{"type":"oauth2"}"#, notSupported: "oauth2"),
        auth("should handle oauth2 auth with authorization_code_with_pkce grant type", #"{"type":"oauth2","oauth2":{"grant_type":"authorization_code_with_pkce","authUrl":"https://auth.example.com","redirect_uri":"https://callback.example.com","accessTokenUrl":"https://token.example.com","refreshTokenUrl":"https://refresh.example.com","clientId":"test-client-id","clientSecret":"test-client-secret","scope":"test-scope","state":"test-state","addTokenTo":"header","client_authentication":"body","tokenName":"test-token-name"}}"#, notSupported: "oauth2"),
        auth("should handle oauth2 auth with implicit grant type", #"{"type":"oauth2","oauth2":{"grant_type":"implicit","authUrl":"https://auth.example.com","redirect_uri":"https://callback.example.com","accessTokenUrl":"https://token.example.com","refreshTokenUrl":"https://refresh.example.com","clientId":"test-client-id","clientSecret":"test-client-secret","scope":"test-scope","state":"test-state","addTokenTo":"header","tokenHeaderPrefix":"Bearer","tokenQueryKey":"","client_authentication":"body","tokenName":"test-token-name"}}"#, notSupported: "oauth2"),
        auth("should default oauth2 token placement to the header when addTokenTo is absent", #"{"type":"oauth2","oauth2":[{"key":"grant_type","value":"client_credentials"},{"key":"accessTokenUrl","value":"https://token.example.com"}]}"#, notSupported: "oauth2"),
        auth("should default oauth2 tokenHeaderPrefix to Bearer when headerPrefix is absent and the token goes in the header", #"{"type":"oauth2","oauth2":[{"key":"grant_type","value":"client_credentials"},{"key":"accessTokenUrl","value":"https://token.example.com"},{"key":"addTokenTo","value":"header"}]}"#, notSupported: "oauth2"),
        auth("should preserve an explicit oauth2 headerPrefix", #"{"type":"oauth2","oauth2":[{"key":"grant_type","value":"client_credentials"},{"key":"addTokenTo","value":"header"},{"key":"headerPrefix","value":"Token"}]}"#, notSupported: "oauth2"),
        auth("should preserve an explicitly emptied oauth2 headerPrefix", #"{"type":"oauth2","oauth2":[{"key":"grant_type","value":"client_credentials"},{"key":"addTokenTo","value":"header"},{"key":"headerPrefix","value":""}]}"#, notSupported: "oauth2"),
        auth("should not default the oauth2 tokenHeaderPrefix when the token goes in the url", #"{"type":"oauth2","oauth2":[{"key":"grant_type","value":"client_credentials"},{"key":"addTokenTo","value":"queryParams"}]}"#, notSupported: "oauth2"),
        auth("should map oauth2 additionalParameters for authorization/token/refresh with send_as placements", #"{"type":"oauth2","oauth2":{"grant_type":"authorization_code","authUrl":"https://auth.example.com","redirect_uri":"https://callback.example.com","accessTokenUrl":"https://token.example.com","clientId":"test-client-id","authRequestParams":[{"key":"audience","value":"https://api.example.com","send_as":"request_url","enabled":true}],"tokenRequestParams":[{"key":"resource","value":"res-1","send_as":"request_body"}],"refreshRequestParams":[{"key":"x-refresh","value":"r-1","send_as":"request_header","enabled":false}]}}"#, notSupported: "oauth2"),
        auth("should default additionalParameters sendIn to headers and enabled to true when unspecified", #"{"type":"oauth2","oauth2":{"grant_type":"client_credentials","accessTokenUrl":"https://token.example.com","tokenRequestParams":[{"key":"a","value":"1"},{"key":"b","value":"2","send_as":"unknown_placement"}]}}"#, notSupported: "oauth2"),
        auth("should only include the additionalParameters keys that are present in the auth", #"{"type":"oauth2","oauth2":{"grant_type":"client_credentials","accessTokenUrl":"https://token.example.com","tokenRequestParams":[{"key":"scope_extra","value":"x","send_as":"request_body"}]}}"#, notSupported: "oauth2"),
        auth("should inject an empty authorization array for authorization_code grant when only other params are present", #"{"type":"oauth2","oauth2":{"grant_type":"authorization_code_with_pkce","authUrl":"https://auth.example.com","redirect_uri":"https://callback.example.com","accessTokenUrl":"https://token.example.com","tokenRequestParams":[{"key":"foo","value":"bar","send_as":"request_header"}]}}"#, notSupported: "oauth2"),
        auth("should omit additionalParameters entirely when no request-param arrays are present", #"{"type":"oauth2","oauth2":{"grant_type":"client_credentials","accessTokenUrl":"https://token.example.com"}}"#, notSupported: "oauth2"),
        auth("should handle auth object with undefined type", #"{}"#),
        auth("should handle type as null and auth as null", #"{"type":null,"auth":null}"#),
        auth("should handle auth object with undefined type, but basic auth", #"{"basic":[{"key":"username","value":"testuser","type":"string"},{"key":"password","value":"testpass","type":"string"}]}"#),
        auth("should handle auth object with null type", #"{"type":null}"#),
        auth("should handle auth object with empty string type", #"{"type":null,"basic":{"username":"testuser","password":"testpass"}}"#),
        auth("should handle auth object with boolean type value", #"{"type":"unknown_auth_type","unknown_auth_type":{"accessKey":"test-access-key","secretKey":"test-secret-key"}}"#, notSupported: "unknown_auth_type"),
        auth("should handle oauth1 auth with all fields (v2.1 object format)", #"{"type":"oauth1","oauth1":{"consumerKey":"test-consumer-key","consumerSecret":"test-consumer-secret","token":"test-token","tokenSecret":"test-token-secret","signatureMethod":"HMAC-SHA256","callback":"https://callback.example.com","verifier":"test-verifier","timestamp":"1234567890","nonce":"test-nonce","version":"1.0","realm":"test-realm","addParamsToHeader":true,"includeBodyHash":true,"privateKey":"test-private-key"}}"#, notSupported: "oauth1"),
        auth("should handle oauth1 auth with v2.1 array format", #"{"type":"oauth1","oauth1":[{"key":"consumerKey","value":"ck-array","type":"string"},{"key":"consumerSecret","value":"cs-array","type":"string"},{"key":"token","value":"tk-array","type":"string"},{"key":"tokenSecret","value":"ts-array","type":"string"},{"key":"signatureMethod","value":"HMAC-SHA1","type":"string"},{"key":"addParamsToHeader","value":false,"type":"boolean"}]}"#, notSupported: "oauth1"),
        auth("should handle oauth1 auth with missing values", #"{"type":"oauth1","oauth1":{}}"#, notSupported: "oauth1"),
        auth("should handle oauth1 auth with missing oauth1 key", #"{"type":"oauth1"}"#, notSupported: "oauth1"),
        auth("should handle oauth1 addParamsToHeader false as query", #"{"type":"oauth1","oauth1":{"consumerKey":"ck","addParamsToHeader":false}}"#, notSupported: "oauth1"),
        auth("should handle edgegrid auth (Postman v2.1 array form)", #"{"type":"edgegrid","edgegrid":[{"key":"accessToken","value":"akab-access-token","type":"string"},{"key":"clientToken","value":"akab-client-token","type":"string"},{"key":"clientSecret","value":"secret==","type":"string"},{"key":"baseURL","value":"https://akaa-x.luna.akamaiapis.net","type":"string"},{"key":"nonce","value":"my-nonce","type":"string"},{"key":"timestamp","value":"20240101T00:00:00+0000","type":"string"},{"key":"headersToSign","value":"X-Test1,X-Test2","type":"string"},{"key":"maxBodySize","value":"2048","type":"string"}]}"#, notSupported: "edgegrid"),
        auth("should handle edgegrid auth (object form)", #"{"type":"edgegrid","edgegrid":{"accessToken":"at","clientToken":"ct","clientSecret":"cs"}}"#, notSupported: "edgegrid"),
        auth("should handle edgegrid auth with missing edgegrid key", #"{"type":"edgegrid"}"#, notSupported: "edgegrid"),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/disabled-system-headers.spec.js
    // Differs from Bruno: `disabledSystemHeaders` is dropped (any other `protocolProfileBehavior`
    // key), where Bruno keeps it as omitted headers.
    static let disabledSystemHeaders: [PostmanFixture] = [
        PostmanFixture("should import disabled system headers from protocolProfileBehavior", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "POST",
                    "url": "https://api.example.com/test",
                    "header": [{"key": "Authorization", "value": "Bearer token", "disabled": false}]
                  },
                  "protocolProfileBehavior": {"disabledSystemHeaders": {"accept": true, "user-agent": true}}
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "POST", "https://api.example.com/test", headers: rows(("Authorization", "Bearer token")))])),
        PostmanFixture("should handle empty disabledSystemHeaders object", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {"method": "GET", "url": "https://api.example.com/test", "header": []},
                  "protocolProfileBehavior": {"disabledSystemHeaders": {}}
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/test")])),
        PostmanFixture("should handle null disabledSystemHeaders", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "header": [{"key": "Custom-Header", "value": "custom-value"}]
                  },
                  "protocolProfileBehavior": {"disabledSystemHeaders": null}
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/test", headers: rows(("Custom-Header", "custom-value")))])),
        PostmanFixture("should handle requests with no protocolProfileBehavior", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "header": [{"key": "X-Custom", "value": "test"}]
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/test", headers: rows(("X-Custom", "test")))])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/max-redirects.spec.js
    // Differs from Bruno throughout: `maxRedirects` is dropped without a note (any other
    // `protocolProfileBehavior` key), so no value is kept and none is warned about.
    static let maxRedirects: [PostmanFixture] = [
        PostmanFixture("should preserve a maxRedirects of 0", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 0},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should preserve a maxRedirects of 50", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 50},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should preserve a maxRedirects of 51", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 51},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should preserve a maxRedirects of 1000", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 1000},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should preserve a maxRedirects of 9007199254740991", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 9007199254740991},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should preserve a maxRedirects of 1e+21", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 1e+21},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should preserve a maxRedirects of 9.999999999998865e+21", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 9.999999999998865e+21},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should leave maxRedirects unset for protocolProfileBehavior {\"followRedirects\": true}", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"followRedirects": true},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should leave maxRedirects unset for protocolProfileBehavior undefined", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should truncate a fractional maxRedirects of 3.5 to 3", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 3.5},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should truncate a fractional maxRedirects of 0.9 to 0", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": 0.9},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of -1 and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": -1},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of \"100\" and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": "100"},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of \"abc\" and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": "abc"},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of \"\" and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": ""},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of true and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": true},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of [] and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": []},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of NaN and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": null},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of Infinity and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": null},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should drop a maxRedirects of null and warn instead of failing the import", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": {"maxRedirects": null},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        // Differs here and for the literal of 1 and 400 zeros below: Foundation's JSON parser rejects a number that overflows a Double, so
        // the file is not JSON to Raccoon and nothing is planned (What it reads). Postman writes no such
        // literal: JSON.stringify writes `null` for Infinity. -1e309 parses, so its file is planned.
        PostmanFixture("should warn for a maxRedirects literal of 1e309 that overflows to a non-finite number", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": { "maxRedirects": 1e309 },
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": { "raw": "https://example.com", "protocol": "https", "host": ["example", "com"] }
                  }
                }
              ]
            }
            """#, plan: ImportPlan(collections: [], environments: [], globals: [], notes: [])),
        PostmanFixture("should warn for a maxRedirects literal of -1e309 that overflows to a non-finite number", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": { "maxRedirects": -1e309 },
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": { "raw": "https://example.com", "protocol": "https", "host": ["example", "com"] }
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Req", "GET", "https://example.com")])),
        PostmanFixture("should warn for a maxRedirects literal of 1 and 400 zeros that overflows to a non-finite number", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Req",
                  "protocolProfileBehavior": { "maxRedirects": 10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 },
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": { "raw": "https://example.com", "protocol": "https", "host": ["example", "com"] }
                  }
                }
              ]
            }
            """#, plan: ImportPlan(collections: [], environments: [], globals: [], notes: [])),
        PostmanFixture("should import every sibling and report one issue per offending request", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "First Offender",
                  "protocolProfileBehavior": {"maxRedirects": -1},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                },
                {
                  "name": "Fine",
                  "protocolProfileBehavior": {"maxRedirects": 10},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                },
                {
                  "name": "Second Offender",
                  "protocolProfileBehavior": {"maxRedirects": "nope"},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "First Offender", "GET", "https://example.com"), planned(2, "Fine", "GET", "https://example.com"), planned(3, "Second Offender", "GET", "https://example.com")])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/partial-import.spec.js
    // Differs from Bruno: a request whose method is absent, `null` or empty is a GET (`request.method`),
    // where Bruno skips it and reports an error, so every request here is planned.
    static let partialImport: [PostmanFixture] = [
        PostmanFixture("should import valid items and skip items with missing method", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Valid Request 1",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                },
                {
                  "name": "Bad Request",
                  "request": {"method": null, "header": [], "url": {"raw": "https://example.com"}}
                },
                {
                  "name": "Valid Request 2",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Valid Request 1", "GET", "https://example.com"), planned(2, "Bad Request", "GET", "https://example.com"), planned(3, "Valid Request 2", "GET", "https://example.com")])),
        PostmanFixture("should record issues for nested folder items with full path", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "My Folder",
                  "item": [
                    {
                      "name": "Subfolder",
                      "item": [
                        {
                          "name": "Bad Nested",
                          "request": {"method": null, "header": [], "url": {"raw": "https://example.com"}}
                        },
                        {
                          "name": "Good Nested",
                          "request": {
                            "method": "GET",
                            "header": [],
                            "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Test Collection", [.folder(name: "My Folder", children: [.folder(name: "Subfolder", children: [planned(1, "Bad Nested", "GET", "https://example.com"), planned(2, "Good Nested", "GET", "https://example.com")])])])),
        PostmanFixture("should return empty issues array for valid collections", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Request 1",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                },
                {
                  "name": "Request 2",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Request 1", "GET", "https://example.com"), planned(2, "Request 2", "GET", "https://example.com")])),
        PostmanFixture("should handle empty collections with no issues", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": []
            }
            """#, plan: imported("Test Collection", [])),
        PostmanFixture("should handle all items being malformed without throwing", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Bad 1",
                  "request": {"method": null, "header": [], "url": {"raw": "https://example.com"}}
                },
                {"name": "Bad 2", "request": {"header": [], "url": {"raw": "https://example.com"}}}
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Bad 1", "GET", "https://example.com"), planned(2, "Bad 2", "GET", "https://example.com")])),
        // Differs: a `variable` that is not an array holds no variables (collection `variable`), so nothing
        // is added to Globals and there is nothing to warn about.
        PostmanFixture("should record warning for malformed collection-level variables", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Valid",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                }
              ],
              "variable": "not-an-array"
            }
            """#, plan: imported("Test Collection", [planned(1, "Valid", "GET", "https://example.com")])),
        PostmanFixture("should handle mixed valid/invalid items with folders and bad variables", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "r1",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                },
                {"name": "r2-missing-method", "request": {"header": [], "url": {"raw": "https://example.com"}}},
                {
                  "name": "r3",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                  }
                },
                {
                  "name": "API Folder",
                  "item": [
                    {
                      "name": "valid-in-folder",
                      "request": {
                        "method": "GET",
                        "header": [],
                        "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                      }
                    },
                    {
                      "name": "r4-null-method",
                      "request": {"method": null, "header": [], "url": {"raw": "https://example.com"}}
                    },
                    {
                      "name": "Nested Subfolder",
                      "item": [
                        {
                          "name": "r5-empty-method",
                          "request": {"method": "", "header": [], "url": {"raw": "https://example.com"}}
                        },
                        {
                          "name": "valid-nested",
                          "request": {
                            "method": "DELETE",
                            "header": [],
                            "url": {"raw": "https://example.com", "protocol": "https", "host": ["example", "com"]}
                          }
                        }
                      ]
                    }
                  ]
                }
              ],
              "variable": "not-an-array"
            }
            """#, plan: imported("Test Collection", [planned(1, "r1", "POST", "https://example.com"), planned(2, "r2-missing-method", "GET", "https://example.com"), planned(3, "r3", "POST", "https://example.com"), .folder(name: "API Folder", children: [planned(4, "valid-in-folder", "GET", "https://example.com"), planned(5, "r4-null-method", "GET", "https://example.com"), .folder(name: "Nested Subfolder", children: [planned(6, "r5-empty-method", "GET", "https://example.com"), planned(7, "valid-nested", "DELETE", "https://example.com")])])])),
        // Differs: the request with no name is named by its URL, as its Draft Tab would be titled (a request
        // item with an empty or blank `name`).
        PostmanFixture("should use fallback name for items without a name", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [{"request": {"method": null, "header": [], "url": {"raw": "https://example.com"}}}]
            }
            """#, plan: imported("Test Collection", [planned(1, "https://example.com", "GET", "https://example.com")])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/postman-to-bruno.spec.js
    static let postmanToBruno: [PostmanFixture] = [
        PostmanFixture("should correctly import a valid Postman collection file", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "simple collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "_exporter_id": "21992467",
                "_collection_link": "https://random-user-007.postman.co/workspace/testing~7523f559-3d5f-4c30-8315-3cb3c3ff98b7/collection/21992467-7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9?action=share&source=collection_link&creator=007"
              },
              "item": [
                {
                  "name": "folder",
                  "item": [
                    {
                      "name": "request",
                      "request": {
                        "method": "GET",
                        "header": [],
                        "url": {"raw": "https://usebruno.com", "protocol": "https", "host": ["usebruno", "com"]}
                      },
                      "response": []
                    }
                  ]
                },
                {
                  "name": "request",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://usebruno.com", "protocol": "https", "host": ["usebruno", "com"]}
                  },
                  "response": []
                }
              ]
            }
            """#, plan: imported("simple collection", [.folder(name: "folder", children: [planned(1, "request", "GET", "https://usebruno.com")]), planned(2, "request", "GET", "https://usebruno.com")])),
        // Differs: a variable with an empty or absent key is no variable and is dropped silently (a variable
        // `key` that is not a VariableName); Bruno keeps three with no name.
        PostmanFixture("should handle falsy values in collection variables", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with falsy vars",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [
                {"type": "string"},
                {"key": "", "type": "string"},
                {"value": "", "type": "string"},
                {"key": "", "value": "", "type": "string"}
              ],
              "item": []
            }
            """#, plan: imported("collection with falsy vars", [])),
        // Differs: `maxRedirects` and `disableUrlEncoding` are dropped (any other `protocolProfileBehavior`
        // key); the nameless variables are dropped (a variable `key` that is not a VariableName).
        PostmanFixture("should successfully translate a URL path array with no empty elements", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with falsy vars",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [
                {"type": "string"},
                {"key": "", "type": "string"},
                {"value": "", "type": "string"},
                {"key": "", "value": "", "type": "string"}
              ],
              "item": [
                {
                  "name": "Request with all settings",
                  "protocolProfileBehavior": {"maxRedirects": 10, "followRedirects": false, "disableUrlEncoding": true},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"protocol": "https", "host": ["httpbin", "org"], "path": ["api", "v1", "resource"]}
                  }
                }
              ]
            }
            """#, plan: imported("collection with falsy vars", [planned(1, "Request with all settings", "GET", "https://httpbin.org/api/v1/resource", redirects: false)])),
        PostmanFixture("should not mutate a URL path with an empty element representing a trailing slash", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with falsy vars",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [
                {"type": "string"},
                {"key": "", "type": "string"},
                {"value": "", "type": "string"},
                {"key": "", "value": "", "type": "string"}
              ],
              "item": [
                {
                  "name": "Request with all settings",
                  "protocolProfileBehavior": {"maxRedirects": 10, "followRedirects": false, "disableUrlEncoding": true},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"protocol": "https", "host": ["httpbin", "org"], "path": ["api", "v1", "resource", ""]}
                  }
                }
              ]
            }
            """#, plan: imported("collection with falsy vars", [planned(1, "Request with all settings", "GET", "https://httpbin.org/api/v1/resource/", redirects: false)])),
        PostmanFixture("should not mutate a URL path with an empty element representing a trailing slash (2)", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with falsy vars",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [
                {"type": "string"},
                {"key": "", "type": "string"},
                {"value": "", "type": "string"},
                {"key": "", "value": "", "type": "string"}
              ],
              "item": [
                {
                  "name": "Request with all settings",
                  "protocolProfileBehavior": {"maxRedirects": 10, "followRedirects": false, "disableUrlEncoding": true},
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"protocol": "https", "host": ["httpbin", "org"], "path": ["api", "", "resource"]}
                  }
                }
              ]
            }
            """#, plan: imported("collection with falsy vars", [planned(1, "Request with all settings", "GET", "https://httpbin.org/api//resource", redirects: false)])),
        PostmanFixture("should convert non-string variable values to strings", #"""
            {
              "info": {
                "name": "Non-String Variable Demo",
                "_postman_id": "abcd1234-5678-90ef-ghij-1234567890ab",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [
                {"key": "timeout", "value": 5000},
                {"key": "enabled", "value": true},
                {"key": "user", "value": {"id": 1, "name": "Alice"}}
              ],
              "item": [
                {
                  "name": "Sample Request",
                  "request": {
                    "method": "GET",
                    "url": {
                      "raw": "https://postman-echo.com/get",
                      "protocol": "https",
                      "host": ["postman-echo", "com"],
                      "path": ["get"]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("Non-String Variable Demo", [planned(1, "Sample Request", "GET", "https://postman-echo.com/get")], globals: [variable("timeout", "5000"), variable("enabled", "true"), variable("user", #"{"id":1,"name":"Alice"}"#)], notes: [note(.collectionVariables, "Non-String Variable Demo")])),
        PostmanFixture("should handle empty variables", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with falsy vars",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [],
              "item": []
            }
            """#, plan: imported("collection with falsy vars", [])),
        PostmanFixture("should preserve the disabled state of collection variables", #"""
            {
              "info": {
                "_postman_id": "c1d0e5a6-2b3c-4d5e-6f7a-8b9c0d1e2f3a",
                "name": "collection with disabled var",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [
                {"key": "enabledVar", "value": "value1"},
                {"key": "disabledVar", "value": "value2", "disabled": true},
                {"key": "explicitlyEnabledVar", "value": "value3", "disabled": false}
              ],
              "item": []
            }
            """#, plan: imported("collection with disabled var", [], globals: [variable("enabledVar", "value1"), variable("disabledVar", "value2", enabled: false), variable("explicitlyEnabledVar", "value3")], notes: [note(.collectionVariables, "collection with disabled var")])),
        // Differs: `maxRedirects`, `disableUrlEncoding` and `followAuthorizationHeader` are dropped (any other
        // `protocolProfileBehavior` key); only `followRedirects` is a Request Setting.
        PostmanFixture("should correctly import protocolProfileBehavior settings from Postman requests", #"""
            {
              "info": {
                "_postman_id": "test-settings-id",
                "name": "Collection with Settings",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Request with all settings",
                  "protocolProfileBehavior": {
                    "maxRedirects": 10,
                    "followRedirects": false,
                    "disableUrlEncoding": true,
                    "followAuthorizationHeader": true
                  },
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://echo.usebruno.com/get",
                      "protocol": "https",
                      "host": ["echo", "usebruno", "com"],
                      "path": ["get"]
                    }
                  }
                },
                {
                  "name": "Request with partial settings",
                  "protocolProfileBehavior": {"followRedirects": true},
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {
                      "raw": "https://echo.usebruno.com/post",
                      "protocol": "https",
                      "host": ["echo", "usebruno", "com"],
                      "path": ["post"]
                    }
                  }
                },
                {
                  "name": "Request without settings",
                  "request": {
                    "method": "PUT",
                    "header": [],
                    "url": {
                      "raw": "https://echo.usebruno.com/put",
                      "protocol": "https",
                      "host": ["echo", "usebruno", "com"],
                      "path": ["put"]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("Collection with Settings", [planned(1, "Request with all settings", "GET", "https://echo.usebruno.com/get", redirects: false), planned(2, "Request with partial settings", "POST", "https://echo.usebruno.com/post"), planned(3, "Request without settings", "PUT", "https://echo.usebruno.com/put")])),
        PostmanFixture("should handle collection with auth object having undefined type", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with undefined auth type",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {
                "basic": [
                  {"key": "username", "value": "testuser", "type": "string"},
                  {"key": "password", "value": "testpass", "type": "string"}
                ]
              },
              "item": [
                {
                  "name": "request",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://api.example.com/test",
                      "protocol": "https",
                      "host": ["api", "example", "com"],
                      "path": ["test"]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with undefined auth type", [planned(1, "request", "GET", "https://api.example.com/test")])),
        PostmanFixture("should handle collection with auth object having null type", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with null auth type",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {"type": null, "bearer": {"token": "test-token"}},
              "item": [
                {
                  "name": "request",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://api.example.com/test",
                      "protocol": "https",
                      "host": ["api", "example", "com"],
                      "path": ["test"]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with null auth type", [planned(1, "request", "GET", "https://api.example.com/test")])),
        // Differs: the request inherits an auth Raccoon does not know, so it is none and noted (auth
        // `inherit`, and auth `oauth2`, … for a type with no equivalent); Bruno makes it none silently.
        PostmanFixture("should handle collection with auth object having unexpected type value", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with unexpected auth type",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "auth": {
                "type": "unexpected_auth_type",
                "basic": [
                  {"key": "username", "value": "testuser", "type": "string"},
                  {"key": "password", "value": "testpass", "type": "string"}
                ]
              },
              "item": [
                {
                  "name": "request",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://api.example.com/test",
                      "protocol": "https",
                      "host": ["api", "example", "com"],
                      "path": ["test"]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with unexpected auth type", [planned(1, "request", "GET", "https://api.example.com/test")], notes: [note(.authInherited, "request"), note(.authNotSupported(type: "unexpected_auth_type"), "request")])),
        PostmanFixture("should handle request with auth object having undefined type", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with request undefined auth type",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://api.example.com/test",
                      "protocol": "https",
                      "host": ["api", "example", "com"],
                      "path": ["test"]
                    },
                    "auth": {
                      "basic": [
                        {"key": "username", "value": "testuser", "type": "string"},
                        {"key": "password", "value": "testpass", "type": "string"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with request undefined auth type", [planned(1, "request", "GET", "https://api.example.com/test")])),
        // Differs: as above, from the Folder.
        PostmanFixture("should handle folder with auth object having unexpected type", #"""
            {
              "info": {
                "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                "name": "collection with folder unexpected auth type",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "folder",
                  "auth": {"type": "unexpected_folder_auth_type", "bearer": {"token": "folder-token"}},
                  "item": [
                    {
                      "name": "request",
                      "request": {
                        "method": "GET",
                        "header": [],
                        "url": {
                          "raw": "https://api.example.com/test",
                          "protocol": "https",
                          "host": ["api", "example", "com"],
                          "path": ["test"]
                        }
                      }
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("collection with folder unexpected auth type", [.folder(name: "folder", children: [planned(1, "request", "GET", "https://api.example.com/test")])], notes: [note(.authInherited, "request"), note(.authNotSupported(type: "unexpected_folder_auth_type"), "request")])),
        PostmanFixture("should skip headers where both key and value are null, and coalesce partial nulls", #"""
            {
              "info": {
                "_postman_id": "test-null-headers",
                "name": "collection with null headers",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with null headers",
                  "request": {
                    "method": "GET",
                    "header": [
                      {"key": "Content-Type", "value": "application/json"},
                      {"key": null, "value": null},
                      {"key": null, "value": "somevalue"},
                      {"key": "X-Custom", "value": null}
                    ],
                    "url": {"raw": "https://example.com/api"}
                  }
                }
              ]
            }
            """#, plan: imported("collection with null headers", [planned(1, "request with null headers", "GET", "https://example.com/api", headers: rows(("Content-Type", "application/json"), ("", "somevalue"), ("X-Custom", "")))])),
        PostmanFixture("should skip urlencoded params where both key and value are null", #"""
            {
              "info": {
                "_postman_id": "test-null-urlencoded",
                "name": "collection with null urlencoded",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with null urlencoded",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/api"},
                    "body": {
                      "mode": "urlencoded",
                      "urlencoded": [
                        {"key": "field1", "value": "value1"},
                        {"key": null, "value": null},
                        {"key": null, "value": "partialvalue"},
                        {"key": "field2", "value": null}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with null urlencoded", [planned(1, "request with null urlencoded", "POST", "https://example.com/api", headers: [form], body: .formURLEncoded(rows(("field1", "value1"), ("", "partialvalue"), ("field2", ""))))])),
        PostmanFixture("should skip formdata params where both key and value are null", #"""
            {
              "info": {
                "_postman_id": "test-null-formdata",
                "name": "collection with null formdata",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with null formdata",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/api"},
                    "body": {
                      "mode": "formdata",
                      "formdata": [
                        {"key": "field1", "value": "value1", "type": "text"},
                        {"key": null, "value": null, "type": "text"},
                        {"key": "field2", "value": null, "type": "text"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with null formdata", [planned(1, "request with null formdata", "POST", "https://example.com/api", headers: [multipart], body: parts(("field1", .text("value1")), ("field2", .text(""))))])),
        PostmanFixture("should skip query params where both key and value are null", #"""
            {
              "info": {
                "_postman_id": "test-null-query-params",
                "name": "collection with null query params",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with null query params",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://example.com/api?search=test",
                      "protocol": "https",
                      "host": ["example", "com"],
                      "path": ["api"],
                      "query": [
                        {"key": "search", "value": "test"},
                        {"key": null, "value": null},
                        {"key": null, "value": "somevalue"},
                        {"key": "emptyval", "value": null}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with null query params", [planned(1, "request with null query params", "GET", "https://example.com/api", params: rows(("search", "test"), ("", "somevalue"), ("emptyval", "")))])),
        // Differs: `:accountId` is written into the path and noted (path variables `:id` with
        // `url.variable`); Bruno keeps it as a path Param.
        PostmanFixture("should convert numeric values to strings in headers, params, and body fields", #"""
            {
              "info": {
                "_postman_id": "test-numeric-values",
                "name": "collection with numeric values",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with numeric values",
                  "request": {
                    "method": "POST",
                    "header": [{"key": "X-Account-Id", "value": 0}, {"key": "X-Retry-Count", "value": 3}],
                    "url": {
                      "raw": "https://example.com/api/:accountId",
                      "protocol": "https",
                      "host": ["example", "com"],
                      "path": ["api", ":accountId"],
                      "query": [{"key": "limit", "value": 100}, {"key": "offset", "value": 0}],
                      "variable": [{"key": "accountId", "value": 0}]
                    },
                    "body": {"mode": "urlencoded", "urlencoded": [{"key": "timeout", "value": 5000}]}
                  }
                },
                {
                  "name": "request with numeric multipart form values",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {
                      "mode": "formdata",
                      "formdata": [
                        {"key": "retries", "value": 3, "type": "text"},
                        {"key": "priority", "value": 0, "type": "text"}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with numeric values", [planned(1, "request with numeric values", "POST", "https://example.com/api/0", params: rows(("limit", "100"), ("offset", "0")), headers: rows(("X-Account-Id", "0"), ("X-Retry-Count", "3")) + [form], body: .formURLEncoded(rows(("timeout", "5000")))), planned(2, "request with numeric multipart form values", "POST", "https://example.com/upload", headers: [multipart], body: parts(("retries", .text("3")), ("priority", .text("0"))))], notes: [note(.pathVariable, "request with numeric values")])),
        // Differs: the saved example is dropped and counted (`response`).
        PostmanFixture("should convert numeric values to strings in example request and response fields", #"""
            {
              "info": {
                "_postman_id": "test-numeric-examples",
                "name": "collection with numeric example values",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with numeric example",
                  "request": {"method": "GET", "header": [], "url": {"raw": "https://example.com/api"}},
                  "response": [
                    {
                      "name": "Example with numerics",
                      "originalRequest": {
                        "method": "GET",
                        "header": [{"key": "X-Account-Id", "value": 42}],
                        "url": {
                          "raw": "https://example.com/api/:id?page=1",
                          "protocol": "https",
                          "host": ["example", "com"],
                          "path": ["api", ":id"],
                          "query": [{"key": "page", "value": 1}],
                          "variable": [{"key": "id", "value": 99}]
                        },
                        "body": {"mode": "urlencoded", "urlencoded": [{"key": "retries", "value": 3}]}
                      },
                      "status": "OK",
                      "code": 200,
                      "header": [{"key": "X-RateLimit-Remaining", "value": 0}],
                      "body": "{\"ok\": true}"
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("collection with numeric example values", [planned(1, "request with numeric example", "GET", "https://example.com/api")], notes: [note(.examplesDropped, "request with numeric example")])),
        // Differs: the API key is a header (auth `apikey`).
        PostmanFixture("should convert numeric auth values to strings (array-backed v2.1 format)", #"""
            {
              "info": {
                "_postman_id": "test-numeric-auth",
                "name": "collection with numeric auth values",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with numeric bearer token",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com/api"},
                    "auth": {"type": "bearer", "bearer": [{"key": "token", "value": 123}]}
                  }
                },
                {
                  "name": "request with numeric apikey values",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com/api"},
                    "auth": {"type": "apikey", "apikey": [{"key": "key", "value": 456}, {"key": "value", "value": 789}]}
                  }
                }
              ]
            }
            """#, plan: imported("collection with numeric auth values", [planned(1, "request with numeric bearer token", "GET", "https://example.com/api", auth: .bearer(token: "123")), planned(2, "request with numeric apikey values", "GET", "https://example.com/api", headers: rows(("456", "789")))])),
        PostmanFixture("should convert numeric auth values to strings (object-backed format)", #"""
            {
              "info": {
                "_postman_id": "test-object-auth",
                "name": "collection with object-backed auth",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with object-backed basic auth",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {"raw": "https://example.com/api"},
                    "auth": {"type": "basic", "basic": {"username": 12345, "password": 67890}}
                  }
                }
              ]
            }
            """#, plan: imported("collection with object-backed auth", [planned(1, "request with object-backed basic auth", "GET", "https://example.com/api", auth: .basic(user: "12345", password: "67890"))])),
        PostmanFixture("should parse string headers in request header arrays", #"""
            {
              "info": {
                "_postman_id": "test-string-headers",
                "name": "collection with string headers",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with string headers",
                  "request": {
                    "method": "GET",
                    "header": [
                      "Content-Type: application/json",
                      {"key": "X-Custom", "value": "test"},
                      "Authorization: Bearer token123"
                    ],
                    "url": {"raw": "https://example.com/api"}
                  }
                }
              ]
            }
            """#, plan: imported("collection with string headers", [planned(1, "request with string headers", "GET", "https://example.com/api", headers: rows(("Content-Type", "application/json"), ("X-Custom", "test"), ("Authorization", "Bearer token123")))])),
        PostmanFixture("should parse a single concatenated string as the header field", #"""
            {
              "info": {
                "_postman_id": "test-concat-headers",
                "name": "collection with concatenated header string",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with concatenated header",
                  "request": {
                    "method": "GET",
                    "header": "Content-Type: application/json\r\nHost: example.com",
                    "url": {"raw": "https://example.com/api"}
                  }
                }
              ]
            }
            """#, plan: imported("collection with concatenated header string", [planned(1, "request with concatenated header", "GET", "https://example.com/api", headers: rows(("Content-Type", "application/json"), ("Host", "example.com")))])),
        // Differs: a Collection is recognised by its own `info.schema` (What it reads), so a file that wraps
        // one in `{"collection": …}` is not a Postman export Raccoon reads, and nothing is planned.
        PostmanFixture("should unwrap and import a Postman collection with { collection: { ... } } envelope", #"""
            {
              "collection": {
                "info": {
                  "_postman_id": "7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9",
                  "name": "simple collection",
                  "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                  "_exporter_id": "21992467",
                  "_collection_link": "https://random-user-007.postman.co/workspace/testing~7523f559-3d5f-4c30-8315-3cb3c3ff98b7/collection/21992467-7f91bbd8-cb97-41ac-8d0b-e1fcd8bb4ce9?action=share&source=collection_link&creator=007"
                },
                "item": [
                  {
                    "name": "folder",
                    "item": [
                      {
                        "name": "request",
                        "request": {
                          "method": "GET",
                          "header": [],
                          "url": {"raw": "https://usebruno.com", "protocol": "https", "host": ["usebruno", "com"]}
                        },
                        "response": []
                      }
                    ]
                  },
                  {
                    "name": "request",
                    "request": {
                      "method": "GET",
                      "header": [],
                      "url": {"raw": "https://usebruno.com", "protocol": "https", "host": ["usebruno", "com"]}
                    },
                    "response": []
                  }
                ]
              }
            }
            """#, plan: ImportPlan(collections: [], environments: [], globals: [], notes: [])),
        PostmanFixture("should handle string headers with no value", #"""
            {
              "info": {
                "_postman_id": "test-no-value-header",
                "name": "collection with no-value string header",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with no-value header",
                  "request": {"method": "GET", "header": ["X-No-Value"], "url": {"raw": "https://example.com/api"}}
                }
              ]
            }
            """#, plan: imported("collection with no-value string header", [planned(1, "request with no-value header", "GET", "https://example.com/api", headers: rows(("X-No-Value", "")))])),
        // Differs: the two paths are two file Parts named myFile (body `formdata`), the same bytes on the
        // wire as Bruno's one part with two values.
        PostmanFixture("should import formdata with type: file correctly", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with file formdata",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with file",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {
                      "mode": "formdata",
                      "formdata": [
                        {
                          "key": "myFile",
                          "type": "file",
                          "src": ["/path/to/file1.txt", "/path/to/file2.txt"],
                          "disabled": false
                        }
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with file formdata", [planned(1, "request with file", "POST", "https://example.com/upload", headers: [multipart], body: parts(("myFile", .file(path: "/path/to/file1.txt")), ("myFile", .file(path: "/path/to/file2.txt"))))])),
        PostmanFixture("should import formdata with type: default and src field as file", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with default type formdata",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with default type",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {
                      "mode": "formdata",
                      "formdata": [{"key": "myFile", "type": "default", "src": "/path/to/file.txt", "disabled": false}]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with default type formdata", [planned(1, "request with default type", "POST", "https://example.com/upload", headers: [multipart], body: parts(("myFile", .file(path: "/path/to/file.txt"))))])),
        // Differs: an array value is its JSON text (a value that is a number, … or an array); Bruno joins
        // the elements into "sometext".
        PostmanFixture("should import formdata with type: default and value array as text", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with default type and value array",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with default type",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {
                      "mode": "formdata",
                      "formdata": [{"key": "myField", "type": "default", "value": ["some", "text"], "disabled": false}]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with default type and value array", [planned(1, "request with default type", "POST", "https://example.com/upload", headers: [multipart], body: parts(("myField", .text(#"["some","text"]"#))))])),
        // Differs: the part's `contentType` is dropped (body `formdata`).
        PostmanFixture("should preserve contentType when importing formdata", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with contentType",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with contentType",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {
                      "mode": "formdata",
                      "formdata": [
                        {
                          "key": "myFile",
                          "type": "file",
                          "src": "/path/to/file.json",
                          "contentType": "application/json",
                          "disabled": false
                        }
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with contentType", [planned(1, "request with contentType", "POST", "https://example.com/upload", headers: [multipart], body: parts(("myFile", .file(path: "/path/to/file.json"))))])),
        PostmanFixture("should handle mixed file and text fields in formdata", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with mixed formdata",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "request with mixed fields",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {
                      "mode": "formdata",
                      "formdata": [
                        {"key": "textField", "type": "text", "value": "hello world", "disabled": false},
                        {"key": "fileField", "type": "file", "src": "/path/to/file.txt", "disabled": true}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("collection with mixed formdata", [planned(1, "request with mixed fields", "POST", "https://example.com/upload", headers: [multipart], body: .multipart([Part(name: "textField", content: .text("hello world")), Part(name: "fileField", isEnabled: false, content: .file(path: "/path/to/file.txt"))]))])),
        // Differs here and in the next five: a binary body is none, noted (body `file`); Bruno keeps the
        // path and guesses a Content-Type from its extension.
        PostmanFixture("should import a request with mode: file and preserve the file path", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with binary body",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "binary upload",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {"mode": "file", "file": {"src": "./binary-payload.bin"}}
                  }
                }
              ]
            }
            """#, plan: imported("collection with binary body", [planned(1, "binary upload", "POST", "https://example.com/upload")], notes: [note(.binaryBody, "binary upload")])),
        PostmanFixture("should import a Postman example with mode: file in originalRequest", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with binary example",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "binary upload",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {"mode": "file", "file": {"src": "./binary-payload.bin"}}
                  },
                  "response": [
                    {
                      "name": "Binary upload example",
                      "originalRequest": {
                        "method": "POST",
                        "header": [],
                        "url": {"raw": "https://example.com/upload"},
                        "body": {"mode": "file", "file": {"src": "./example-payload.bin"}}
                      },
                      "status": "Created",
                      "code": 201,
                      "header": [],
                      "body": ""
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("collection with binary example", [planned(1, "binary upload", "POST", "https://example.com/upload")], notes: [note(.binaryBody, "binary upload"), note(.examplesDropped, "binary upload")])),
        PostmanFixture("should infer contentType from the file extension of src", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with known extension",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "json upload",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {"mode": "file", "file": {"src": "./payload.json"}}
                  }
                }
              ]
            }
            """#, plan: imported("collection with known extension", [planned(1, "json upload", "POST", "https://example.com/upload")], notes: [note(.binaryBody, "json upload")])),
        PostmanFixture("should infer image/png for a .png file", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with png upload",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "png upload",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {"mode": "file", "file": {"src": "./avatar.png"}}
                  }
                }
              ]
            }
            """#, plan: imported("collection with png upload", [planned(1, "png upload", "POST", "https://example.com/upload")], notes: [note(.binaryBody, "png upload")])),
        PostmanFixture("should resolve application/octet-stream for a .bin file", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with bin upload",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "bin upload",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {"mode": "file", "file": {"src": "./binary-payload.bin"}}
                  }
                }
              ]
            }
            """#, plan: imported("collection with bin upload", [planned(1, "bin upload", "POST", "https://example.com/upload")], notes: [note(.binaryBody, "bin upload")])),
        PostmanFixture("should not throw when mode: file has no src", #"""
            {
              "info": {
                "_postman_id": "test-id",
                "name": "collection with missing src",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "binary upload without file",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": {"raw": "https://example.com/upload"},
                    "body": {"mode": "file"}
                  }
                }
              ]
            }
            """#, plan: imported("collection with missing src", [planned(1, "binary upload without file", "POST", "https://example.com/upload")], notes: [note(.binaryBody, "binary upload without file")])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-to-bruno/transform-description.spec.js
    // Differs from Bruno throughout: a Collection's, Folder's or Request's description is dropped and
    // counted, and a header's, Param's, path variable's or body field's is dropped without a note
    // (`response`, `description`). Bruno keeps them as docs.
    static let transformDescription: [PostmanFixture] = [
        PostmanFixture("should handle null and undefined descriptions", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "description": null
              },
              "item": []
            }
            """#, plan: imported("Test Collection", [])),
        PostmanFixture("should handle string descriptions (legacy format)", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "description": "This is a string description"
              },
              "item": []
            }
            """#, plan: imported("Test Collection", [], notes: [note(.descriptionsDropped, "Test Collection")])),
        PostmanFixture("should handle object descriptions with content property (new Postman format)", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "description": {"content": "This is the content from the new Postman format", "type": "text/plain"}
              },
              "item": []
            }
            """#, plan: imported("Test Collection", [], notes: [note(.descriptionsDropped, "Test Collection")])),
        PostmanFixture("should handle object descriptions without content property", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "description": {"type": "text/plain"}
              },
              "item": []
            }
            """#, plan: imported("Test Collection", [])),
        PostmanFixture("should handle request descriptions with new format", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "description": {"content": "This is a request description in new format", "type": "text/plain"}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/test")], notes: [note(.descriptionsDropped, "Test Request")])),
        PostmanFixture("should handle folder descriptions with new format", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Folder",
                  "description": {"content": "This is a folder description in new format", "type": "text/plain"},
                  "item": []
                }
              ]
            }
            """#, plan: imported("Test Collection", [.folder(name: "Test Folder", children: [])], notes: [note(.descriptionsDropped, "Test Folder")])),
        PostmanFixture("should handle header descriptions with new format", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "header": [
                      {
                        "key": "Authorization",
                        "value": "Bearer token",
                        "description": {"content": "Authorization header description", "type": "text/plain"}
                      }
                    ]
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/test", headers: rows(("Authorization", "Bearer token")))])),
        PostmanFixture("should handle query parameter descriptions with new format", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "GET",
                    "url": {
                      "raw": "https://api.example.com/test?param=value",
                      "host": ["api", "example", "com"],
                      "path": ["test"],
                      "query": [
                        {
                          "key": "param",
                          "value": "value",
                          "description": {"content": "Query parameter description", "type": "text/plain"}
                        }
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/test", params: rows(("param", "value")))])),
        PostmanFixture("should handle path variable descriptions with new format", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "GET",
                    "url": {
                      "raw": "https://api.example.com/users/:id",
                      "host": ["api", "example", "com"],
                      "path": ["users", ":id"],
                      "variable": [
                        {
                          "key": "id",
                          "value": "123",
                          "description": {"content": "User ID path variable", "type": "text/plain"}
                        }
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/users/123")], notes: [note(.pathVariable, "Test Request")])),
        PostmanFixture("should handle form data descriptions with new format", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "POST",
                    "url": "https://api.example.com/test",
                    "body": {
                      "mode": "formdata",
                      "formdata": [
                        {
                          "key": "field1",
                          "value": "value1",
                          "description": {"content": "Form field description", "type": "text/plain"}
                        }
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "POST", "https://api.example.com/test", headers: [multipart], body: parts(("field1", .text("value1"))))])),
        PostmanFixture("should handle urlencoded form descriptions with new format", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "POST",
                    "url": "https://api.example.com/test",
                    "body": {
                      "mode": "urlencoded",
                      "urlencoded": [
                        {
                          "key": "field1",
                          "value": "value1",
                          "description": {"content": "URL encoded field description", "type": "text/plain"}
                        }
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "POST", "https://api.example.com/test", headers: [form], body: .formURLEncoded(rows(("field1", "value1"))))])),
        PostmanFixture("should handle mixed description formats in the same collection", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "description": "Collection with string description"
              },
              "item": [
                {
                  "name": "Test Folder",
                  "description": {"content": "Folder with object description", "type": "text/plain"},
                  "item": [
                    {
                      "name": "Test Request",
                      "request": {
                        "method": "GET",
                        "url": "https://api.example.com/test",
                        "description": "Request with string description",
                        "header": [
                          {
                            "key": "Content-Type",
                            "value": "application/json",
                            "description": {"content": "Header with object description", "type": "text/plain"}
                          }
                        ]
                      }
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Test Collection", [.folder(name: "Test Folder", children: [planned(1, "Test Request", "GET", "https://api.example.com/test", headers: rows(("Content-Type", "application/json")))])], notes: [note(.descriptionsDropped, "Test Collection", "Test Folder", "Test Request")])),
        PostmanFixture("should handle edge cases like empty strings and special characters", #"""
            {
              "info": {
                "name": "Test Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "description": {"content": "", "type": "text/plain"}
              },
              "item": [
                {
                  "name": "Test Request",
                  "request": {
                    "method": "GET",
                    "url": "https://api.example.com/test",
                    "description": {"content": "Description with special chars: !@#$%^&*()", "type": "text/plain"}
                  }
                }
              ]
            }
            """#, plan: imported("Test Collection", [planned(1, "Test Request", "GET", "https://api.example.com/test")], notes: [note(.descriptionsDropped, "Test Request")])),
    ]

    // bruno/packages/bruno-converters/tests/postman/postman-env-to-bruno-env.spec.js
    static let environments: [PostmanFixture] = [
        // The secret keeps its value for the Keychain (environment value with `type: "secret"`).
        PostmanFixture("should correctly import a valid Postman environment file", #"""
            {
              "id": "some-id",
              "name": "My Environment",
              "values": [
                {"key": "var1", "value": "value1", "enabled": true, "type": "text"},
                {"key": "var2", "value": "value2", "enabled": false, "type": "secret"}
              ]
            }
            """#, plan: environment("My Environment", [variable("var1", "value1"), ImportVariable(name: VariableName("var2")!, isEnabled: false, value: .secret("value2"))])),
        // Differs: a variable with an empty or absent key is no variable and is dropped silently (a variable
        // `key` that is not a VariableName); Bruno keeps three with no name.
        PostmanFixture("should handle falsy values in environment variables", #"""
            {
              "id": "some-id",
              "name": "My Environment",
              "values": [
                {"enabled": true, "type": "text"},
                {"value": "", "enabled": true, "type": "text"},
                {"key": "", "enabled": true, "type": "text"},
                {"key": "", "value": "", "enabled": true, "type": "text"}
              ]
            }
            """#, plan: environment("My Environment", [])),
        PostmanFixture("should default enabled to true when Postman omits or nulls it", #"""
            {
              "id": "some-id",
              "name": "My Environment",
              "values": [
                {"key": "noEnabled", "value": "value1", "type": "default"},
                {"key": "nullEnabled", "value": "value2", "enabled": null, "type": "default"}
              ]
            }
            """#, plan: environment("My Environment", [variable("noEnabled", "value1"), variable("nullEnabled", "value2")])),
        PostmanFixture("should handle empty variables (2)", #"""
            {"name": "My Environment", "values": []}
            """#, plan: environment("My Environment", [])),
        // Differs: a file with a `name` and no `values` and no `_postman_variable_scope` is not an
        // Environment (What it reads), so nothing is planned.
        PostmanFixture("should handle undefined variables", #"""
            {"name": "My Environment"}
            """#, plan: ImportPlan(collections: [], environments: [], globals: [], notes: [])),
    ]

    // bruno/packages/bruno-converters/tests/postman/edgegrid-auth.spec.js
    static let edgegrid: [PostmanFixture] = [
        // Differs: EdgeGrid is none, noted (auth `oauth2`, …, `edgegrid`).
        PostmanFixture("imports edgegrid auth at request level with all credentials", #"""
            {
              "info": {"name": "C", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
              "item": [
                {
                  "name": "EdgeGrid Request",
                  "request": {
                    "method": "GET",
                    "url": "https://akaa-x.luna.akamaiapis.net/identity/v1",
                    "auth": {
                      "type": "edgegrid",
                      "edgegrid": [
                        {"key": "accessToken", "value": "akab-access-token"},
                        {"key": "clientToken", "value": "akab-client-token"},
                        {"key": "clientSecret", "value": "secret=="},
                        {"key": "baseURL", "value": "https://akaa-x.luna.akamaiapis.net"},
                        {"key": "nonce", "value": "my-nonce"},
                        {"key": "timestamp", "value": "20240101T00:00:00+0000"},
                        {"key": "headersToSign", "value": "X-Test1,X-Test2"},
                        {"key": "maxBodySize", "value": 2048}
                      ]
                    }
                  }
                }
              ]
            }
            """#, plan: imported("C", [planned(1, "EdgeGrid Request", "GET", "https://akaa-x.luna.akamaiapis.net/identity/v1")], notes: [note(.authNotSupported(type: "edgegrid"), "EdgeGrid Request")])),
    ]

    // bruno/packages/bruno-converters/tests/postman/preserve-scripts.spec.js
    // Differs from Bruno throughout: scripts are dropped and counted, a Folder's or the Collection's on
    // every Request under it (`event`); Raccoon runs no scripts, so there is nothing to preserve or
    // translate, and the import options of the first four make no difference.
    static let preserveScripts: [PostmanFixture] = [
        PostmanFixture("should keep pre-request and test scripts as-is instead of translating pm.* to bru.*", #"""
            {
              "info": {
                "_postman_id": "preserve-scripts-test",
                "name": "Preserve Scripts Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [{"key": "token", "value": "abc123"}],
              "item": [
                {
                  "name": "Get User",
                  "request": {"method": "GET", "url": "https://example.com/users"},
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.environment.set('token', '123')", "console.log('pre')"]
                      }
                    },
                    {
                      "listen": "test",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.test('status is 200', function () {", "  pm.response.to.have.status(200);", "});"]
                      }
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Preserve Scripts Collection", [planned(1, "Get User", "GET", "https://example.com/users")], globals: [variable("token", "abc123")], notes: [note(.scriptsDropped, "Get User"), note(.collectionVariables, "Preserve Scripts Collection")])),
        PostmanFixture("should convert the collection metadata, requests, and variables", #"""
            {
              "info": {
                "_postman_id": "preserve-scripts-test",
                "name": "Preserve Scripts Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [{"key": "token", "value": "abc123"}],
              "item": [
                {
                  "name": "Get User",
                  "request": {"method": "GET", "url": "https://example.com/users"},
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.environment.set('token', '123')", "console.log('pre')"]
                      }
                    },
                    {
                      "listen": "test",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.test('status is 200', function () {", "  pm.response.to.have.status(200);", "});"]
                      }
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Preserve Scripts Collection", [planned(1, "Get User", "GET", "https://example.com/users")], globals: [variable("token", "abc123")], notes: [note(.scriptsDropped, "Get User"), note(.collectionVariables, "Preserve Scripts Collection")])),
        PostmanFixture("should translate scripts to bru.* by default when the option is not enabled", #"""
            {
              "info": {
                "_postman_id": "preserve-scripts-test",
                "name": "Preserve Scripts Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [{"key": "token", "value": "abc123"}],
              "item": [
                {
                  "name": "Get User",
                  "request": {"method": "GET", "url": "https://example.com/users"},
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.environment.set('token', '123')", "console.log('pre')"]
                      }
                    },
                    {
                      "listen": "test",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.test('status is 200', function () {", "  pm.response.to.have.status(200);", "});"]
                      }
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Preserve Scripts Collection", [planned(1, "Get User", "GET", "https://example.com/users")], globals: [variable("token", "abc123")], notes: [note(.scriptsDropped, "Get User"), note(.collectionVariables, "Preserve Scripts Collection")])),
        PostmanFixture("should keep scripts as is even when the worker path is used", #"""
            {
              "info": {
                "_postman_id": "preserve-scripts-test",
                "name": "Preserve Scripts Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "variable": [{"key": "token", "value": "abc123"}],
              "item": [
                {
                  "name": "Get User",
                  "request": {"method": "GET", "url": "https://example.com/users"},
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.environment.set('token', '123')", "console.log('pre')"]
                      }
                    },
                    {
                      "listen": "test",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["pm.test('status is 200', function () {", "  pm.response.to.have.status(200);", "});"]
                      }
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Preserve Scripts Collection", [planned(1, "Get User", "GET", "https://example.com/users")], globals: [variable("token", "abc123")], notes: [note(.scriptsDropped, "Get User"), note(.collectionVariables, "Preserve Scripts Collection")])),
        PostmanFixture("should leave pm.require() and require() calls untouched", #"""
            {
              "info": {
                "_postman_id": "preserve-require-test",
                "name": "Require Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "item": [
                {
                  "name": "Uses packages",
                  "request": {"method": "GET", "url": "https://example.com"},
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {
                        "type": "text/javascript",
                        "exec": ["const _ = pm.require('lodash');", "const axios = require('axios');"]
                      }
                    }
                  ]
                }
              ]
            }
            """#, plan: imported("Require Collection", [planned(1, "Uses packages", "GET", "https://example.com")], notes: [note(.scriptsDropped, "Uses packages")])),
        PostmanFixture("should keep collection level scripts as is", #"""
            {
              "info": {
                "_postman_id": "preserve-nested-test",
                "name": "Nested Scripts Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "event": [
                {
                  "listen": "prerequest",
                  "script": {"type": "text/javascript", "exec": ["pm.environment.set('collectionVar', '1')"]}
                },
                {
                  "listen": "test",
                  "script": {"type": "text/javascript", "exec": ["pm.test('collection-level test', function () {});"]}
                }
              ],
              "item": [
                {
                  "name": "Auth Folder",
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {"type": "text/javascript", "exec": ["pm.variables.set('folderVar', '2')"]}
                    },
                    {
                      "listen": "test",
                      "script": {"type": "text/javascript", "exec": ["pm.expect(true).to.be.true;"]}
                    }
                  ],
                  "item": [{"name": "Login", "request": {"method": "POST", "url": "https://example.com/login"}}]
                }
              ]
            }
            """#, plan: imported("Nested Scripts Collection", [.folder(name: "Auth Folder", children: [planned(1, "Login", "POST", "https://example.com/login")])], notes: [note(.scriptsDropped, "Login")])),
        PostmanFixture("should keep folder level scripts as is", #"""
            {
              "info": {
                "_postman_id": "preserve-nested-test",
                "name": "Nested Scripts Collection",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
              },
              "event": [
                {
                  "listen": "prerequest",
                  "script": {"type": "text/javascript", "exec": ["pm.environment.set('collectionVar', '1')"]}
                },
                {
                  "listen": "test",
                  "script": {"type": "text/javascript", "exec": ["pm.test('collection-level test', function () {});"]}
                }
              ],
              "item": [
                {
                  "name": "Auth Folder",
                  "event": [
                    {
                      "listen": "prerequest",
                      "script": {"type": "text/javascript", "exec": ["pm.variables.set('folderVar', '2')"]}
                    },
                    {
                      "listen": "test",
                      "script": {"type": "text/javascript", "exec": ["pm.expect(true).to.be.true;"]}
                    }
                  ],
                  "item": [{"name": "Login", "request": {"method": "POST", "url": "https://example.com/login"}}]
                }
              ]
            }
            """#, plan: imported("Nested Scripts Collection", [.folder(name: "Auth Folder", children: [planned(1, "Login", "POST", "https://example.com/login")])], notes: [note(.scriptsDropped, "Login")])),
    ]
}
