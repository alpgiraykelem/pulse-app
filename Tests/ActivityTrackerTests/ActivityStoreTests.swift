import XCTest
@testable import ActivityTracker

final class ActivityStoreTests: XCTestCase {
    func testInsertAndQuery() throws {
        let store = try ActivityStore(dbPath: temporaryDBPath())

        let record = ActivityRecord(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Apple - Apple",
            url: "https://apple.com",
            durationSeconds: 120,
            date: "2024-01-15"
        )

        try store.insert(record)

        let summary = try store.queryDay(date: "2024-01-15")
        XCTAssertEqual(summary.apps.count, 1)
        XCTAssertEqual(summary.apps.first?.appName, "Safari")
        XCTAssertEqual(summary.apps.first?.totalSeconds, 120)
    }

    func testUpdateDuration() throws {
        let store = try ActivityStore(dbPath: temporaryDBPath())

        let record = ActivityRecord(
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "~/Projects",
            durationSeconds: 10,
            date: "2024-01-15"
        )

        let id = try store.insert(record)
        try store.updateDuration(id: id, seconds: 60)

        let summary = try store.queryDay(date: "2024-01-15")
        XCTAssertEqual(summary.apps.first?.totalSeconds, 60)
    }

    func testQueryApp() throws {
        let store = try ActivityStore(dbPath: temporaryDBPath())

        try store.insert(ActivityRecord(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Google",
            url: "https://google.com",
            durationSeconds: 60,
            date: "2024-01-15"
        ))

        try store.insert(ActivityRecord(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Apple",
            url: "https://apple.com",
            durationSeconds: 30,
            date: "2024-01-15"
        ))

        try store.insert(ActivityRecord(
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "~/Projects",
            durationSeconds: 45,
            date: "2024-01-15"
        ))

        let report = try store.queryApp(appName: "Safari")
        XCTAssertEqual(report.totalSeconds, 90)
        XCTAssertEqual(report.topWindows.count, 2)
    }

    func testQueryTimeline() throws {
        let store = try ActivityStore(dbPath: temporaryDBPath())

        try store.insert(ActivityRecord(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Google",
            durationSeconds: 30,
            date: "2024-01-15"
        ))

        try store.insert(ActivityRecord(
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "~/Projects",
            durationSeconds: 20,
            date: "2024-01-15"
        ))

        let timeline = try store.queryTimeline(date: "2024-01-15")
        XCTAssertEqual(timeline.count, 2)
        XCTAssertEqual(timeline.first?.appName, "Safari")
    }

    private func temporaryDBPath() -> String {
        let tmp = NSTemporaryDirectory()
        return tmp + "test-\(UUID().uuidString).db"
    }
}
