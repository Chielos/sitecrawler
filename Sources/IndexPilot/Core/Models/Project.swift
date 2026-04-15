import Foundation

/// Top-level container for all crawls and settings related to one website.
struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var seedURLs: [String]
    var configuration: CrawlConfiguration
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        seedURLs: [String],
        configuration: CrawlConfiguration = CrawlConfiguration(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.seedURLs = seedURLs
        self.configuration = configuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
