import Foundation

/// Priority queue + deduplication layer for the crawl frontier.
///
/// Design:
/// - In-memory min-heap prioritised by (depth, discovery time).
/// - Seen-URL set keyed on normalized URL strings, preventing duplicate fetches.
/// - Spills to the database `url_queue` table when in-memory count exceeds `spillThreshold`.
/// - Automatically refills from the database when the in-memory queue drains below `refillThreshold`.
/// - All mutations are actor-isolated — safe to call from many concurrent crawl workers.
actor URLFrontier {

    private let sessionID: UUID
    private let db: DatabaseManager
    private let normalizer: URLNormalizer
    private var heap: [PendingURL] = []
    private var seenURLs: Set<String> = []
    private var spillThreshold: Int
    private var refillThreshold: Int
    private var spilledCount: Int = 0
    private var totalEnqueued: Int = 0

    // MARK: — Init

    init(
        sessionID: UUID,
        db: DatabaseManager,
        normalizer: URLNormalizer,
        spillThreshold: Int = 10_000,
        refillThreshold: Int = 500
    ) {
        self.sessionID = sessionID
        self.db = db
        self.normalizer = normalizer
        self.spillThreshold = spillThreshold
        self.refillThreshold = refillThreshold
    }

    // MARK: — Seeding

    /// Add seed URLs to the frontier.
    func seed(urls: [String], depth: Int = 0) {
        for rawURL in urls {
            guard let normalized = normalizer.normalize(rawURL),
                  !seenURLs.contains(normalized.absoluteString) else { continue }
            let pending = PendingURL(
                url: rawURL,
                normalizedURL: normalized.absoluteString,
                depth: depth,
                priority: priority(depth: depth, discoveredAt: Date())
            )
            enqueueInMemory(pending)
        }
    }

    /// Enqueue newly-discovered URLs from a crawled page.
    func enqueue(urls: [(url: String, depth: Int)]) {
        let now = Date()
        for (rawURL, depth) in urls {
            guard let normalized = normalizer.normalize(rawURL),
                  !seenURLs.contains(normalized.absoluteString) else { continue }
            seenURLs.insert(normalized.absoluteString)
            totalEnqueued += 1

            let pending = PendingURL(
                url: rawURL,
                normalizedURL: normalized.absoluteString,
                depth: depth,
                priority: priority(depth: depth, discoveredAt: now)
            )

            if heap.count < spillThreshold {
                enqueueInMemory(pending)
            } else {
                spillToDB(pending)
            }
        }
    }

    // MARK: — Dequeue

    /// Returns the next URL to crawl, or nil if the frontier is exhausted.
    func next() -> PendingURL? {
        if heap.isEmpty && spilledCount > 0 {
            refillFromDB()
        }
        guard !heap.isEmpty else { return nil }
        return heapPop()
    }

    // MARK: — State

    var isEmpty: Bool { heap.isEmpty && spilledCount == 0 }

    var count: Int { heap.count + spilledCount }

    var seenCount: Int { seenURLs.count }

    /// Mark a URL as seen without enqueueing it (e.g. already in DB from a prior crawl).
    func markSeen(_ normalizedURL: String) {
        seenURLs.insert(normalizedURL)
    }

    func isSeen(_ normalizedURL: String) -> Bool {
        seenURLs.contains(normalizedURL)
    }

    // MARK: — Checkpointing

    func checkpoint() -> FrontierCheckpoint {
        FrontierCheckpoint(
            pendingURLs: heap.map { .init(url: $0.url, depth: $0.depth, priority: $0.priority) },
            seenURLs: Array(seenURLs),
            savedAt: Date()
        )
    }

    func restore(from checkpoint: FrontierCheckpoint) {
        seenURLs = Set(checkpoint.seenURLs)
        heap = []
        for item in checkpoint.pendingURLs {
            let pending = PendingURL(
                url: item.url,
                normalizedURL: item.url,  // already normalized in checkpoint
                depth: item.depth,
                priority: item.priority
            )
            heapPush(pending)
        }
    }

    // MARK: — Min-Heap Internals

    private func enqueueInMemory(_ pending: PendingURL) {
        seenURLs.insert(pending.normalizedURL)
        totalEnqueued += 1
        heapPush(pending)
    }

    private func heapPush(_ item: PendingURL) {
        heap.append(item)
        siftUp(heap.count - 1)
    }

    private func heapPop() -> PendingURL {
        heap.swapAt(0, heap.count - 1)
        let item = heap.removeLast()
        if !heap.isEmpty { siftDown(0) }
        return item
    }

    private func siftUp(_ idx: Int) {
        var i = idx
        while i > 0 {
            let parent = (i - 1) / 2
            if heap[i].priority < heap[parent].priority {
                heap.swapAt(i, parent)
                i = parent
            } else { break }
        }
    }

    private func siftDown(_ idx: Int) {
        var i = idx
        let n = heap.count
        while true {
            var smallest = i
            let l = 2 * i + 1, r = 2 * i + 2
            if l < n && heap[l].priority < heap[smallest].priority { smallest = l }
            if r < n && heap[r].priority < heap[smallest].priority { smallest = r }
            if smallest == i { break }
            heap.swapAt(i, smallest)
            i = smallest
        }
    }

    // MARK: — DB Spill / Refill

    private func spillToDB(_ pending: PendingURL) {
        do {
            try db.pool.write { db in
                try db.execute(sql: """
                    INSERT OR IGNORE INTO url_queue (session_id, url, depth, priority, enqueued_at)
                    VALUES (?, ?, ?, ?, ?)
                """, arguments: [
                    sessionID.uuidString,
                    pending.normalizedURL,
                    pending.depth,
                    pending.priority,
                    Date().timeIntervalSince1970,
                ])
            }
            spilledCount += 1
        } catch {
            // Best-effort: if spill fails, the URL is lost for this session.
            // Acceptable — it can be re-discovered via links.
        }
    }

    private func refillFromDB() {
        let batchSize = spillThreshold / 2
        do {
            let rows = try db.pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT url, depth, priority FROM url_queue
                    WHERE session_id = ?
                    ORDER BY priority ASC
                    LIMIT ?
                """, arguments: [sessionID.uuidString, batchSize])
            }

            var refilled = 0
            for row in rows {
                let url: String = row["url"]
                guard !seenURLs.contains(url) else { continue }
                let pending = PendingURL(
                    url: url,
                    normalizedURL: url,
                    depth: row["depth"],
                    priority: row["priority"]
                )
                heapPush(pending)
                refilled += 1
            }

            if refilled > 0 {
                try? db.pool.write { db in
                    try db.execute(sql: """
                        DELETE FROM url_queue
                        WHERE session_id = ? AND url IN (
                            SELECT url FROM url_queue WHERE session_id = ?
                            ORDER BY priority ASC LIMIT ?
                        )
                    """, arguments: [sessionID.uuidString, sessionID.uuidString, refilled])
                }
                spilledCount = max(0, spilledCount - refilled)
            }
        } catch { }
    }

    // MARK: — Priority Calculation

    private func priority(depth: Int, discoveredAt: Date) -> Double {
        // Lower value = higher priority.
        // Breadth-first with shallow pages prioritised.
        Double(depth) * 1_000_000 + discoveredAt.timeIntervalSince1970
    }
}

// MARK: — PendingURL

struct PendingURL: Sendable {
    let url: String
    let normalizedURL: String
    let depth: Int
    let priority: Double
}
