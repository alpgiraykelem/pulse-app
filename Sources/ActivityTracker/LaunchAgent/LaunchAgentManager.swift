import Foundation

enum LaunchAgentManager {
    private static let label = "com.alpgiraykelem.activity-tracker"

    private static var plistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist").path
    }

    private static var logDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/ActivityTracker").path
    }

    static func install(binaryPath: String? = nil) throws {
        let binary = binaryPath ?? findBinary()

        guard FileManager.default.fileExists(atPath: binary) else {
            throw LaunchAgentError.binaryNotFound(binary)
        }

        // Create log directory
        try FileManager.default.createDirectory(
            atPath: logDir,
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary, "start"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "LowPriorityBackgroundIO": true,
            "Nice": 10,
            "StandardOutPath": "\(logDir)/stdout.log",
            "StandardErrorPath": "\(logDir)/stderr.log",
            "ProcessType": "Background",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        // Ensure LaunchAgents directory exists
        let launchAgentsDir = (plistPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: launchAgentsDir,
            withIntermediateDirectories: true
        )

        try data.write(to: URL(fileURLWithPath: plistPath))

        // Load the agent
        let result = Process()
        result.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        result.arguments = ["load", plistPath]
        try result.run()
        result.waitUntilExit()

        let green = "\(Color.green)"
        let reset = "\(Color.reset)"
        print("\(green)LaunchAgent installed successfully.\(reset)")
        print("  Plist: \(plistPath)")
        print("  Binary: \(binary)")
        print("  Logs: \(logDir)/")
        print("  Activity Tracker will start automatically on login.")
    }

    static func uninstall() throws {
        // Unload the agent first
        if FileManager.default.fileExists(atPath: plistPath) {
            let result = Process()
            result.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            result.arguments = ["unload", plistPath]
            try result.run()
            result.waitUntilExit()

            try FileManager.default.removeItem(atPath: plistPath)
        }

        let green = "\(Color.green)"
        let reset = "\(Color.reset)"
        print("\(green)LaunchAgent uninstalled.\(reset)")
        print("  Activity Tracker will no longer start automatically.")
    }

    private static func findBinary() -> String {
        // Check common locations
        let candidates = [
            "/usr/local/bin/activity-tracker",
            ProcessInfo.processInfo.arguments.first ?? "",
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // Fall back to current executable
        return ProcessInfo.processInfo.arguments.first ?? "/usr/local/bin/activity-tracker"
    }
}

enum LaunchAgentError: LocalizedError {
    case binaryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "Binary not found at: \(path). Build with 'swift build -c release' first."
        }
    }
}
