import Foundation

struct Heartbeat {
    let appName: String
    let bundleId: String
    let windowTitle: String
    let url: String?
    let extraInfo: String?
}

final class HeartbeatMerger {
    private let store: ActivityStore
    private let flushInterval: TimeInterval
    private let projectMatcher: ProjectMatcher?

    private var currentRecord: ActivityRecord?
    private var currentRecordId: Int64?
    private var lastFlush: Date = Date()
    private var accumulatedSeconds: Int = 0

    /// True when the current activity is a passive consumption app
    /// (video, music, PDF, books) where idle detection should not pause tracking.
    var isCurrentPassiveMedia: Bool {
        guard let record = currentRecord else { return false }
        let passiveBundleIds: Set<String> = [
            "virtual.youtube",
            "com.spotify.client",
            "com.apple.Music",
            "com.apple.TV",
            // PDF & Book readers
            "com.apple.Preview",
            "com.apple.iBooksX",
            "com.apple.iBooks",
            "com.readdle.PDFExpert-Mac",
            "net.shinyfrog.bear",
            "com.adobe.Reader",
            "com.adobe.Acrobat.Pro",
        ]
        if passiveBundleIds.contains(record.bundleId) {
            return true
        }
        // Detect PDF/book content in browser or other apps by window title
        let title = record.windowTitle.lowercased()
        if title.hasSuffix(".pdf") || title.contains(".pdf —") || title.contains(".pdf –") {
            return true
        }
        return false
    }

    init(store: ActivityStore, flushInterval: TimeInterval = 30.0, projectMatcher: ProjectMatcher? = nil) {
        self.store = store
        self.flushInterval = flushInterval
        self.projectMatcher = projectMatcher
    }

    func process(heartbeat: Heartbeat, interval: Int) {
        let isSame = currentRecord.map { record in
            if record.bundleId == heartbeat.bundleId && record.appName == heartbeat.appName {
                // For media/streaming apps, merge by app only (title changes as content plays)
                if heartbeat.bundleId.hasPrefix("virtual.") ||
                   heartbeat.bundleId == "com.spotify.client" ||
                   heartbeat.bundleId == "com.apple.Music" {
                    return true
                }
                return record.windowTitle == heartbeat.windowTitle
            }
            return false
        } ?? false

        if isSame {
            accumulatedSeconds += interval
            // Update window title to latest (keeps the most recent title in the record)
            if let current = currentRecord, current.windowTitle != heartbeat.windowTitle {
                currentRecord = ActivityRecord(
                    appName: heartbeat.appName,
                    bundleId: heartbeat.bundleId,
                    windowTitle: heartbeat.windowTitle,
                    url: heartbeat.url,
                    extraInfo: heartbeat.extraInfo,
                    durationSeconds: accumulatedSeconds
                )
                if let id = currentRecordId {
                    try? store.updateWindowTitle(id: id, title: heartbeat.windowTitle,
                                                  url: heartbeat.url, extraInfo: heartbeat.extraInfo)
                }
            }
            periodicFlush()
        } else {
            flush()
            startNew(heartbeat: heartbeat, interval: interval)
        }
    }

    func flush() {
        guard let id = currentRecordId, accumulatedSeconds > 0 else { return }
        do {
            try store.updateDuration(id: id, seconds: accumulatedSeconds)
        } catch {
            print("Failed to flush activity: \(error)")
        }
    }

    private func startNew(heartbeat: Heartbeat, interval: Int) {
        let record = ActivityRecord(
            appName: heartbeat.appName,
            bundleId: heartbeat.bundleId,
            windowTitle: heartbeat.windowTitle,
            url: heartbeat.url,
            extraInfo: heartbeat.extraInfo,
            durationSeconds: interval
        )

        do {
            let matchedProjectId = projectMatcher?.match(heartbeat: heartbeat)
            let source: ProjectSource? = matchedProjectId != nil ? .autoRule : nil
            let id = try store.insert(record, projectId: matchedProjectId, projectSource: source)
            currentRecord = record
            currentRecordId = id
            accumulatedSeconds = interval
            lastFlush = Date()
        } catch {
            print("Failed to insert activity: \(error)")
        }
    }

    private func periodicFlush() {
        let now = Date()
        if now.timeIntervalSince(lastFlush) >= flushInterval {
            flush()
            lastFlush = now
        }
    }
}
