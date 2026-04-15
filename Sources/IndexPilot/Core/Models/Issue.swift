import Foundation

/// One detected SEO issue for a specific URL.
struct Issue: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionID: UUID
    var url: String
    var issueKey: String
    var severity: IssueSeverity
    var category: IssueCategory
    var title: String
    var description: String
    var remediation: String
    var data: [String: String]

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        url: String,
        definition: IssueDefinition,
        data: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.url = url
        self.issueKey = definition.key
        self.severity = definition.severity
        self.category = definition.category
        self.title = definition.title
        self.description = definition.description
        self.remediation = definition.remediation
        self.data = data
    }
}

enum IssueSeverity: String, Codable, CaseIterable, Comparable {
    case error = "error"
    case warning = "warning"
    case opportunity = "opportunity"
    case info = "info"

    var sortOrder: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .opportunity: return 2
        case .info: return 3
        }
    }

    public static func < (lhs: IssueSeverity, rhs: IssueSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayLabel: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .opportunity: return "Opportunity"
        case .info: return "Info"
        }
    }
}

enum IssueCategory: String, Codable, CaseIterable {
    case http = "HTTP"
    case redirect = "Redirects"
    case titles = "Titles"
    case metaDescription = "Meta Description"
    case headings = "Headings"
    case canonical = "Canonicals"
    case indexability = "Indexability"
    case sitemaps = "Sitemaps"
    case images = "Images"
    case hreflang = "Hreflang"
    case security = "Security"
    case content = "Content"
    case structuredData = "Structured Data"
    case performance = "Performance"
    case links = "Links"
}

/// Static metadata for a class of issues. Registered in IssueDefinitionRegistry.
struct IssueDefinition {
    let key: String
    let severity: IssueSeverity
    let category: IssueCategory
    let title: String
    let description: String
    let remediation: String
}
