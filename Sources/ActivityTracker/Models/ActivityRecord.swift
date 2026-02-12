import Foundation

struct ActivityRecord {
    var id: Int64?
    let timestamp: Date
    let appName: String
    let bundleId: String
    let windowTitle: String
    let url: String?
    let extraInfo: String?
    var durationSeconds: Int
    let date: String // YYYY-MM-DD

    init(
        id: Int64? = nil,
        timestamp: Date = Date(),
        appName: String,
        bundleId: String,
        windowTitle: String,
        url: String? = nil,
        extraInfo: String? = nil,
        durationSeconds: Int = 0,
        date: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.extraInfo = extraInfo
        self.durationSeconds = durationSeconds

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.date = date ?? formatter.string(from: timestamp)
    }
}

struct ActivitySummary: Codable {
    let appName: String
    let bundleId: String
    let totalSeconds: Int
    let windowDetails: [WindowDetail]
}

struct WindowDetail: Codable {
    let windowTitle: String
    let url: String?
    let extraInfo: String?
    let totalSeconds: Int
    let activityIds: [Int64]

    init(windowTitle: String, url: String?, extraInfo: String?, totalSeconds: Int, activityIds: [Int64] = []) {
        self.windowTitle = windowTitle
        self.url = url
        self.extraInfo = extraInfo
        self.totalSeconds = totalSeconds
        self.activityIds = activityIds
    }
}

struct DaySummary: Codable {
    let date: String
    let totalSeconds: Int
    let apps: [ActivitySummary]
    let wallClockSeconds: Int
    let activeTrackingSeconds: Int
    let firstActivity: String?
    let lastActivity: String?
}

struct AppDetailReport: Codable {
    let appName: String
    let totalSeconds: Int
    let days: [DayBreakdown]
    let topWindows: [WindowDetail]
}

struct DayBreakdown: Codable {
    let date: String
    let totalSeconds: Int
}

struct TimelineEntry: Codable {
    let timestamp: Date
    let appName: String
    let windowTitle: String
    let url: String?
    let extraInfo: String?
    let durationSeconds: Int
}
