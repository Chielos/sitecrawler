import SwiftUI
import Observation

/// Single source of truth for the application.
/// Injected as an environment object from the app entry point.
@Observable
@MainActor
final class AppEnvironment {

    // MARK: — State

    var projects: [Project] = []
    var selectedProject: Project?
    var activeSession: CrawlSession?
    var activeCrawlEngine: CrawlEngine?
    var crawlEventTask: Task<Void, Never>?

    var recentURLs: [CrawledURL] = []
    var crawlStats: CrawlStats = CrawlStats()
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: — DB

    let db: DatabaseManager

    init() {
        // Initialise the database. Fatal errors here indicate a corrupted app install.
        do {
            let path = try DatabaseManager.defaultPath()
            self.db = try DatabaseManager(path: path)
        } catch {
            fatalError("Failed to open IndexPilot database: \(error)")
        }
        loadProjects()
    }

    // MARK: — Projects

    func loadProjects() {
        do {
            projects = try db.fetchAllProjects()
            if selectedProject == nil {
                selectedProject = projects.first
            }
        } catch {
            errorMessage = "Failed to load projects: \(error.localizedDescription)"
        }
    }

    func createProject(name: String, seedURLs: [String], config: CrawlConfiguration) {
        let project = Project(name: name, seedURLs: seedURLs, configuration: config)
        do {
            try db.insertProject(project)
            projects.insert(project, at: 0)
            selectedProject = project
        } catch {
            errorMessage = "Failed to create project: \(error.localizedDescription)"
        }
    }

    func updateProject(_ project: Project) {
        do {
            try db.updateProject(project)
            if let i = projects.firstIndex(where: { $0.id == project.id }) {
                projects[i] = project
            }
            if selectedProject?.id == project.id {
                selectedProject = project
            }
        } catch {
            errorMessage = "Failed to update project: \(error.localizedDescription)"
        }
    }

    func deleteProject(_ project: Project) {
        do {
            try db.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
            if selectedProject?.id == project.id {
                selectedProject = projects.first
            }
        } catch {
            errorMessage = "Failed to delete project: \(error.localizedDescription)"
        }
    }

    // MARK: — Crawl Control

    func startCrawl(for project: Project) {
        guard activeCrawlEngine == nil else { return }

        let engine = CrawlEngine(db: db, config: project.configuration)
        activeCrawlEngine = engine
        recentURLs = []
        crawlStats = CrawlStats()

        crawlEventTask = Task {
            let stream = await engine.start(
                projectID: project.id,
                seedURLs: project.seedURLs
            )

            for await event in stream {
                handleCrawlEvent(event)
            }
            // Stream finished
            activeCrawlEngine = nil
        }
    }

    func pauseCrawl() {
        guard let engine = activeCrawlEngine else { return }
        Task { await engine.pause() }
    }

    func cancelCrawl() {
        crawlEventTask?.cancel()
        Task { await activeCrawlEngine?.cancel() }
        activeCrawlEngine = nil
    }

    // MARK: — Event Handling

    private func handleCrawlEvent(_ event: CrawlEvent) {
        switch event {
        case .started(let id):
            if let session = try? db.fetchSession(id: id) {
                activeSession = session
            }

        case .urlFetched(let url):
            recentURLs.insert(url, at: 0)
            if recentURLs.count > 5000 {
                recentURLs = Array(recentURLs.prefix(5000))
            }

        case .statsUpdated(let stats):
            crawlStats = stats

        case .completed(let stats):
            crawlStats = stats
            if let session = activeSession {
                activeSession = try? db.fetchSession(id: session.id)
            }

        case .failed(let error):
            errorMessage = "Crawl failed: \(error)"
            activeCrawlEngine = nil

        default:
            break
        }
    }

    // MARK: — Computed

    var isCrawling: Bool { activeCrawlEngine != nil }

    var selectedSessionIssues: [Issue] {
        guard let session = activeSession else { return [] }
        return (try? db.fetchIssues(sessionID: session.id)) ?? []
    }
}
