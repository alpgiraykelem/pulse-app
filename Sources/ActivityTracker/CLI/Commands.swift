import ArgumentParser
import Cocoa

struct ActivityTrackerCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activity-tracker",
        abstract: "Track your macOS application usage automatically.",
        version: "1.0.0",
        subcommands: [Start.self, Stop.self, Status.self, Report.self, Install.self, Uninstall.self]
    )
}

// MARK: - Start

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start tracking with menu bar icon."
    )

    @Option(name: .long, help: "Polling interval in seconds.")
    var interval: Int = 2

    @Flag(name: .long, help: "Run in headless mode (no menu bar, for LaunchAgent).")
    var headless: Bool = false

    func run() throws {
        if headless {
            try runHeadless()
        } else {
            let app = StatusBarApp(interval: TimeInterval(interval))
            try app.run()
        }
    }

    private func runHeadless() throws {
        if PIDFile.isRunning() {
            print("\(Color.yellow)Pulse is already running.\(Color.reset)")
            throw ExitCode.failure
        }

        PermissionChecker.checkAll()

        let store = try ActivityStore()
        let merger = HeartbeatMerger(store: store)
        let monitor = WindowMonitor(interval: TimeInterval(interval), merger: merger, store: store)

        PIDFile.write()

        let signalHandler = SignalHandler {
            monitor.stop()
            PIDFile.remove()
        }
        signalHandler.setup()

        print("\(Color.green)Pulse started (headless).\(Color.reset)")
        monitor.start()
        RunLoop.main.run()
    }
}

// MARK: - Stop

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop tracking activity."
    )

    func run() throws {
        if PIDFile.sendStop() {
            print("\(Color.green)Pulse stopped.\(Color.reset)")
            Thread.sleep(forTimeInterval: 0.5)
            if !PIDFile.isRunning() {
                PIDFile.remove()
            }
        } else {
            print("\(Color.yellow)Pulse is not running.\(Color.reset)")
            PIDFile.remove()
        }
    }
}

// MARK: - Status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check if Pulse is running."
    )

    func run() throws {
        if PIDFile.isRunning() {
            let pid = PIDFile.read() ?? 0
            print("\(Color.green)Pulse is running.\(Color.reset) (PID: \(pid))")
        } else {
            print("\(Color.dim)Pulse is not running.\(Color.reset)")
            PIDFile.remove()
        }
    }
}

// MARK: - Report

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "View activity reports.",
        subcommands: [Today.self, Week.self, App.self, Timeline.self, Export.self]
    )
}

struct Today: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show today's activity summary."
    )

    @Option(name: .long, help: "Specific date (YYYY-MM-DD).")
    var date: String?

    @Flag(name: .long, help: "Open HTML report in browser.")
    var html: Bool = false

    func run() throws {
        let store = try ActivityStore()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = date ?? formatter.string(from: Date())
        let summary = try store.queryDay(date: dateStr)

        if html {
            let timeline = try store.queryTimeline(date: dateStr)
            let url = HTMLReportGenerator.generate(summary: summary, timeline: timeline)
            let jsonURL = HTMLReportGenerator.generateJSON(summary: summary, timeline: timeline)
            print("HTML report: \(url.path)")
            print("JSON report: \(jsonURL.path)")
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        } else {
            ReportFormatting.printDayReport(summary)
        }
    }
}

struct Week: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show this week's activity summary."
    )

    func run() throws {
        let store = try ActivityStore()
        let days = try store.queryWeek()
        ReportFormatting.printWeekReport(days)
    }
}

struct App: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show activity details for a specific app."
    )

    @Argument(help: "Application name (e.g., Safari, Terminal).")
    var name: String

    func run() throws {
        let store = try ActivityStore()
        let report = try store.queryApp(appName: name)
        ReportFormatting.printAppReport(report)
    }
}

struct Timeline: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show today's activity timeline."
    )

    @Option(name: .long, help: "Specific date (YYYY-MM-DD).")
    var date: String?

    func run() throws {
        let store = try ActivityStore()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = date ?? formatter.string(from: Date())
        let entries = try store.queryTimeline(date: dateStr)
        ReportFormatting.printTimeline(entries)
    }
}

// MARK: - Export

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export activity data as JSON for AI analysis."
    )

    @Flag(name: .long, help: "Export last 7 days.")
    var week: Bool = false

    @Flag(name: .long, help: "Export last 30 days.")
    var month: Bool = false

    @Option(name: .long, help: "Start date (YYYY-MM-DD).")
    var from: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD).")
    var to: String?

    func run() throws {
        let store = try ActivityStore()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let fromDate: String
        let toDate: String

        if week {
            toDate = formatter.string(from: Date())
            fromDate = formatter.string(from: Calendar.current.date(byAdding: .day, value: -6, to: Date())!)
        } else if month {
            toDate = formatter.string(from: Date())
            fromDate = formatter.string(from: Calendar.current.date(byAdding: .day, value: -29, to: Date())!)
        } else if let f = from, let t = to {
            fromDate = f
            toDate = t
        } else {
            print("\(Color.yellow)Specify --week, --month, or --from/--to date range.\(Color.reset)")
            throw ExitCode.failure
        }

        let days = try store.queryDays(from: fromDate, to: toDate)
        if days.isEmpty {
            print("\(Color.dim)No activity data found for \(fromDate) to \(toDate).\(Color.reset)")
            return
        }

        let url = HTMLReportGenerator.generateExportJSON(days: days)
        let totalDays = days.count
        let totalSeconds = days.reduce(0) { $0 + $1.totalSeconds }
        print("\(Color.green)Export complete!\(Color.reset)")
        print("  Days: \(totalDays)")
        print("  Total tracked: \(HTMLReportGenerator.dur(totalSeconds))")
        print("  File: \(url.path)")
    }
}

// MARK: - Install / Uninstall

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install LaunchAgent for automatic startup."
    )

    @Option(name: .long, help: "Path to the activity-tracker binary.")
    var binaryPath: String?

    func run() throws {
        try LaunchAgentManager.install(binaryPath: binaryPath)
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove LaunchAgent (stop automatic startup)."
    )

    func run() throws {
        try LaunchAgentManager.uninstall()
    }
}
