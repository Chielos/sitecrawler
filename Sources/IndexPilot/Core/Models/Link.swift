import Foundation

/// One hyperlink discovered during a crawl — edges in the internal link graph.
struct Link: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionID: UUID
    var sourceURL: String
    var targetURL: String
    var anchorText: String?
    var rel: LinkRel
    var tagName: LinkTag
    var isInternal: Bool

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        sourceURL: String,
        targetURL: String,
        anchorText: String? = nil,
        rel: LinkRel = LinkRel(),
        tagName: LinkTag = .anchor,
        isInternal: Bool
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sourceURL = sourceURL
        self.targetURL = targetURL
        self.anchorText = anchorText
        self.rel = rel
        self.tagName = tagName
        self.isInternal = isInternal
    }
}

struct LinkRel: Codable, Hashable {
    var nofollow: Bool = false
    var ugc: Bool = false
    var sponsored: Bool = false
    var noopener: Bool = false
    var noreferrer: Bool = false

    init(rawRel: String? = nil) {
        guard let rel = rawRel?.lowercased() else { return }
        let parts = rel.components(separatedBy: CharacterSet.whitespaces.union(.init(charactersIn: ",")))
        nofollow = parts.contains("nofollow")
        ugc = parts.contains("ugc")
        sponsored = parts.contains("sponsored")
        noopener = parts.contains("noopener")
        noreferrer = parts.contains("noreferrer")
    }
}

enum LinkTag: String, Codable, CaseIterable {
    case anchor = "a"
    case image = "img"
    case link = "link"
    case script = "script"
    case iframe = "iframe"
    case canonical = "canonical"
    case hreflang = "hreflang"
}
