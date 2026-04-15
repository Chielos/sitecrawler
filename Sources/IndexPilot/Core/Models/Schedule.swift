import Foundation

/// A recurring crawl schedule for a project.
struct Schedule: Identifiable, Codable {
    let id: UUID
    var projectID: UUID
    var name: String
    var frequency: Frequency
    var isEnabled: Bool
    var nextRunAt: Date?
    var lastRunAt: Date?
    var lastRunStatus: RunStatus?
    var exportDestination: String?
    var createdAt: Date
    var runHistory: [RunRecord]

    init(
        id: UUID = UUID(),
        projectID: UUID,
        name: String,
        frequency: Frequency,
        exportDestination: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.frequency = frequency
        self.isEnabled = true
        self.nextRunAt = frequency.nextDate(from: Date())
        self.lastRunAt = nil
        self.lastRunStatus = nil
        self.exportDestination = exportDestination
        self.createdAt = Date()
        self.runHistory = []
    }

    enum Frequency: Codable, Hashable {
        case daily(hour: Int, minute: Int)
        case weekly(weekday: Int, hour: Int, minute: Int)
        case monthly(day: Int, hour: Int, minute: Int)

        func nextDate(from reference: Date) -> Date? {
            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .weekday, .hour, .minute],
                from: reference
            )
            switch self {
            case .daily(let hour, let minute):
                components.hour = hour
                components.minute = minute
                let candidate = Calendar.current.nextDate(
                    after: reference,
                    matching: components,
                    matchingPolicy: .nextTime
                )
                return candidate
            case .weekly(let weekday, let hour, let minute):
                components.weekday = weekday
                components.hour = hour
                components.minute = minute
                return Calendar.current.nextDate(
                    after: reference,
                    matching: components,
                    matchingPolicy: .nextTimePreservingSmallerComponents
                )
            case .monthly(let day, let hour, let minute):
                components.day = day
                components.hour = hour
                components.minute = minute
                return Calendar.current.nextDate(
                    after: reference,
                    matching: components,
                    matchingPolicy: .nextTimePreservingSmallerComponents
                )
            }
        }
    }

    enum RunStatus: String, Codable {
        case success = "success"
        case failed = "failed"
        case cancelled = "cancelled"
    }

    struct RunRecord: Codable {
        var sessionID: UUID
        var startedAt: Date
        var completedAt: Date?
        var status: RunStatus
        var urlsCrawled: Int
        var issuesFound: Int
    }
}
