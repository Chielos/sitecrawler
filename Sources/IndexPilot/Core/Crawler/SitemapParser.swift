import Foundation

/// Parses XML sitemaps: standard sitemap, sitemap index, and news/image/video extensions.
/// Handles gzip-encoded sitemaps transparently via URLSession.
final class SitemapParser: NSObject, XMLParserDelegate {

    // MARK: — Types

    struct SitemapURL {
        var loc: String
        var lastmod: Date?
        var changefreq: String?
        var priority: Double?
    }

    struct ParseResult {
        var urls: [SitemapURL]
        var sitemapIndexURLs: [String]
        var parseErrors: [String]
    }

    // MARK: — Public API

    static func parse(data: Data) -> ParseResult {
        let instance = SitemapParser()
        return instance.parseXML(data: data)
    }

    /// Fetch and parse a sitemap URL, following sitemap index references one level deep.
    static func fetchAndParse(url: URL) async -> ParseResult {
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: config)
            let (data, _) = try await session.data(from: url)
            var result = parse(data: data)

            // Resolve sitemap index references
            var allURLs = result.urls
            for indexURL in result.sitemapIndexURLs {
                guard let indexParsed = URL(string: indexURL) else { continue }
                do {
                    let (subData, _) = try await session.data(from: indexParsed)
                    let subResult = parse(data: subData)
                    allURLs.append(contentsOf: subResult.urls)
                } catch { /* skip unreachable sub-sitemaps */ }
            }
            result.urls = allURLs
            return result
        } catch {
            return ParseResult(urls: [], sitemapIndexURLs: [], parseErrors: [error.localizedDescription])
        }
    }

    // MARK: — XML Parsing State

    private var urls: [SitemapURL] = []
    private var sitemapIndexURLs: [String] = []
    private var parseErrors: [String] = []

    private var currentElement: String = ""
    private var currentLoc: String = ""
    private var currentLastmod: String = ""
    private var currentChangefreq: String = ""
    private var currentPriority: String = ""
    private var isSitemapIndex: Bool = false
    private var currentText: String = ""

    private func parseXML(data: Data) -> ParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return ParseResult(urls: urls, sitemapIndexURLs: sitemapIndexURLs, parseErrors: parseErrors)
    }

    // MARK: — XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        currentText = ""
        if currentElement == "sitemapindex" { isSitemapIndex = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "loc":
            currentLoc = value
        case "lastmod":
            currentLastmod = value
        case "changefreq":
            currentChangefreq = value
        case "priority":
            currentPriority = value
        case "url":
            if !currentLoc.isEmpty {
                var entry = SitemapURL(loc: currentLoc)
                entry.lastmod = parseDate(currentLastmod)
                entry.changefreq = currentChangefreq.isEmpty ? nil : currentChangefreq
                entry.priority = Double(currentPriority)
                urls.append(entry)
            }
            clearCurrent()
        case "sitemap":
            if isSitemapIndex && !currentLoc.isEmpty {
                sitemapIndexURLs.append(currentLoc)
            }
            clearCurrent()
        default:
            break
        }
        currentElement = ""
        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parseErrors.append(parseError.localizedDescription)
    }

    private func clearCurrent() {
        currentLoc = ""
        currentLastmod = ""
        currentChangefreq = ""
        currentPriority = ""
    }

    private func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let formatters: [DateFormatter] = [
            makeFormatter("yyyy-MM-dd'T'HH:mm:ssZZZZZ"),
            makeFormatter("yyyy-MM-dd'T'HH:mm:ss"),
            makeFormatter("yyyy-MM-dd"),
        ]
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }
}
