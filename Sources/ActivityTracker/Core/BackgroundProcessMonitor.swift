import Foundation

struct BackgroundProcess {
    let tabId: String     // unique key per tab
    let windowTitle: String
    let processName: String
    let directory: String?
}

final class BackgroundProcessMonitor {
    private var mergers: [String: HeartbeatMerger] = [:]
    private var activeTabIds: Set<String> = []
    private let store: ActivityStore
    private let throttleInterval: TimeInterval = 6.0
    private var lastCheck: Date = .distantPast

    init(store: ActivityStore) {
        self.store = store
    }

    func check(frontmostBundleId: String?, interval: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastCheck) >= throttleInterval else { return }
        lastCheck = now

        let processes = queryTerminalProcesses()
        var currentTabIds = Set<String>()

        for proc in processes {
            currentTabIds.insert(proc.tabId)

            let merger = mergers[proc.tabId] ?? {
                let m = HeartbeatMerger(store: store, flushInterval: 30.0)
                mergers[proc.tabId] = m
                return m
            }()

            // Parse project name from Terminal window title
            // Format: "SessionName — · WindowName — processes TERM_PROGRAM=..."
            let parsedTitle = parseProjectName(from: proc.windowTitle, processName: proc.processName)

            let heartbeat = Heartbeat(
                appName: "Terminal (bg)",
                bundleId: "com.apple.Terminal.background",
                windowTitle: parsedTitle,
                url: nil,
                extraInfo: proc.processName + (proc.directory != nil ? " · \(proc.directory!)" : "")
            )

            let elapsed = Int(throttleInterval)
            merger.process(heartbeat: heartbeat, interval: elapsed)
        }

        // Flush mergers for tabs whose processes ended
        let stoppedTabs = activeTabIds.subtracting(currentTabIds)
        for tabId in stoppedTabs {
            mergers[tabId]?.flush()
            mergers.removeValue(forKey: tabId)
        }

        activeTabIds = currentTabIds
    }

    func flushAll() {
        for (_, merger) in mergers {
            merger.flush()
        }
    }

    func stop() {
        flushAll()
        mergers.removeAll()
        activeTabIds.removeAll()
    }

    // MARK: - Terminal Query

    private func queryTerminalProcesses() -> [BackgroundProcess] {
        // shells to ignore - only track actual running commands
        let shells: Set<String> = ["bash", "zsh", "sh", "fish", "login", "-bash", "-zsh", "-sh", "-fish"]

        let script = """
        tell application "Terminal"
            set output to ""
            set winIdx to 0
            repeat with w in windows
                set winIdx to winIdx + 1
                set tabIdx to 0
                repeat with t in tabs of w
                    set tabIdx to tabIdx + 1
                    set procs to processes of t
                    if (count of procs) > 0 then
                        set lastProc to item -1 of procs
                        set allProcs to ""
                        repeat with p in procs
                            set allProcs to allProcs & (p as text) & ","
                        end repeat
                        set wName to name of w
                        set output to output & winIdx & ":" & tabIdx & "|||" & lastProc & "|||" & allProcs & "|||" & wName & "###"
                    end if
                end repeat
            end repeat
            return output
        end tell
        """

        guard let result = runAppleScript(script), !result.isEmpty else {
            return []
        }

        var processes: [BackgroundProcess] = []

        let entries = result.components(separatedBy: "###").filter { !$0.isEmpty }
        for entry in entries {
            let parts = entry.components(separatedBy: "|||")
            guard parts.count >= 4 else { continue }

            let tabId = parts[0].trimmingCharacters(in: .whitespaces)
            let lastProcess = parts[1].trimmingCharacters(in: .whitespaces)
            let allProcsStr = parts[2]
            let windowName = parts[3].trimmingCharacters(in: .whitespaces)

            // Check if there's a non-shell process running
            let allProcs = allProcsStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let hasActiveProcess = allProcs.contains { proc in
                !shells.contains(proc) && !shells.contains("-" + proc)
            }

            guard hasActiveProcess else { continue }

            // Find the actual command (last non-shell process)
            let command = allProcs.last { proc in
                !shells.contains(proc) && !shells.contains("-" + proc)
            } ?? lastProcess

            // Parse directory from window name
            let directory = parseDirectory(from: windowName)

            processes.append(BackgroundProcess(
                tabId: tabId,
                windowTitle: windowName,
                processName: command,
                directory: directory
            ))
        }

        return processes
    }

    /// Extract meaningful project name from Terminal window title.
    /// Input examples:
    ///   "Bornova App — · Bornova Miras Translation — caffeinate · claude TERM_PROGRAM=Apple_Terminal — 120×35"
    ///   "activity tracker — * Activity Tracker Cleanup — sourcekit-lsp · claude TERM_PROG..."
    ///   "user@host: ~/projects/foo — node — 80×24"
    /// Returns the session+window name part, e.g. "Bornova App — Bornova Miras Translation"
    private func parseProjectName(from windowTitle: String, processName: String) -> String {
        // Split by " — " segments
        let segments = windowTitle.components(separatedBy: " — ")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard segments.count >= 2 else {
            return windowTitle
        }

        // First segment: session/dir name (e.g. "Bornova App" or "user@host: ~/path")
        let session = segments[0]

        // Second segment: often has tmux indicators like "· " or "* " before the window name
        let rawWindow = segments[1]
        let windowName = rawWindow
            .replacingOccurrences(of: "^[·\\*\\-\\+!#] ", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // If windowName looks like a process chain (contains TERM_PROGRAM or is just the process name), skip it
        if windowName.contains("TERM_PROGRAM") || windowName == processName {
            return session
        }

        // If windowName is a meaningful name, combine session + window
        return "\(session) — \(windowName)"
    }

    private func parseDirectory(from title: String) -> String? {
        if let colonRange = title.range(of: ": ") {
            return String(title[colonRange.upperBound...])
                .components(separatedBy: " — ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if title.contains("~") || title.hasPrefix("/") {
            return title.components(separatedBy: " — ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
}
