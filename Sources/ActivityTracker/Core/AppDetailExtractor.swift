import Cocoa
import ApplicationServices

struct AppDetails {
    let windowTitleOverride: String?
    let url: String?
    let extraInfo: String?
    let appNameOverride: String?
    let bundleIdOverride: String?

    init(windowTitleOverride: String? = nil, url: String? = nil, extraInfo: String? = nil,
         appNameOverride: String? = nil, bundleIdOverride: String? = nil) {
        self.windowTitleOverride = windowTitleOverride
        self.url = url
        self.extraInfo = extraInfo
        self.appNameOverride = appNameOverride
        self.bundleIdOverride = bundleIdOverride
    }
}

final class AppDetailExtractor {
    private var lastSafariQuery: Date = .distantPast
    private var cachedSafariDetails: AppDetails?
    private let safariThrottleInterval: TimeInterval = 4.0

    private var lastTerminalQuery: Date = .distantPast
    private var cachedTerminalDetails: AppDetails?
    private let terminalThrottleInterval: TimeInterval = 3.0

    private var lastFigmaQuery: Date = .distantPast
    private var cachedFigmaDetails: AppDetails?
    private let figmaThrottleInterval: TimeInterval = 3.0

    private var lastMusicQuery: Date = .distantPast
    private var cachedMusicDetails: AppDetails?
    private let musicThrottleInterval: TimeInterval = 5.0

    func extract(bundleId: String, windowTitle: String) -> AppDetails {
        switch bundleId {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return extractSafariDetails()
        case "com.apple.Terminal":
            return extractTerminalDetails()
        case "com.googlecode.iterm2":
            return extractITermDetails()
        case "com.figma.Desktop":
            return extractFigmaDetails(windowTitle: windowTitle)
        case "com.spotify.client":
            return extractSpotifyDetails()
        case "com.apple.Music":
            return extractAppleMusicDetails()
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
             "org.mozilla.firefox", "company.thebrowser.Browser":
            return extractChromiumDetails(bundleId: bundleId, windowTitle: windowTitle)
        default:
            return AppDetails(windowTitleOverride: nil, url: nil, extraInfo: nil)
        }
    }

    // MARK: - Safari

    private func extractSafariDetails() -> AppDetails {
        let now = Date()
        if now.timeIntervalSince(lastSafariQuery) < safariThrottleInterval,
           let cached = cachedSafariDetails {
            return cached
        }
        lastSafariQuery = now

        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                set theURL to URL of current tab of front window
                set theTitle to name of current tab of front window
                return theURL & "|||" & theTitle
            end if
        end tell
        """

        guard let result = runAppleScript(script) else {
            cachedSafariDetails = AppDetails(windowTitleOverride: nil, url: nil, extraInfo: nil)
            return cachedSafariDetails!
        }

        let parts = result.components(separatedBy: "|||")
        let url = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

        let siteOverride = detectSiteOverride(url: url, windowTitle: title)

        let details = AppDetails(
            windowTitleOverride: siteOverride?.title ?? title,
            url: url,
            extraInfo: siteOverride?.tag,
            appNameOverride: siteOverride?.appName,
            bundleIdOverride: siteOverride?.bundleId
        )
        cachedSafariDetails = details
        return details
    }

    // MARK: - Terminal

    private func extractTerminalDetails() -> AppDetails {
        let now = Date()
        if now.timeIntervalSince(lastTerminalQuery) < terminalThrottleInterval,
           let cached = cachedTerminalDetails {
            return cached
        }
        lastTerminalQuery = now

        let script = """
        tell application "Terminal"
            if (count of windows) > 0 then
                set tabName to name of front window
                set tabCustom to custom title of selected tab of front window
                if tabCustom is not "" then
                    return tabCustom & "|||" & tabName
                else
                    return tabName & "|||" & tabName
                end if
            end if
        end tell
        """

        guard let result = runAppleScript(script) else {
            cachedTerminalDetails = AppDetails(windowTitleOverride: nil, url: nil, extraInfo: nil)
            return cachedTerminalDetails!
        }

        let parts = result.components(separatedBy: "|||")
        let customTitle = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowName = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : customTitle

        // Parse directory from window name: "user@host: ~/path — -zsh — 80×24"
        let directory = parseTerminalDirectory(from: windowName ?? "")

        let details = AppDetails(
            windowTitleOverride: windowName,
            url: nil,
            extraInfo: directory
        )
        cachedTerminalDetails = details
        return details
    }

    private func extractITermDetails() -> AppDetails {
        let now = Date()
        if now.timeIntervalSince(lastTerminalQuery) < terminalThrottleInterval,
           let cached = cachedTerminalDetails {
            return cached
        }
        lastTerminalQuery = now

        let script = """
        tell application "iTerm2"
            if (count of windows) > 0 then
                set sessionName to name of current session of current tab of front window
                return sessionName
            end if
        end tell
        """

        let result = runAppleScript(script)
        let directory = result.flatMap { parseTerminalDirectory(from: $0) }

        let details = AppDetails(
            windowTitleOverride: result,
            url: nil,
            extraInfo: directory
        )
        cachedTerminalDetails = details
        return details
    }

    private func parseTerminalDirectory(from title: String) -> String? {
        // Formats: "user@host: ~/path", "~/path — -zsh", "user@host:~/path"
        var path: String? = nil

        if let colonRange = title.range(of: ": ") {
            path = String(title[colonRange.upperBound...])
                .components(separatedBy: " — ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let colonRange = title.range(of: ":") {
            let after = String(title[colonRange.upperBound...])
            if after.hasPrefix("~") || after.hasPrefix("/") {
                path = after.components(separatedBy: " ").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if path == nil, title.contains("~") || title.hasPrefix("/") {
            path = title
                .components(separatedBy: " — ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return path
    }

    // MARK: - Figma

    private func extractFigmaDetails(windowTitle: String) -> AppDetails {
        let now = Date()
        if now.timeIntervalSince(lastFigmaQuery) < figmaThrottleInterval,
           let cached = cachedFigmaDetails {
            return cached
        }
        lastFigmaQuery = now

        // CGWindowList often returns just "Figma" for Electron apps.
        // Fall back to AXUIElement for the real window title.
        var effectiveTitle = windowTitle
        let cgCleaned = windowTitle
            .replacingOccurrences(of: " – Figma", with: "")
            .replacingOccurrences(of: " - Figma", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cgCleaned.isEmpty || cgCleaned == "Figma" {
            if let axTitle = getFigmaFrontWindowTitle() {
                effectiveTitle = axTitle
            } else {
                let details = AppDetails(windowTitleOverride: "Home", url: nil, extraInfo: nil)
                cachedFigmaDetails = details
                return details
            }
        }

        let cleaned = effectiveTitle
            .replacingOccurrences(of: " – Figma", with: "")
            .replacingOccurrences(of: " - Figma", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty || cleaned == "Figma" {
            let details = AppDetails(windowTitleOverride: "Home", url: nil, extraInfo: nil)
            cachedFigmaDetails = details
            return details
        }

        // Parse Figma window title format: "Page – FileName" or just "FileName"
        var fileName = cleaned
        var pageName: String? = nil

        if let dashRange = cleaned.range(of: " – ") {
            pageName = String(cleaned[cleaned.startIndex..<dashRange.lowerBound])
            fileName = String(cleaned[dashRange.upperBound...])
        }

        // Get all window names to count open files
        let allWindows = getFigmaAllWindowNames()
        let fileCount = allWindows.count

        var extraParts: [String] = []
        if fileCount > 1 {
            extraParts.append("\(fileCount) files open")
        }
        if let page = pageName {
            extraParts.append("Page: \(page)")
        }

        let extra = extraParts.isEmpty ? "File" : extraParts.joined(separator: " · ")

        let details = AppDetails(
            windowTitleOverride: fileName,
            url: nil,
            extraInfo: extra
        )
        cachedFigmaDetails = details
        return details
    }

    private func getFigmaFrontWindowTitle() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.figma.Desktop"
        }) else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Try focused window first
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(focusedRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty, title != "Figma" {
                return title
            }
        }

        // Fallback: first window with a meaningful title
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty, title != "Figma" {
                return title
            }
        }
        return nil
    }

    private func getFigmaAllWindowNames() -> [String] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.figma.Desktop"
        }) else { return [] }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return [] }

        var names: [String] = []
        for window in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty, title != "Figma" {
                names.append(title)
            }
        }
        return names
    }

    // MARK: - Spotify

    private func extractSpotifyDetails() -> AppDetails {
        let now = Date()
        if now.timeIntervalSince(lastMusicQuery) < musicThrottleInterval,
           let cached = cachedMusicDetails {
            return cached
        }
        lastMusicQuery = now

        let script = """
        tell application "Spotify"
            if player state is playing then
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                return trackName & "|||" & artistName & "|||" & albumName
            else
                return "paused"
            end if
        end tell
        """

        guard let result = runAppleScript(script), result != "paused" else {
            let details = AppDetails(windowTitleOverride: nil, url: nil, extraInfo: "Paused")
            cachedMusicDetails = details
            return details
        }

        let parts = result.components(separatedBy: "|||")
        let track = parts.first ?? ""
        let artist = parts.count > 1 ? parts[1] : ""
        let nowPlaying = "\(track) – \(artist)"

        let details = AppDetails(
            windowTitleOverride: nowPlaying,
            url: nil,
            extraInfo: "Now Playing"
        )
        cachedMusicDetails = details
        return details
    }

    // MARK: - Apple Music

    private func extractAppleMusicDetails() -> AppDetails {
        let now = Date()
        if now.timeIntervalSince(lastMusicQuery) < musicThrottleInterval,
           let cached = cachedMusicDetails {
            return cached
        }
        lastMusicQuery = now

        let script = """
        tell application "Music"
            if player state is playing then
                set trackName to name of current track
                set artistName to artist of current track
                return trackName & "|||" & artistName
            else
                return "paused"
            end if
        end tell
        """

        guard let result = runAppleScript(script), result != "paused" else {
            let details = AppDetails(windowTitleOverride: nil, url: nil, extraInfo: "Paused")
            cachedMusicDetails = details
            return details
        }

        let parts = result.components(separatedBy: "|||")
        let track = parts.first ?? ""
        let artist = parts.count > 1 ? parts[1] : ""
        let nowPlaying = "\(track) – \(artist)"

        let details = AppDetails(
            windowTitleOverride: nowPlaying,
            url: nil,
            extraInfo: "Now Playing"
        )
        cachedMusicDetails = details
        return details
    }

    // MARK: - Chromium Browsers (YouTube detection)

    private func extractChromiumDetails(bundleId: String, windowTitle: String) -> AppDetails {
        // YouTube: "Video Title - YouTube - Google Chrome"
        let isYouTube = windowTitle.contains("- YouTube")

        if isYouTube {
            let title = windowTitle
                .replacingOccurrences(of: " - YouTube - Google Chrome", with: "")
                .replacingOccurrences(of: " - YouTube - Brave", with: "")
                .replacingOccurrences(of: " - YouTube - Microsoft Edge", with: "")
                .replacingOccurrences(of: " - YouTube - Mozilla Firefox", with: "")
                .replacingOccurrences(of: " - YouTube - Arc", with: "")
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return AppDetails(
                windowTitleOverride: title,
                url: "youtube.com",
                extraInfo: "Video",
                appNameOverride: "YouTube",
                bundleIdOverride: "virtual.youtube"
            )
        }

        // Twitter/X: "... / X"
        if windowTitle.hasSuffix("/ X") || windowTitle.contains("/ X -") {
            let title = windowTitle
                .replacingOccurrences(of: " - Google Chrome", with: "")
                .replacingOccurrences(of: " - Brave", with: "")
                .replacingOccurrences(of: " - Microsoft Edge", with: "")
                .replacingOccurrences(of: " - Mozilla Firefox", with: "")
                .replacingOccurrences(of: " - Arc", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return AppDetails(
                windowTitleOverride: title,
                url: "x.com",
                extraInfo: nil,
                appNameOverride: "X (Twitter)",
                bundleIdOverride: "virtual.twitter"
            )
        }

        return AppDetails()
    }

    // MARK: - Site Detection (virtual apps from browser URLs)

    private struct SiteOverride {
        let appName: String
        let bundleId: String
        let title: String?
        let tag: String?
    }

    private func detectSiteOverride(url: String?, windowTitle: String?) -> SiteOverride? {
        guard let url = url?.lowercased() else { return nil }

        if url.contains("youtube.com") {
            let cleanTitle = windowTitle?
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SiteOverride(appName: "YouTube", bundleId: "virtual.youtube", title: cleanTitle, tag: "Video")
        }

        if url.contains("twitter.com") || url.contains("x.com") {
            return SiteOverride(appName: "X (Twitter)", bundleId: "virtual.twitter", title: windowTitle, tag: nil)
        }

        if url.contains("chatgpt.com") || url.contains("chat.openai.com") {
            return SiteOverride(appName: "ChatGPT", bundleId: "virtual.chatgpt", title: windowTitle, tag: nil)
        }

        if url.contains("claude.ai") {
            return SiteOverride(appName: "Claude", bundleId: "virtual.claude", title: windowTitle, tag: nil)
        }

        if url.contains("github.com") {
            return SiteOverride(appName: "GitHub", bundleId: "virtual.github", title: windowTitle, tag: nil)
        }

        if url.contains("notion.so") || url.contains("notion.site") {
            return SiteOverride(appName: "Notion", bundleId: "virtual.notion", title: windowTitle, tag: nil)
        }

        if url.contains("linear.app") {
            return SiteOverride(appName: "Linear", bundleId: "virtual.linear", title: windowTitle, tag: nil)
        }

        return nil
    }

    // MARK: - AppleScript Runner

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
}
