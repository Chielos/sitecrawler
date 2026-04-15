import Foundation

/// RFC 9309-compliant robots.txt parser.
/// Parses User-agent, Disallow, Allow, Crawl-delay, and Sitemap directives.
struct RobotsParser {

    // MARK: — Parsed Model

    struct ParsedRobots {
        var groups: [Group]
        var sitemaps: [String]
        var crawlDelay: Double?

        struct Group {
            var userAgents: [String]  // lowercase, trimmed
            var rules: [Rule]
        }

        struct Rule {
            var allow: Bool
            var path: String  // normalised path pattern

            func matches(path: String) -> Bool {
                guard !self.path.isEmpty else { return true }
                return wildcardMatch(pattern: self.path, subject: path)
            }
        }

        static let empty = ParsedRobots(groups: [], sitemaps: [], crawlDelay: nil)
    }

    // MARK: — Public API

    static func parse(_ content: String) -> ParsedRobots {
        var groups: [ParsedRobots.Group] = []
        var sitemaps: [String] = []

        var currentUAs: [String] = []
        var currentRules: [ParsedRobots.Rule] = []
        var globalCrawlDelay: Double? = nil
        var inGroup = false

        func flushGroup() {
            if !currentUAs.isEmpty {
                groups.append(ParsedRobots.Group(userAgents: currentUAs, rules: currentRules))
            }
            currentUAs = []
            currentRules = []
            inGroup = false
        }

        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            // Strip inline comments
            let commentIdx = rawLine.firstIndex(of: "#")
            let line = (commentIdx != nil ? String(rawLine[..<commentIdx!]) : rawLine)
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                if inGroup { flushGroup() }
                continue
            }

            let colonIdx = line.firstIndex(of: ":")
            guard let ci = colonIdx else { continue }
            let field = line[..<ci].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: ci)...].trimmingCharacters(in: .whitespaces)

            switch field {
            case "user-agent":
                if inGroup {
                    // New group starting — flush the current one
                    // But if current group has no rules yet, allow UA accumulation
                    if !currentRules.isEmpty {
                        flushGroup()
                    }
                    // If rules are empty, we're still accumulating UAs for the next block
                }
                currentUAs.append(value.lowercased())
                inGroup = true

            case "disallow":
                let path = decodePath(value)
                currentRules.append(ParsedRobots.Rule(allow: false, path: path))

            case "allow":
                let path = decodePath(value)
                currentRules.append(ParsedRobots.Rule(allow: true, path: path))

            case "crawl-delay":
                if let d = Double(value) {
                    globalCrawlDelay = globalCrawlDelay == nil ? d : min(globalCrawlDelay!, d)
                }

            case "sitemap":
                sitemaps.append(value)

            default:
                break
            }
        }
        flushGroup()

        return ParsedRobots(groups: groups, sitemaps: sitemaps, crawlDelay: globalCrawlDelay)
    }

    // MARK: — Permission Check

    /// Returns true if `userAgent` is allowed to fetch `path` according to the parsed robots.
    /// Implements the "longest matching rule wins" spec with tie-breaking by Allow > Disallow.
    static func isAllowed(path: String, robots: ParsedRobots, userAgent: String) -> Bool {
        let ua = userAgent.lowercased()

        // Find matching groups: exact UA match first, then wildcard "*"
        let matchingGroups = robots.groups.filter { group in
            group.userAgents.contains(ua) ||
            group.userAgents.contains { uaPattern in
                wildcardMatchUA(pattern: uaPattern, subject: ua)
            }
        }
        let wildcardGroups = robots.groups.filter { $0.userAgents.contains("*") }
        let groups = matchingGroups.isEmpty ? wildcardGroups : matchingGroups

        guard !groups.isEmpty else { return true }  // No applicable rules → allowed

        var bestMatchLength = -1
        var bestMatchAllows = true

        for group in groups {
            for rule in group.rules {
                guard rule.matches(path: path) else { continue }
                let matchLength = effectiveLength(rule.path)
                if matchLength > bestMatchLength ||
                   (matchLength == bestMatchLength && rule.allow && !bestMatchAllows) {
                    bestMatchLength = matchLength
                    bestMatchAllows = rule.allow
                }
            }
        }

        if bestMatchLength == -1 { return true }
        return bestMatchAllows
    }

    // MARK: — Helpers

    private static func decodePath(_ raw: String) -> String {
        // Percent-decode the path pattern but keep * and $ as-is
        return raw.removingPercentEncoding ?? raw
    }

    /// Effective match length for specificity tie-breaking.
    private static func effectiveLength(_ pattern: String) -> Int {
        // Wildcards reduce specificity
        pattern.replacingOccurrences(of: "*", with: "").count
    }
}

// MARK: — Wildcard Matching

/// Robots.txt wildcard matching: * matches any sequence, $ anchors end of path.
private func wildcardMatch(pattern: String, subject: String) -> Bool {
    // Fast path: no wildcards
    if !pattern.contains("*") && !pattern.contains("$") {
        return subject.hasPrefix(pattern)
    }

    let endsWithDollar = pattern.hasSuffix("$")
    let pat = endsWithDollar ? String(pattern.dropLast()) : pattern

    // DP-style wildcard matching
    let pChars = Array(pat)
    let sChars = Array(subject)
    var dp = Array(repeating: Array(repeating: false, count: sChars.count + 1), count: pChars.count + 1)
    dp[0][0] = true

    for i in 1...pChars.count {
        if pChars[i - 1] == "*" { dp[i][0] = dp[i - 1][0] }
    }

    for i in 1...pChars.count {
        for j in 1...sChars.count {
            if pChars[i - 1] == "*" {
                dp[i][j] = dp[i - 1][j] || dp[i][j - 1]
            } else if pChars[i - 1] == sChars[j - 1] {
                dp[i][j] = dp[i - 1][j - 1]
            }
        }
    }

    if endsWithDollar {
        return dp[pChars.count][sChars.count]
    }
    // Without $, any suffix of subject that matched the full pattern counts
    return dp[pChars.count].contains(true)
}

private func wildcardMatchUA(pattern: String, subject: String) -> Bool {
    pattern == "*" || subject.hasPrefix(pattern.lowercased())
}

// MARK: — RobotsCache

/// Per-session cache of fetched and parsed robots.txt files.
/// Thread-safe actor so multiple crawl workers share the same cache.
actor RobotsCache {

    private let sessionID: UUID
    private let db: DatabaseManager
    private var cache: [String: RobotsParser.ParsedRobots] = [:]
    private var fetching: [String: Task<RobotsParser.ParsedRobots, Never>] = [:]

    init(sessionID: UUID, db: DatabaseManager) {
        self.sessionID = sessionID
        self.db = db
    }

    /// Returns whether `url` is allowed to be crawled.
    func isAllowed(_ url: URL, userAgent: String) async -> Bool {
        guard let host = url.host else { return false }
        let robots = await fetchRobots(for: host, scheme: url.scheme ?? "https")
        return RobotsParser.isAllowed(
            path: url.path.isEmpty ? "/" : url.path,
            robots: robots,
            userAgent: userAgent
        )
    }

    /// Returns the parsed robots.txt for a host, fetching and caching if needed.
    func fetchRobots(for host: String, scheme: String) async -> RobotsParser.ParsedRobots {
        if let cached = cache[host] { return cached }

        // Avoid duplicate in-flight fetches to the same host
        if let existing = fetching[host] {
            return await existing.value
        }

        let task = Task<RobotsParser.ParsedRobots, Never> {
            let result = await fetchRobotsFromNetwork(host: host, scheme: scheme)
            return result
        }
        fetching[host] = task
        let result = await task.value
        fetching.removeValue(forKey: host)
        cache[host] = result

        // Persist to DB for resumable crawls
        let content: String?
        if result.groups.isEmpty && result.sitemaps.isEmpty {
            content = nil
        } else {
            content = "cached"  // We cache the parsed form, not raw text
        }
        try? db.cacheRobots(sessionID: sessionID, host: host, content: content)

        return result
    }

    /// Fetch robots.txt over HTTP and parse it.
    private func fetchRobotsFromNetwork(host: String, scheme: String) async -> RobotsParser.ParsedRobots {
        guard let url = URL(string: "\(scheme)://\(host)/robots.txt") else {
            return .empty
        }

        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: config)

            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return .empty }

            switch httpResponse.statusCode {
            case 200:
                let content = String(data: data, encoding: .utf8) ?? ""
                return RobotsParser.parse(content)
            case 401, 403:
                // Block everything on auth-protected robots
                return RobotsParser.ParsedRobots(
                    groups: [RobotsParser.ParsedRobots.Group(
                        userAgents: ["*"],
                        rules: [RobotsParser.ParsedRobots.Rule(allow: false, path: "/")]
                    )],
                    sitemaps: [],
                    crawlDelay: nil
                )
            default:
                // Non-200 other than 401/403: treat as empty (allowed)
                return .empty
            }
        } catch {
            return .empty
        }
    }

    /// All sitemap URLs discovered across all robots.txt files fetched.
    func allSitemapURLs() -> [String] {
        cache.values.flatMap { $0.sitemaps }
    }
}
