import Foundation

enum Color {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let white = "\u{001B}[37m"

    static let appColors = [cyan, green, yellow, magenta, blue, red]

    static func forIndex(_ i: Int) -> String {
        appColors[i % appColors.count]
    }
}

enum ReportFormatting {
    // MARK: - Duration Formatting

    static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let m = seconds / 60
            let s = seconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        } else {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
    }

    // MARK: - Bar Graph

    static func bar(fraction: Double, width: Int = 30) -> String {
        let filled = Int(fraction * Double(width))
        let empty = width - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    // MARK: - Day Report

    static func printDayReport(_ summary: DaySummary) {
        let header = "\(Color.bold)\(Color.white)📊 Activity Report: \(summary.date)\(Color.reset)"
        print(header)
        print("\(Color.dim)\(String(repeating: "─", count: 50))\(Color.reset)")
        print("Total tracked: \(Color.bold)\(formatDuration(summary.totalSeconds))\(Color.reset)")
        print()

        if summary.apps.isEmpty {
            print("\(Color.dim)No activity recorded.\(Color.reset)")
            return
        }

        let maxNameLen = summary.apps.map(\.appName.count).max() ?? 10

        for (i, app) in summary.apps.enumerated() {
            let color = Color.forIndex(i)
            let percent = summary.totalSeconds > 0
                ? Double(app.totalSeconds) / Double(summary.totalSeconds) * 100
                : 0
            let percentStr = String(format: "%5.1f%%", percent)
            let duration = formatDuration(app.totalSeconds)
            let paddedName = app.appName.padding(toLength: maxNameLen, withPad: " ", startingAt: 0)
            let barGraph = bar(fraction: Double(app.totalSeconds) / Double(summary.totalSeconds))

            print("\(color)\(paddedName)\(Color.reset)  \(barGraph)  \(Color.bold)\(duration)\(Color.reset)  \(Color.dim)\(percentStr)\(Color.reset)")
        }
        print()
    }

    // MARK: - Week Report

    static func printWeekReport(_ days: [DaySummary]) {
        print("\(Color.bold)\(Color.white)📊 Weekly Activity Report\(Color.reset)")
        print("\(Color.dim)\(String(repeating: "─", count: 50))\(Color.reset)")

        if days.isEmpty {
            print("\(Color.dim)No activity recorded this week.\(Color.reset)")
            return
        }

        let maxSeconds = days.map(\.totalSeconds).max() ?? 1

        for day in days {
            let barGraph = bar(fraction: Double(day.totalSeconds) / Double(maxSeconds), width: 25)
            let duration = formatDuration(day.totalSeconds)
            let appCount = day.apps.count

            // Format date nicely
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let displayDate: String
            if let date = formatter.date(from: day.date) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "EEE, MMM d"
                displayDate = displayFormatter.string(from: date)
            } else {
                displayDate = day.date
            }

            let paddedDate = displayDate.padding(toLength: 12, withPad: " ", startingAt: 0)
            print("\(Color.cyan)\(paddedDate)\(Color.reset)  \(barGraph)  \(Color.bold)\(duration)\(Color.reset)  \(Color.dim)(\(appCount) apps)\(Color.reset)")
        }

        let totalSeconds = days.reduce(0) { $0 + $1.totalSeconds }
        let avgSeconds = totalSeconds / max(days.count, 1)
        print()
        print("Total: \(Color.bold)\(formatDuration(totalSeconds))\(Color.reset)  |  Daily avg: \(Color.bold)\(formatDuration(avgSeconds))\(Color.reset)")
        print()
    }

    // MARK: - App Detail Report

    static func printAppReport(_ report: AppDetailReport) {
        print("\(Color.bold)\(Color.white)📊 App Detail: \(report.appName)\(Color.reset)")
        print("\(Color.dim)\(String(repeating: "─", count: 50))\(Color.reset)")
        print("Total time: \(Color.bold)\(formatDuration(report.totalSeconds))\(Color.reset)")
        print()

        if !report.days.isEmpty {
            print("\(Color.bold)Daily Breakdown:\(Color.reset)")
            let maxSeconds = report.days.map(\.totalSeconds).max() ?? 1
            for day in report.days.prefix(14) {
                let barGraph = bar(fraction: Double(day.totalSeconds) / Double(maxSeconds), width: 20)
                print("  \(Color.cyan)\(day.date)\(Color.reset)  \(barGraph)  \(formatDuration(day.totalSeconds))")
            }
            print()
        }

        if !report.topWindows.isEmpty {
            print("\(Color.bold)Top Windows/Pages:\(Color.reset)")
            for (i, window) in report.topWindows.prefix(15).enumerated() {
                let num = String(format: "%2d", i + 1)
                let title = String(window.windowTitle.prefix(60))
                print("  \(Color.dim)\(num).\(Color.reset) \(Color.green)\(title)\(Color.reset)  \(formatDuration(window.totalSeconds))")
                if let url = window.url {
                    print("      \(Color.dim)\(String(url.prefix(70)))\(Color.reset)")
                }
            }
            print()
        }
    }

    // MARK: - Timeline

    static func printTimeline(_ entries: [TimelineEntry]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        print("\(Color.bold)\(Color.white)📊 Timeline\(Color.reset)")
        print("\(Color.dim)\(String(repeating: "─", count: 50))\(Color.reset)")

        if entries.isEmpty {
            print("\(Color.dim)No activity recorded.\(Color.reset)")
            return
        }

        var lastApp = ""
        for entry in entries {
            let time = formatter.string(from: entry.timestamp)
            let duration = formatDuration(entry.durationSeconds)
            let title = String(entry.windowTitle.prefix(50))

            if entry.appName != lastApp {
                print()
                print("  \(Color.bold)\(Color.cyan)\(entry.appName)\(Color.reset)")
                lastApp = entry.appName
            }

            print("    \(Color.dim)\(time)\(Color.reset)  \(title)  \(Color.green)\(duration)\(Color.reset)")
            if let url = entry.url {
                print("             \(Color.dim)\(String(url.prefix(60)))\(Color.reset)")
            }
        }
        print()
    }
}
