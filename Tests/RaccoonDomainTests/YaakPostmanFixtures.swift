// The inputs below are copied from Yaak's Postman importer tests: the four fixture files in
// yaak/plugins/importer-postman/tests/fixtures, each named after its file, and the inline
// collections of yaak/plugins/importer-postman/tests/index.test.ts, each named after its Yaak
// test. The expected outputs are rewritten as Raccoon's ImportPlan; where Raccoon differs on
// purpose, the comment names the row of design/entry-points/postman.md that says why.
//
// MIT License
//
// Copyright (c) 2024 Yaak
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

enum YaakPostmanFixtures {
    static let all: [PostmanFixture] = [auth, nested, params, dynamicVariables] + inline

    private static let echo = "https://yaak.app/x/echo"
    private static let json = rows(("Content-Type", "application/json"))
    private static let hello = Body.raw(.json, "{\n    \"hello\": \"world\"\n}")

    // Differs from Yaak's output, each by a row of the mapping:
    // - "Inherit" and "Folder Child Inherit" get the Collection's and the Folder's auth written
    //   onto them, noted (auth `inherit`, or no auth on the item). Raccoon has no Collection or
    //   Folder auth, so Yaak's workspace and folder auth have no place of their own.
    // - oauth2, awsv4, jwt, digest, ntlm and oauth1 are none, noted per type (auth `oauth2`, …).
    // - API Key is a Param named X-API-Key (auth `apikey`), not an auth of its own.
    // - `{{vault:hello}}` is left as typed (`{{name}}`); Yaak rewrites it to `${[hello]}`.
    // - "COLLECTION VARIABLE" is dropped and listed (a variable `key` that is not a
    //   VariableName); Yaak keeps it in its global environment.
    static let auth = PostmanFixture("auth", #"""
        {
          "info": {
            "_postman_id": "9e6dfada-256c-49ea-a38f-7d1b05b7ca2d",
            "name": "Authentication",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
            "_exporter_id": "18798"
          },
          "item": [
            {
              "name": "No Auth",
              "request": {
                "auth": {
                  "type": "noauth"
                },
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "Inherit",
              "request": {
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "OAuth 2 Auth Code",
              "protocolProfileBehavior": {
                "disableBodyPruning": true
              },
              "request": {
                "auth": {
                  "type": "oauth2",
                  "oauth2": [
                    {
                      "key": "grant_type",
                      "value": "authorization_code",
                      "type": "string"
                    },
                    {
                      "key": "headerPrefix",
                      "value": "Bearer",
                      "type": "string"
                    },
                    {
                      "key": "client_authentication",
                      "value": "header",
                      "type": "string"
                    },
                    {
                      "key": "challengeAlgorithm",
                      "value": "S256",
                      "type": "string"
                    },
                    {
                      "key": "refreshTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "state",
                      "value": "state",
                      "type": "string"
                    },
                    {
                      "key": "scope",
                      "value": "scope",
                      "type": "string"
                    },
                    {
                      "key": "code_verifier",
                      "value": "verifier",
                      "type": "string"
                    },
                    {
                      "key": "clientSecret",
                      "value": "clientsecet",
                      "type": "string"
                    },
                    {
                      "key": "clientId",
                      "value": "cliend id",
                      "type": "string"
                    },
                    {
                      "key": "authUrl",
                      "value": "https://github.com/login/oauth/authorize",
                      "type": "string"
                    },
                    {
                      "key": "accessTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "useBrowser",
                      "value": true,
                      "type": "boolean"
                    },
                    {
                      "key": "redirect_uri",
                      "value": "https://callback",
                      "type": "string"
                    },
                    {
                      "key": "tokenName",
                      "value": "name",
                      "type": "string"
                    },
                    {
                      "key": "addTokenTo",
                      "value": "header",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "body": {
                  "mode": "raw",
                  "raw": "{\n    \"hello\": \"world\"\n}",
                  "options": {
                    "raw": {
                      "language": "json"
                    }
                  }
                },
                "url": {
                  "raw": "{{vault:hello}}",
                  "host": ["{{vault:hello}}"]
                }
              },
              "response": []
            },
            {
              "name": "OAuth 2 Auth Code (PKCE)",
              "protocolProfileBehavior": {
                "disableBodyPruning": true
              },
              "request": {
                "auth": {
                  "type": "oauth2",
                  "oauth2": [
                    {
                      "key": "headerPrefix",
                      "value": "Bearer",
                      "type": "string"
                    },
                    {
                      "key": "client_authentication",
                      "value": "header",
                      "type": "string"
                    },
                    {
                      "key": "challengeAlgorithm",
                      "value": "S256",
                      "type": "string"
                    },
                    {
                      "key": "refreshTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "state",
                      "value": "state",
                      "type": "string"
                    },
                    {
                      "key": "scope",
                      "value": "scope",
                      "type": "string"
                    },
                    {
                      "key": "code_verifier",
                      "value": "verifier",
                      "type": "string"
                    },
                    {
                      "key": "grant_type",
                      "value": "authorization_code_with_pkce",
                      "type": "string"
                    },
                    {
                      "key": "clientSecret",
                      "value": "clientsecet",
                      "type": "string"
                    },
                    {
                      "key": "clientId",
                      "value": "cliend id",
                      "type": "string"
                    },
                    {
                      "key": "authUrl",
                      "value": "https://github.com/login/oauth/authorize",
                      "type": "string"
                    },
                    {
                      "key": "accessTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "useBrowser",
                      "value": true,
                      "type": "boolean"
                    },
                    {
                      "key": "redirect_uri",
                      "value": "https://callback",
                      "type": "string"
                    },
                    {
                      "key": "tokenName",
                      "value": "name",
                      "type": "string"
                    },
                    {
                      "key": "addTokenTo",
                      "value": "header",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "body": {
                  "mode": "raw",
                  "raw": "{\n    \"hello\": \"world\"\n}",
                  "options": {
                    "raw": {
                      "language": "json"
                    }
                  }
                },
                "url": {
                  "raw": "{{vault:hello}}",
                  "host": ["{{vault:hello}}"]
                }
              },
              "response": []
            },
            {
              "name": "OAuth 2 Implicit",
              "protocolProfileBehavior": {
                "disableBodyPruning": true
              },
              "request": {
                "auth": {
                  "type": "oauth2",
                  "oauth2": [
                    {
                      "key": "client_authentication",
                      "value": "header",
                      "type": "string"
                    },
                    {
                      "key": "redirect_uri",
                      "value": "https://yaak.app/x/echo",
                      "type": "string"
                    },
                    {
                      "key": "useBrowser",
                      "value": false,
                      "type": "boolean"
                    },
                    {
                      "key": "grant_type",
                      "value": "implicit",
                      "type": "string"
                    },
                    {
                      "key": "headerPrefix",
                      "value": "Bearer",
                      "type": "string"
                    },
                    {
                      "key": "challengeAlgorithm",
                      "value": "S256",
                      "type": "string"
                    },
                    {
                      "key": "refreshTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "state",
                      "value": "state",
                      "type": "string"
                    },
                    {
                      "key": "scope",
                      "value": "scope",
                      "type": "string"
                    },
                    {
                      "key": "code_verifier",
                      "value": "verifier",
                      "type": "string"
                    },
                    {
                      "key": "clientSecret",
                      "value": "clientsecet",
                      "type": "string"
                    },
                    {
                      "key": "clientId",
                      "value": "cliend id",
                      "type": "string"
                    },
                    {
                      "key": "authUrl",
                      "value": "https://github.com/login/oauth/authorize",
                      "type": "string"
                    },
                    {
                      "key": "accessTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "tokenName",
                      "value": "name",
                      "type": "string"
                    },
                    {
                      "key": "addTokenTo",
                      "value": "header",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "body": {
                  "mode": "raw",
                  "raw": "{\n    \"hello\": \"world\"\n}",
                  "options": {
                    "raw": {
                      "language": "json"
                    }
                  }
                },
                "url": {
                  "raw": "{{vault:hello}}",
                  "host": ["{{vault:hello}}"]
                }
              },
              "response": []
            },
            {
              "name": "OAuth 2 Password",
              "protocolProfileBehavior": {
                "disableBodyPruning": true
              },
              "request": {
                "auth": {
                  "type": "oauth2",
                  "oauth2": [
                    {
                      "key": "password",
                      "value": "password",
                      "type": "string"
                    },
                    {
                      "key": "username",
                      "value": "username",
                      "type": "string"
                    },
                    {
                      "key": "clientSecret",
                      "value": "clientsecret",
                      "type": "string"
                    },
                    {
                      "key": "clientId",
                      "value": "clientid",
                      "type": "string"
                    },
                    {
                      "key": "grant_type",
                      "value": "password_credentials",
                      "type": "string"
                    },
                    {
                      "key": "client_authentication",
                      "value": "header",
                      "type": "string"
                    },
                    {
                      "key": "redirect_uri",
                      "value": "https://yaak.app/x/echo",
                      "type": "string"
                    },
                    {
                      "key": "useBrowser",
                      "value": false,
                      "type": "boolean"
                    },
                    {
                      "key": "headerPrefix",
                      "value": "Bearer",
                      "type": "string"
                    },
                    {
                      "key": "challengeAlgorithm",
                      "value": "S256",
                      "type": "string"
                    },
                    {
                      "key": "refreshTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "state",
                      "value": "state",
                      "type": "string"
                    },
                    {
                      "key": "scope",
                      "value": "scope",
                      "type": "string"
                    },
                    {
                      "key": "code_verifier",
                      "value": "verifier",
                      "type": "string"
                    },
                    {
                      "key": "authUrl",
                      "value": "https://github.com/login/oauth/authorize",
                      "type": "string"
                    },
                    {
                      "key": "accessTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "tokenName",
                      "value": "name",
                      "type": "string"
                    },
                    {
                      "key": "addTokenTo",
                      "value": "header",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "body": {
                  "mode": "raw",
                  "raw": "{\n    \"hello\": \"world\"\n}",
                  "options": {
                    "raw": {
                      "language": "json"
                    }
                  }
                },
                "url": {
                  "raw": "{{vault:hello}}",
                  "host": ["{{vault:hello}}"]
                }
              },
              "response": []
            },
            {
              "name": "OAuth 2 Client Credentials",
              "protocolProfileBehavior": {
                "disableBodyPruning": true
              },
              "request": {
                "auth": {
                  "type": "oauth2",
                  "oauth2": [
                    {
                      "key": "grant_type",
                      "value": "client_credentials",
                      "type": "string"
                    },
                    {
                      "key": "password",
                      "value": "password",
                      "type": "string"
                    },
                    {
                      "key": "username",
                      "value": "username",
                      "type": "string"
                    },
                    {
                      "key": "clientSecret",
                      "value": "clientsecret",
                      "type": "string"
                    },
                    {
                      "key": "clientId",
                      "value": "clientid",
                      "type": "string"
                    },
                    {
                      "key": "client_authentication",
                      "value": "header",
                      "type": "string"
                    },
                    {
                      "key": "redirect_uri",
                      "value": "https://yaak.app/x/echo",
                      "type": "string"
                    },
                    {
                      "key": "useBrowser",
                      "value": false,
                      "type": "boolean"
                    },
                    {
                      "key": "headerPrefix",
                      "value": "Bearer",
                      "type": "string"
                    },
                    {
                      "key": "challengeAlgorithm",
                      "value": "S256",
                      "type": "string"
                    },
                    {
                      "key": "refreshTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "state",
                      "value": "state",
                      "type": "string"
                    },
                    {
                      "key": "scope",
                      "value": "scope",
                      "type": "string"
                    },
                    {
                      "key": "code_verifier",
                      "value": "verifier",
                      "type": "string"
                    },
                    {
                      "key": "authUrl",
                      "value": "https://github.com/login/oauth/authorize",
                      "type": "string"
                    },
                    {
                      "key": "accessTokenUrl",
                      "value": "https://github.com/login/oauth/access_token",
                      "type": "string"
                    },
                    {
                      "key": "tokenName",
                      "value": "name",
                      "type": "string"
                    },
                    {
                      "key": "addTokenTo",
                      "value": "header",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "body": {
                  "mode": "raw",
                  "raw": "{\n    \"hello\": \"world\"\n}",
                  "options": {
                    "raw": {
                      "language": "json"
                    }
                  }
                },
                "url": {
                  "raw": "{{vault:hello}}",
                  "host": ["{{vault:hello}}"]
                }
              },
              "response": []
            },
            {
              "name": "AWS V4",
              "request": {
                "auth": {
                  "type": "awsv4",
                  "awsv4": [
                    {
                      "key": "sessionToken",
                      "value": "session",
                      "type": "string"
                    },
                    {
                      "key": "service",
                      "value": "s3",
                      "type": "string"
                    },
                    {
                      "key": "region",
                      "value": "us-west-1",
                      "type": "string"
                    },
                    {
                      "key": "secretKey",
                      "value": "secret",
                      "type": "string"
                    },
                    {
                      "key": "accessKey",
                      "value": "access",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "API Key",
              "request": {
                "auth": {
                  "type": "apikey",
                  "apikey": [
                    {
                      "key": "in",
                      "value": "query",
                      "type": "string"
                    },
                    {
                      "key": "value",
                      "value": "secret-123",
                      "type": "string"
                    },
                    {
                      "key": "key",
                      "value": "X-API-Key",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "JWT",
              "request": {
                "auth": {
                  "type": "jwt",
                  "jwt": [
                    {
                      "key": "header",
                      "value": "{\n    \"header\": \"foo\"\n}",
                      "type": "string"
                    },
                    {
                      "key": "headerPrefix",
                      "value": "Bearer",
                      "type": "string"
                    },
                    {
                      "key": "payload",
                      "value": "{\n    \"my\": \"payload\"\n}",
                      "type": "string"
                    },
                    {
                      "key": "isSecretBase64Encoded",
                      "value": false,
                      "type": "boolean"
                    },
                    {
                      "key": "secret",
                      "value": "mysecret",
                      "type": "string"
                    },
                    {
                      "key": "algorithm",
                      "value": "HS384",
                      "type": "string"
                    },
                    {
                      "key": "addTokenTo",
                      "value": "header",
                      "type": "string"
                    },
                    {
                      "key": "queryParamKey",
                      "value": "token",
                      "type": "string"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "Digest",
              "request": {
                "auth": {
                  "type": "digest",
                  "digest": [
                    {
                      "key": "algorithm",
                      "value": "MD5",
                      "type": "string"
                    },
                    {
                      "key": "username",
                      "value": "digest-user",
                      "type": "string"
                    },
                    {
                      "key": "password",
                      "value": "digest-pass",
                      "type": "string"
                    },
                    {
                      "key": "realm",
                      "value": "testrealm@yaak.app",
                      "type": "string"
                    },
                    {
                      "key": "nonce",
                      "value": "dcd98b7102dd2f0e8b11d0f600bfb0c093",
                      "type": "string"
                    },
                    {
                      "key": "nonceCount",
                      "value": "00000001",
                      "type": "string"
                    },
                    {
                      "key": "clientNonce",
                      "value": "0a4f113b",
                      "type": "string"
                    },
                    {
                      "key": "opaque",
                      "value": "5ccc069c403ebaf9f0171e9517f40e41",
                      "type": "string"
                    },
                    {
                      "key": "qop",
                      "value": "auth",
                      "type": "string"
                    },
                    {
                      "key": "disableRetryRequest",
                      "value": true,
                      "type": "boolean"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "NTLM",
              "request": {
                "auth": {
                  "type": "ntlm",
                  "ntlm": [
                    {
                      "key": "username",
                      "value": "ntlm-user",
                      "type": "string"
                    },
                    {
                      "key": "password",
                      "value": "ntlm-pass",
                      "type": "string"
                    },
                    {
                      "key": "domain",
                      "value": "CORP",
                      "type": "string"
                    },
                    {
                      "key": "workstation",
                      "value": "WORKSTATION-01",
                      "type": "string"
                    },
                    {
                      "key": "disableRetryRequest",
                      "value": true,
                      "type": "boolean"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "OAuth 1",
              "request": {
                "auth": {
                  "type": "oauth1",
                  "oauth1": [
                    {
                      "key": "consumerKey",
                      "value": "consumer-key",
                      "type": "string"
                    },
                    {
                      "key": "consumerSecret",
                      "value": "consumer-secret",
                      "type": "string"
                    },
                    {
                      "key": "token",
                      "value": "access-token",
                      "type": "string"
                    },
                    {
                      "key": "tokenSecret",
                      "value": "token-secret",
                      "type": "string"
                    },
                    {
                      "key": "signatureMethod",
                      "value": "HMAC-SHA256",
                      "type": "string"
                    },
                    {
                      "key": "timestamp",
                      "value": "1700000000",
                      "type": "string"
                    },
                    {
                      "key": "nonce",
                      "value": "9e6dfada256c",
                      "type": "string"
                    },
                    {
                      "key": "version",
                      "value": "1.0",
                      "type": "string"
                    },
                    {
                      "key": "realm",
                      "value": "yaak.app",
                      "type": "string"
                    },
                    {
                      "key": "callback",
                      "value": "https://yaak.app/x/callback",
                      "type": "string"
                    },
                    {
                      "key": "verifier",
                      "value": "verifier-123",
                      "type": "string"
                    },
                    {
                      "key": "addParamsToHeader",
                      "value": true,
                      "type": "boolean"
                    },
                    {
                      "key": "addEmptyParamsToSign",
                      "value": false,
                      "type": "boolean"
                    },
                    {
                      "key": "includeBodyHash",
                      "value": false,
                      "type": "boolean"
                    }
                  ]
                },
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://yaak.app/x/echo",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"]
                }
              },
              "response": []
            },
            {
              "name": "Folder With Auth",
              "item": [
                {
                  "name": "Folder Child Inherit",
                  "request": {
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://yaak.app/x/echo",
                      "protocol": "https",
                      "host": ["yaak", "app"],
                      "path": ["x", "echo"]
                    }
                  },
                  "response": []
                },
                {
                  "name": "Folder Child No Auth",
                  "request": {
                    "auth": {
                      "type": "noauth"
                    },
                    "method": "GET",
                    "header": [],
                    "url": {
                      "raw": "https://yaak.app/x/echo",
                      "protocol": "https",
                      "host": ["yaak", "app"],
                      "path": ["x", "echo"]
                    }
                  },
                  "response": []
                }
              ],
              "auth": {
                "type": "bearer",
                "bearer": [
                  {
                    "key": "token",
                    "value": "folder-token",
                    "type": "string"
                  }
                ]
              }
            }
          ],
          "auth": {
            "type": "basic",
            "basic": [
              {
                "key": "password",
                "value": "workspace_secret",
                "type": "string"
              },
              {
                "key": "username",
                "value": "workspace",
                "type": "string"
              }
            ]
          },
          "event": [
            {
              "listen": "prerequest",
              "script": {
                "type": "text/javascript",
                "packages": {},
                "requests": {},
                "exec": [""]
              }
            },
            {
              "listen": "test",
              "script": {
                "type": "text/javascript",
                "packages": {},
                "requests": {},
                "exec": [""]
              }
            }
          ],
          "variable": [
            {
              "key": "COLLECTION VARIABLE",
              "value": "collection variable"
            }
          ]
        }
        """#, plan: imported("Authentication", [
            planned(1, "No Auth", "GET", echo),
            planned(2, "Inherit", "GET", echo, auth: .basic(user: "workspace", password: "workspace_secret")),
            planned(3, "OAuth 2 Auth Code", "GET", "{{vault:hello}}", headers: json, body: hello),
            planned(4, "OAuth 2 Auth Code (PKCE)", "GET", "{{vault:hello}}", headers: json, body: hello),
            planned(5, "OAuth 2 Implicit", "GET", "{{vault:hello}}", headers: json, body: hello),
            planned(6, "OAuth 2 Password", "GET", "{{vault:hello}}", headers: json, body: hello),
            planned(7, "OAuth 2 Client Credentials", "GET", "{{vault:hello}}", headers: json, body: hello),
            planned(8, "AWS V4", "GET", echo),
            planned(9, "API Key", "GET", echo, params: rows(("X-API-Key", "secret-123"))),
            planned(10, "JWT", "GET", echo),
            planned(11, "Digest", "GET", echo),
            planned(12, "NTLM", "GET", echo),
            planned(13, "OAuth 1", "GET", echo),
            .folder(name: "Folder With Auth", children: [
                planned(14, "Folder Child Inherit", "GET", echo, auth: .bearer(token: "folder-token")),
                planned(15, "Folder Child No Auth", "GET", echo),
            ]),
        ], notes: [
            note(.authInherited, "Inherit", "Folder Child Inherit"),
            note(.authNotSupported(type: "oauth2"), "OAuth 2 Auth Code", "OAuth 2 Auth Code (PKCE)", "OAuth 2 Implicit", "OAuth 2 Password",
                 "OAuth 2 Client Credentials"),
            note(.authNotSupported(type: "awsv4"), "AWS V4"),
            note(.authNotSupported(type: "jwt"), "JWT"),
            note(.authNotSupported(type: "digest"), "Digest"),
            note(.authNotSupported(type: "ntlm"), "NTLM"),
            note(.authNotSupported(type: "oauth1"), "OAuth 1"),
            note(.variableNameInvalid, "COLLECTION VARIABLE"),
        ]))

    static let nested = PostmanFixture("nested", #"""
        {
          "info": {
            "_postman_id": "9e6dfada-256c-49ea-a38f-7d1b05b7ca2d",
            "name": "New Collection",
            "schema": "https://schema.getpostman.com/json/collection/v2.0.0/collection.json",
            "_exporter_id": "18798"
          },
          "item": [
            {
              "name": "Top Folder",
              "item": [
                {
                  "name": "Nested Folder",
                  "item": [
                    {
                      "name": "Request 1",
                      "request": {
                        "method": "GET"
                      }
                    }
                  ]
                },
                {
                  "name": "Request 2",
                  "request": {
                    "method": "GET"
                  }
                }
              ]
            },
            {
              "name": "Request 3",
              "request": {
                "method": "GET"
              }
            }
          ]
        }
        """#, plan: imported("New Collection", [
            .folder(name: "Top Folder", children: [
                .folder(name: "Nested Folder", children: [planned(1, "Request 1")]),
                planned(2, "Request 2"),
            ]),
            planned(3, "Request 3"),
        ]))

    // Differs from Yaak's output, each by a row of the mapping:
    // - `:foo` and `:bar` are written into the path and noted (path variables `:id` with
    //   `url.variable`); Yaak keeps them as `:foo` Params.
    // - The query entry with no key and a null value is no row (a header, query, … entry whose
    //   key and value are both empty or `null`).
    // - The file part's `contentType` is dropped (body `formdata`).
    // - "COLLECTION VARIABLE" is dropped and listed (a variable `key` that is not a VariableName).
    static let params = PostmanFixture("params", #"""
        {
          "info": {
            "_postman_id": "9e6dfada-256c-49ea-a38f-7d1b05b7ca2d",
            "name": "New Collection",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
            "_exporter_id": "18798"
          },
          "item": [
            {
              "name": "Form URL",
              "request": {
                "auth": {
                  "type": "bearer",
                  "bearer": [
                    {
                      "key": "token",
                      "value": "my-token",
                      "type": "string"
                    }
                  ]
                },
                "method": "POST",
                "header": [
                  {
                    "key": "X-foo",
                    "value": "bar",
                    "description": "description"
                  },
                  {
                    "key": "Disabled",
                    "value": "tnroant",
                    "description": "ntisorantosra",
                    "disabled": true
                  }
                ],
                "body": {
                  "mode": "formdata",
                  "formdata": [
                    {
                      "key": "Key",
                      "contentType": "Custom/COntent",
                      "description": "DEscription",
                      "type": "file",
                      "src": "/Users/gschier/Desktop/Screenshot 2024-05-31 at 12.05.11 PM.png"
                    }
                  ]
                },
                "url": {
                  "raw": "example.com/:foo/:bar?q=qqq&",
                  "host": ["example", "com"],
                  "path": [":foo", ":bar"],
                  "query": [
                    {
                      "key": "disabled",
                      "value": "secondvalue",
                      "description": "this is disabled",
                      "disabled": true
                    },
                    {
                      "key": "q",
                      "value": "qqq",
                      "description": "hello"
                    },
                    {
                      "key": "",
                      "value": null
                    }
                  ],
                  "variable": [
                    {
                      "key": "foo",
                      "value": "fff",
                      "description": "Description"
                    },
                    {
                      "key": "bar",
                      "value": "bbb",
                      "description": "bbb description"
                    }
                  ]
                }
              },
              "response": []
            }
          ],
          "auth": {
            "type": "basic",
            "basic": [
              {
                "key": "password",
                "value": "globalpass",
                "type": "string"
              },
              {
                "key": "username",
                "value": "globaluser",
                "type": "string"
              }
            ]
          },
          "event": [
            {
              "listen": "prerequest",
              "script": {
                "type": "text/javascript",
                "packages": {},
                "exec": [""]
              }
            },
            {
              "listen": "test",
              "script": {
                "type": "text/javascript",
                "packages": {},
                "exec": [""]
              }
            }
          ],
          "variable": [
            {
              "key": "COLLECTION VARIABLE",
              "value": "collection variable",
              "type": "string"
            }
          ]
        }
        """#, plan: imported("New Collection", [
            planned(
                1, "Form URL", "POST", "example.com/fff/bbb",
                params: [Row(name: "disabled", value: "secondvalue", isEnabled: false), Row(name: "q", value: "qqq")],
                headers: [Row(name: "X-foo", value: "bar"), Row(name: "Disabled", value: "tnroant", isEnabled: false),
                          Row(name: "Content-Type", value: "multipart/form-data")],
                // macOS names a screenshot with a narrow no-break space before "PM".
                body: .multipart([Part(name: "Key", content: .file(path: "/Users/gschier/Desktop/Screenshot 2024-05-31 at 12.05.11\u{202F}PM.png"))]),
                auth: .bearer(token: "my-token")
            ),
        ], notes: [note(.pathVariable, "Form URL"), note(.variableNameInvalid, "COLLECTION VARIABLE")]))

    // Differs from Yaak's output by the dynamic variables row: each `{{$name}}` is left as typed
    // and noted, once per name, where Yaak rewrites it to one of its template functions.
    static let dynamicVariables = PostmanFixture("dynamic-variables", #"""
        {
          "info": {
            "_postman_id": "5c0ffee0-dyn0-4var-9abc-000000000001",
            "name": "Dynamic Variables",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
          },
          "item": [
            {
              "name": "Dynamic Variables",
              "request": {
                "method": "POST",
                "header": [
                  {
                    "key": "X-Request-Id",
                    "value": "{{$guid}}"
                  },
                  {
                    "key": "X-Correlation-Id",
                    "value": "{{$randomUUID}}"
                  },
                  {
                    "key": "X-Sent-At",
                    "value": "{{$timestamp}}"
                  },
                  {
                    "key": "X-Sent-At-Iso",
                    "value": "{{$isoTimestamp}}"
                  },
                  {
                    "key": "X-Spaced",
                    "value": "{{  $guid  }}"
                  },
                  {
                    "key": "X-Faker",
                    "value": "{{$randomFirstName}}"
                  },
                  {
                    "key": "X-Plain",
                    "value": "{{base_url}}"
                  }
                ],
                "url": {
                  "raw": "https://yaak.app/x/echo?n={{$randomInt}}",
                  "protocol": "https",
                  "host": ["yaak", "app"],
                  "path": ["x", "echo"],
                  "query": [
                    {
                      "key": "n",
                      "value": "{{$randomInt}}"
                    }
                  ]
                },
                "body": {
                  "mode": "raw",
                  "raw": "{\n  \"id\": \"{{$guid}}\",\n  \"at\": {{$timestamp}},\n  \"mixed\": \"{{$guid}}/{{base_url}}\"\n}",
                  "options": {
                    "raw": {
                      "language": "json"
                    }
                  }
                }
              },
              "response": []
            }
          ]
        }
        """#, plan: imported("Dynamic Variables", [
            planned(
                1, "Dynamic Variables", "POST", echo, params: rows(("n", "{{$randomInt}}")),
                headers: rows(
                    ("X-Request-Id", "{{$guid}}"), ("X-Correlation-Id", "{{$randomUUID}}"), ("X-Sent-At", "{{$timestamp}}"),
                    ("X-Sent-At-Iso", "{{$isoTimestamp}}"), ("X-Spaced", "{{  $guid  }}"), ("X-Faker", "{{$randomFirstName}}"),
                    ("X-Plain", "{{base_url}}"), ("Content-Type", "application/json")
                ),
                body: .raw(.json, "{\n  \"id\": \"{{$guid}}\",\n  \"at\": {{$timestamp}},\n  \"mixed\": \"{{$guid}}/{{base_url}}\"\n}")
            ),
        ], notes: ["$randomInt", "$guid", "$randomUUID", "$timestamp", "$isoTimestamp", "$randomFirstName"].map {
            note(.dynamicVariable(name: $0), "Dynamic Variables")
        }))

    static let inline: [PostmanFixture] = [
        // Differs: the description is dropped and counted (`response`, `description`).
        PostmanFixture("Imports object descriptions without [object Object]", #"""
            {"info": {"name": "Description Test", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
             "item": [{"name": "Request 1", "request": {"method": "GET", "description": {"content": "Lijst van klanten", "type": "text/plain"}}}]}
            """#, plan: imported("Description Test", [planned(1, "Request 1")], notes: [note(.descriptionsDropped, "Request 1")])),
        PostmanFixture("Imports url.path when it is a string instead of an array", #"""
            {"info": {"name": "String Path Test", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
             "item": [{"name": "String Path", "request": {"method": "GET", "url": {"host": ["example", "com"], "path": "foo/bar"}}}]}
            """#, plan: imported("String Path Test", [planned(1, "String Path", "GET", "example.com/foo/bar")])),
        // Differs: OAuth 1 is none, noted (auth `oauth1`), so no signature method is kept.
        PostmanFixture("Falls back to the default OAuth 1 signature method for unrecognized ones", #"""
            {"info": {"name": "OAuth 1 Signature", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
             "item": [{"name": "Request", "request": {"method": "GET", "url": "https://yaak.app",
                       "auth": {"type": "oauth1", "oauth1": [{"key": "signatureMethod", "value": "HMAC-SHA384"}]}}}]}
            """#, plan: imported("OAuth 1 Signature", [planned(1, "Request", "GET", "https://yaak.app")],
                                 notes: [note(.authNotSupported(type: "oauth1"), "Request")])),
        // Differs: `{{name}}` is unchanged, where Yaak rewrites it to `${[name]}`.
        PostmanFixture("Leaves {{constructor}} alone instead of reaching Object.prototype", #"""
            {"info": {"name": "Prototype Key", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
             "item": [{"name": "Request", "request": {"method": "GET", "url": "https://yaak.app",
                       "header": [{"key": "X-A", "value": "{{constructor}}"}, {"key": "X-B", "value": "{{toString}}"}]}}]}
            """#, plan: imported("Prototype Key", [
                planned(1, "Request", "GET", "https://yaak.app", headers: rows(("X-A", "{{constructor}}"), ("X-B", "{{toString}}"))),
            ])),
    ]
}
