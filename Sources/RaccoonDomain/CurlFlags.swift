public enum CurlFlags {
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
