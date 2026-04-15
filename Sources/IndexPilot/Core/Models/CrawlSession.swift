import Foundation

/// One execution of a crawl against a project. A project may have many sessions.
struct CrawlSession: Identifiable, Codable {
    let id: UUID
    let projectID: UUID
    var status: Status
    var seedURLs: [String]
    var configuration: CrawlConfiguration
    let startedAt: Date
    var completedAt: Date?
    var stats: CrawlStats
    var frontierCheckpoint: FrontierCheckpoint?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        seedURLs: [String],
        configuration: CrawlConfiguration,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.status = .queued
        self.seedURLs = seedURLs
        self.configuration = configuration
        self.startedAt = startedAt
        self.completedAt = nil
        self.stats = CrawlStats()
        self.frontierCheckpoint = nil
    }

    enum Status: String, Codable, CaseIterable {
        case queued = "queued"
        case running = "running"
        case paused = "paused"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"

        var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled: return true
            case .queued, .running, .paused: return false
            }
        }
    }
}

/// Live counters updated incrementally as the crawl progresses.
struct CrawlStats: Codable {
    var totalURLsDiscovered: Int = 0
    var totalURLsCrawled: Int = 0
    var totalURLsQueued: Int = 0
    var totalErrors: Int = 0
    var total2xx: Int = 0
    var total3xx: Int = 0
    var total4xx: Int = 0
    var total5xx: Int = 0
    var totalIssues: Int = 0
    var totalIssuesByCategory: [String: Int] = [:]
    var crawlRateURLsPerSecond: Double = 0
    var estimatedTimeRemainingSeconds: Double?

    mutating func record(statusCode: Int) {
        totalURLsCrawled += 1
        switch statusCode {
        case 200...299: total2xx += 1
        case 300...399: total3xx += 1
        case 400...499: total4xx += 1
        case 500...599: total5xx += 1
        default: break
        }
    }
}

/// Persisted frontier state for resumable crawls.
struct FrontierCheckpoint: Codable {
    var pendingURLs: [PendingURL]
    var seenURLs: [String]
    var savedAt: Date

    struct PendingURL: Codable {
        var url: String
        var depth: Int
        var priority: Double
    }
}
