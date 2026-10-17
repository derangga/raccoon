/// The options of one curl command that Curl Import reads, and everything else it was given.
public struct CurlFlags: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        /// The long name without dashes: `-H` is `header`.
        public var name: String
        /// nil for a switch, and for an option missing its value at the end of the command.
        public var value: String?

        public init(name: String, value: String?) {
            self.name = name
            self.value = value
        }
    }

    /// In command order, so headers and data keep theirs.
    public var options: [Option]
    public var positionals: [String]
    /// As typed (`-s`, `--retry`), without the value they consumed.
    public var ignoredFlags: [String]

    /// `words` is a whole command after `expandShortFlags`, starting with `curl`.
    public static func collect(_ words: [String]) -> CurlFlags {
        var flags = CurlFlags(options: [], positionals: [], ignoredFlags: [])
        var words = words.dropFirst().makeIterator()
        while let word = words.next() {
            guard let name = name(word) else {
                flags.positionals.append(word)
                continue
            }
            let value = takesValue.contains(String(name)) ? words.next() : nil
            let long = word.hasPrefix("--") ? String(name) : longNames[String(name)]
            if let long, read.contains(long) {
                flags.options.append(Option(name: long, value: value))
            } else {
                flags.ignoredFlags.append(word)
            }
        }
        return flags
    }

    public func values(_ name: String) -> [String] {
        options.compactMap { $0.name == name ? $0.value : nil }
    }

    public func has(_ name: String) -> Bool {
        options.contains { $0.name == name }
    }

    /// What Curl Import maps. `--digest` and `--compressed` are not here on purpose (curl.md).
    static let read: Set<String> = [
        "url", "url-query", "request", "header", "cookie", "user", "form", "get", "insecure", "location",
        "data", "data-ascii", "data-binary", "data-raw", "data-urlencode",
    ]

    /// The short names of the options in `read`.
    static let longNames = [
        "X": "request", "H": "header", "b": "cookie", "u": "user", "F": "form", "G": "get", "k": "insecure",
        "L": "location", "d": "data",
    ]

    /// Every curl option that takes a value, short and long, without dashes: the options with an
    /// argument in `curl --help all` (curl 8.7.1), less `--help`, whose category is optional. An
    /// option not in this table is a switch, so the word after it is never consumed.
    static let takesValue: Set<String> = [
        "E", "K", "C", "b", "c", "d", "D", "F", "P", "H", "m", "o", "x", "U", "Q", "r", "e", "X",
        "Y", "y", "t", "z", "T", "u", "A", "w",
        "abstract-unix-socket", "alt-svc", "aws-sigv4", "cacert", "capath", "cert", "cert-type",
        "ciphers", "config", "connect-timeout", "connect-to", "continue-at", "cookie", "cookie-jar",
        "create-file-mode", "crlfile", "curves", "data", "data-ascii", "data-binary", "data-raw",
        "data-urlencode", "delegation", "dns-interface", "dns-ipv4-addr", "dns-ipv6-addr",
        "dns-servers", "doh-url", "dump-header", "egd-file", "engine", "etag-compare", "etag-save",
        "expect100-timeout", "form", "form-string", "ftp-account", "ftp-alternative-to-user",
        "ftp-method", "ftp-port", "ftp-ssl-ccc-mode", "happy-eyeballs-timeout-ms",
        "haproxy-clientip", "header", "hostpubmd5", "hostpubsha256", "hsts", "interface",
        "ipfs-gateway", "json", "keepalive-time", "key", "key-type", "krb", "libcurl", "limit-rate",
        "local-port", "login-options", "mail-auth", "mail-from", "mail-rcpt", "max-filesize",
        "max-redirs", "max-time", "netrc-file", "noproxy", "oauth2-bearer", "output", "output-dir",
        "parallel-max", "pass", "pinnedpubkey", "preproxy", "proto", "proto-default", "proto-redir",
        "proxy", "proxy-cacert", "proxy-capath", "proxy-cert", "proxy-cert-type", "proxy-ciphers",
        "proxy-crlfile", "proxy-header", "proxy-key", "proxy-key-type", "proxy-pass",
        "proxy-pinnedpubkey", "proxy-service-name", "proxy-tls13-ciphers", "proxy-tlsauthtype",
        "proxy-tlspassword", "proxy-tlsuser", "proxy-user", "pubkey", "quote", "random-file",
        "range", "rate", "referer", "request", "request-target", "resolve", "retry", "retry-delay",
        "retry-max-time", "sasl-authzid", "service-name", "socks4", "socks4a", "socks5",
        "socks5-gssapi-service", "socks5-hostname", "speed-limit", "speed-time", "stderr",
        "telnet-option", "tftp-blksize", "time-cond", "tls-max", "tls13-ciphers", "tlsauthtype",
        "tlspassword", "tlsuser", "trace", "trace-ascii", "trace-config", "unix-socket",
        "upload-file", "url", "url-query", "user", "user-agent", "variable", "write-out",
    ]

    /// `-H` → `H`, `--header` → `header`, anything else (a value, a URL, `-`) → nil.
    static func name(_ word: String) -> Substring? {
        guard word.count > 1, word.hasPrefix("-") else { return nil }
        return word.dropFirst(word.hasPrefix("--") ? 2 : 1)
    }
}
