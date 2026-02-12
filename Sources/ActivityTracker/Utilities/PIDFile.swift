import Foundation

enum PIDFile {
    private static var pidPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ActivityTracker")

        try? FileManager.default.createDirectory(
            atPath: appSupport.path,
            withIntermediateDirectories: true
        )

        return appSupport.appendingPathComponent("activity-tracker.pid").path
    }

    static func write() {
        let pid = ProcessInfo.processInfo.processIdentifier
        try? String(pid).write(toFile: pidPath, atomically: true, encoding: .utf8)
    }

    static func read() -> pid_t? {
        guard let content = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    static func remove() {
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    static func isRunning() -> Bool {
        guard let pid = read() else { return false }
        // kill with signal 0 checks if process exists without sending a signal
        return kill(pid, 0) == 0
    }

    static func sendStop() -> Bool {
        guard let pid = read() else {
            return false
        }
        // Send SIGTERM for graceful shutdown
        return kill(pid, SIGTERM) == 0
    }
}
