import XCTest
@testable import ActivityTracker

final class HeartbeatMergerTests: XCTestCase {
    func testSameActivityMerges() throws {
        let store = try ActivityStore(dbPath: temporaryDBPath())
        let merger = HeartbeatMerger(store: store, flushInterval: 1.0)

        let heartbeat = Heartbeat(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Apple",
            url: "https://apple.com",
            extraInfo: nil
        )

        // Send 5 heartbeats of the same activity
        for _ in 0..<5 {
            merger.process(heartbeat: heartbeat, interval: 2)
        }
        merger.flush()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let summary = try store.queryDay(date: today)

        // Should be merged into a single entry
        XCTAssertEqual(summary.apps.count, 1)
        XCTAssertEqual(summary.apps.first?.appName, "Safari")
        XCTAssertEqual(summary.apps.first?.totalSeconds, 10) // 5 * 2s
    }

    func testDifferentActivitiesCreateSeparateRecords() throws {
        let store = try ActivityStore(dbPath: temporaryDBPath())
        let merger = HeartbeatMerger(store: store, flushInterval: 1.0)

        let safari = Heartbeat(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Apple",
            url: nil,
            extraInfo: nil
        )

        let terminal = Heartbeat(
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "~/Projects",
            url: nil,
            extraInfo: nil
        )

        merger.process(heartbeat: safari, interval: 2)
        merger.process(heartbeat: safari, interval: 2)
        merger.process(heartbeat: terminal, interval: 2)
        merger.process(heartbeat: terminal, interval: 2)
        merger.flush()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let summary = try store.queryDay(date: today)

        XCTAssertEqual(summary.apps.count, 2)
    }

    private func temporaryDBPath() -> String {
        let tmp = NSTemporaryDirectory()
        return tmp + "test-\(UUID().uuidString).db"
    }
}
