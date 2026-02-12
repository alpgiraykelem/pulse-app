import Cocoa

final class BackgroundMusicMonitor {
    private var mergers: [String: HeartbeatMerger] = [:]
    private var activeApps: Set<String> = []
    private let store: ActivityStore
    private let throttleInterval: TimeInterval = 8.0
    /// Per-app throttle timestamps. nil = first check hasn't happened yet for this app.
    private var lastChecks: [String: Date] = [:]

    private let musicApps: [String: String] = [
        "com.spotify.client": "Spotify",
        "com.apple.Music": "Music"
    ]

    /// Browsers that support AppleScript tab URL queries.
    /// Chrome-based: "active tab of front window"
    /// Safari: "current tab of front window"
    private let browserApps: [(bundleId: String, appName: String, isSafari: Bool)] = [
        ("com.google.Chrome", "Google Chrome", false),
        ("com.brave.Browser", "Brave Browser", false),
        ("com.microsoft.edgemac", "Microsoft Edge", false),
        ("com.apple.Safari", "Safari", true),
    ]

    init(store: ActivityStore) {
        self.store = store
    }

    func check(frontmostBundleId: String?, interval: Int) {
        let now = Date()

        let runningBundleIds = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )

        var currentlyPlaying = Set<String>()

        // 1. Check dedicated music apps (Spotify, Apple Music)
        checkMusicApps(now: now, frontmostBundleId: frontmostBundleId,
                       runningBundleIds: runningBundleIds, currentlyPlaying: &currentlyPlaying)

        // 2. Check browsers for YouTube background playback
        checkYouTube(now: now, frontmostBundleId: frontmostBundleId,
                     runningBundleIds: runningBundleIds, currentlyPlaying: &currentlyPlaying)

        // 3. Flush mergers for apps that stopped playing or came to foreground
        let stoppedApps = activeApps.subtracting(currentlyPlaying)
        for key in stoppedApps {
            mergers[key]?.flush()
            mergers.removeValue(forKey: key)
            lastChecks.removeValue(forKey: key)
        }

        activeApps = currentlyPlaying
    }

    func flushAll() {
        for (_, merger) in mergers {
            merger.flush()
        }
    }

    func stop() {
        flushAll()
        mergers.removeAll()
        activeApps.removeAll()
        lastChecks.removeAll()
    }

    // MARK: - Music Apps (Spotify, Apple Music)

    private func checkMusicApps(now: Date, frontmostBundleId: String?,
                                runningBundleIds: Set<String>,
                                currentlyPlaying: inout Set<String>) {
        for (bundleId, appName) in musicApps {
            // Skip if this app is in the foreground (foreground merger handles it)
            if frontmostBundleId == bundleId { continue }

            // Skip if the app isn't running (don't launch it via AppleScript)
            guard runningBundleIds.contains(bundleId) else { continue }

            // Per-app throttle
            if let lastCheck = lastChecks[bundleId] {
                let elapsed = now.timeIntervalSince(lastCheck)
                if elapsed < throttleInterval {
                    if activeApps.contains(bundleId) {
                        currentlyPlaying.insert(bundleId)
                    }
                    continue
                }
            } else {
                // First time — start timer, skip processing
                lastChecks[bundleId] = now
                continue
            }

            lastChecks[bundleId] = now

            guard let trackInfo = queryPlayingTrack(bundleId: bundleId) else { continue }

            currentlyPlaying.insert(bundleId)

            let merger = mergers[bundleId] ?? {
                let m = HeartbeatMerger(store: store, flushInterval: 30.0)
                mergers[bundleId] = m
                return m
            }()

            let heartbeat = Heartbeat(
                appName: appName,
                bundleId: bundleId,
                windowTitle: trackInfo,
                url: nil,
                extraInfo: "Background Listening"
            )

            merger.process(heartbeat: heartbeat, interval: Int(throttleInterval))
        }
    }

    // MARK: - YouTube (Browser Background Detection)

    private func checkYouTube(now: Date, frontmostBundleId: String?,
                              runningBundleIds: Set<String>,
                              currentlyPlaying: inout Set<String>) {
        let ytKey = "virtual.youtube"

        // Per-app throttle for YouTube
        if let lastCheck = lastChecks[ytKey] {
            let elapsed = now.timeIntervalSince(lastCheck)
            if elapsed < throttleInterval {
                if activeApps.contains(ytKey) {
                    currentlyPlaying.insert(ytKey)
                }
                return
            }
        } else {
            // First time — start timer, skip processing
            lastChecks[ytKey] = now
            return
        }

        lastChecks[ytKey] = now

        // Check each non-foreground browser for a YouTube active tab
        for browser in browserApps {
            // Skip if this browser is foreground (AppDetailExtractor already detects YouTube)
            if frontmostBundleId == browser.bundleId { continue }

            // Skip if browser not running
            guard runningBundleIds.contains(browser.bundleId) else { continue }

            guard let videoTitle = queryBrowserYouTube(appName: browser.appName, isSafari: browser.isSafari) else {
                continue
            }

            currentlyPlaying.insert(ytKey)

            let merger = mergers[ytKey] ?? {
                let m = HeartbeatMerger(store: store, flushInterval: 30.0)
                mergers[ytKey] = m
                return m
            }()

            let cleanTitle = videoTitle
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let heartbeat = Heartbeat(
                appName: "YouTube",
                bundleId: "virtual.youtube",
                windowTitle: cleanTitle,
                url: "youtube.com",
                extraInfo: "Background Listening"
            )

            merger.process(heartbeat: heartbeat, interval: Int(throttleInterval))
            return // Found YouTube in one browser, no need to check others
        }
    }

    /// Checks if the browser's active tab is a YouTube video page.
    /// Returns the tab title if YouTube is detected, nil otherwise.
    private func queryBrowserYouTube(appName: String, isSafari: Bool) -> String? {
        let script: String

        if isSafari {
            script = """
            tell application "Safari"
                if (count of windows) > 0 then
                    set tabURL to URL of current tab of front window
                    if tabURL contains "youtube.com/watch" or tabURL contains "music.youtube.com" then
                        return name of current tab of front window
                    end if
                end if
            end tell
            """
        } else {
            // Chrome-based browsers
            script = """
            tell application "\(appName)"
                if (count of windows) > 0 then
                    set tabURL to URL of active tab of front window
                    if tabURL contains "youtube.com/watch" or tabURL contains "music.youtube.com" then
                        return title of active tab of front window
                    end if
                end if
            end tell
            """
        }

        return runAppleScript(script)
    }

    // MARK: - Music Query

    private func queryPlayingTrack(bundleId: String) -> String? {
        let script: String
        switch bundleId {
        case "com.spotify.client":
            script = """
            tell application "Spotify"
                if player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    return trackName & " – " & artistName
                end if
            end tell
            """
        case "com.apple.Music":
            script = """
            tell application "Music"
                if player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    return trackName & " – " & artistName
                end if
            end tell
            """
        default:
            return nil
        }

        return runAppleScript(script)
    }

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
}
