import Foundation

/// Canonical URL normalization.
/// All rules are applied deterministically so the same logical URL always
/// produces the same normalized string — used as the deduplication key.
struct URLNormalizer {

    let configuration: CrawlConfiguration

    init(configuration: CrawlConfiguration = CrawlConfiguration()) {
        self.configuration = configuration
    }

    // MARK: — Public API

    /// Normalize `rawURL` relative to `base`, returning nil if the result is unusable.
    func normalize(_ rawURL: String, relativeTo base: URL? = nil) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("javascript:"), !trimmed.hasPrefix("mailto:"),
              !trimmed.hasPrefix("tel:"), !trimmed.hasPrefix("data:") else { return nil }

        // Resolve relative URLs against the page's base URL.
        let resolved: URL?
        if let base = base {
            resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL
        } else {
            resolved = URL(string: trimmed)
        }
        guard let url = resolved else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }

        return applyNormalizationRules(to: url)
    }

    // MARK: — Normalization Pipeline

    private func applyNormalizationRules(to url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // 1. Lowercase scheme
        components.scheme = components.scheme?.lowercased()

        // 2. Lowercase host + strip trailing dot
        if let host = components.host {
            var h = host.lowercased()
            if h.hasSuffix(".") { h = String(h.dropLast()) }
            components.host = h
        }

        // 3. Strip default ports
        if let port = components.port {
            if (components.scheme == "http" && port == 80) ||
               (components.scheme == "https" && port == 443) {
                components.port = nil
            }
        }

        // 4. Strip fragment
        components.fragment = nil

        // 5. Normalise path
        var path = components.path
        // Resolve dot segments: /a/b/../c → /a/c
        path = resolveDotSegments(path)
        // Ensure path is not empty
        if path.isEmpty { path = "/" }
        // Trailing slash normalisation (configurable)
        if configuration.normalizeTrailingSlash && path != "/" && path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        components.path = path

        // 6. Query parameter normalisation
        if var items = components.queryItems {
            // Remove tracking parameters
            if configuration.stripTrackingParameters {
                items = items.filter { !knownTrackingParameters.contains($0.name.lowercased()) }
            }
            // Sort query parameters for canonical comparison (optional)
            if configuration.sortQueryParameters {
                items.sort { $0.name < $1.name }
            }
            components.queryItems = items.isEmpty ? nil : items
        }

        // 7. Percent-encode normalisation: decode unreserved chars, uppercase hex
        if let rawQuery = components.percentEncodedQuery {
            components.percentEncodedQuery = normalizePercentEncoding(rawQuery)
        }
        components.percentEncodedPath = normalizePercentEncoding(components.percentEncodedPath)

        // 8. HTTP → HTTPS canonicalisation (treat as same resource when configured)
        // Note: this only affects deduplication. The actual crawl always uses the real scheme.
        // Not applied here — handled at the dedup key level in URLFrontier.

        return components.url
    }

    // MARK: — Helpers

    /// Resolve dot-segments in a URI path per RFC 3986 §5.2.4
    private func resolveDotSegments(_ path: String) -> String {
        var input = path
        var output: [String] = []
        while !input.isEmpty {
            if input.hasPrefix("../") {
                input.removeFirst(3)
            } else if input.hasPrefix("./") {
                input.removeFirst(2)
            } else if input.hasPrefix("/./") {
                input = "/" + input.dropFirst(3)
            } else if input == "/." {
                input = "/"
            } else if input.hasPrefix("/../") {
                input = "/" + input.dropFirst(4)
                output = output.dropLast()
            } else if input == "/.." {
                input = "/"
                output = output.dropLast()
            } else if input == "." || input == ".." {
                input = ""
            } else {
                let segment: String
                if input.hasPrefix("/") {
                    let rest = input.dropFirst()
                    let end = rest.firstIndex(of: "/") ?? rest.endIndex
                    segment = "/" + rest[..<end]
                } else {
                    let end = input.firstIndex(of: "/") ?? input.endIndex
                    segment = String(input[..<end])
                }
                output.append(segment)
                input.removeFirst(segment.count)
            }
        }
        return output.joined()
    }

    /// Decode unreserved characters that are unnecessarily percent-encoded,
    /// and uppercase any remaining percent-encoded sequences.
    /// RFC 3986 unreserved chars are ASCII-only: ALPHA / DIGIT / "-" / "." / "_" / "~"
    private func normalizePercentEncoding(_ s: String) -> String {
        // Restrict to ASCII unreserved chars only — do NOT use .alphanumerics which
        // matches all Unicode letters and would decode e.g. %C3 → Ã (non-ASCII literal).
        let asciiUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "%" {
                let hexStart = s.index(after: i)
                if let hexEnd = s.index(hexStart, offsetBy: 2, limitedBy: s.endIndex),
                   let codePoint = UInt32(s[hexStart..<hexEnd], radix: 16),
                   let scalar = Unicode.Scalar(codePoint),
                   scalar.value < 128,
                   asciiUnreserved.contains(scalar) {
                    // Safely decode ASCII unreserved char
                    result.append(Character(scalar))
                    i = hexEnd
                } else if let hexEnd = s.index(hexStart, offsetBy: 2, limitedBy: s.endIndex),
                          UInt32(s[hexStart..<hexEnd], radix: 16) != nil {
                    // Valid %XX but not an unreserved ASCII char — uppercase hex only
                    result += "%" + String(s[hexStart..<hexEnd]).uppercased()
                    i = hexEnd
                } else {
                    // Truncated or invalid percent sequence — encode the bare %
                    result += "%25"
                    i = s.index(after: i)
                }
            } else if c.isASCII {
                result.append(c)
                i = s.index(after: i)
            } else {
                // Non-ASCII literal — encode each UTF-8 byte
                for byte in String(c).utf8 {
                    result += String(format: "%%%02X", byte)
                }
                i = s.index(after: i)
            }
        }
        return result
    }
}

// MARK: — Scope Checking

extension URLNormalizer {

    /// Whether `url` is within the crawl scope defined by `seedURL` and configuration.
    func isInScope(_ url: URL, seedURL: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else { return false }
        guard let urlHost = url.host?.lowercased(),
              let seedHost = seedURL.host?.lowercased() else { return false }

        if configuration.constrainToSeedDomain {
            let registeredDomain = registeredDomainOf(seedHost)
            let urlRegistered = registeredDomainOf(urlHost)
            guard let rd = registeredDomain, let urd = urlRegistered else { return false }

            if configuration.includeSubdomains {
                guard urd == rd || urd.hasSuffix("." + rd) else { return false }
            } else {
                guard urlHost == seedHost else { return false }
            }
        }

        // Path prefix constraint
        if !configuration.allowedPaths.isEmpty {
            guard configuration.allowedPaths.contains(where: { url.path.hasPrefix($0) }) else {
                return false
            }
        }

        return true
    }

    /// Extract the "registered domain" (eTLD+1) from a hostname.
    /// Simplified implementation that handles common TLDs.
    /// For production, replace with a proper Public Suffix List implementation.
    private func registeredDomainOf(_ host: String) -> String? {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        // For multi-part TLDs like .co.uk, .com.au we'd need PSL.
        // Simplified: last two parts.
        return parts.suffix(2).joined(separator: ".")
    }
}
