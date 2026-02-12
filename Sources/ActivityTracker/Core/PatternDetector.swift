import Foundation

// MARK: - Detection Result Types

struct SuggestedRule {
    let ruleType: RuleType
    let pattern: String
    let isRegex: Bool
}

struct DetectedProject {
    let suggestedName: String       // "Web+Topluluk" (capitalized)
    let fullToken: String           // "saasbridge web+topluluk" (full lowercase pattern)
    let activityCount: Int
    let apps: Set<String>
    var suggestedRules: [SuggestedRule]
}

struct DetectedBrand {
    let suggestedName: String       // "SaaSBridge" (capitalized)
    let rootToken: String           // "saasbridge" (lowercase, for grouping)
    var projects: [DetectedProject]
    let totalActivities: Int
    let apps: Set<String>
}

// MARK: - Pattern Detector

final class PatternDetector {
    private let store: ActivityStore

    init(store: ActivityStore) {
        self.store = store
    }

    /// Main detection method — analyzes unassigned activities and returns detected brand/project hierarchy.
    func detect() -> [DetectedBrand] {
        guard let raw = try? store.queryUnassignedRaw(), !raw.isEmpty else { return [] }

        let existingRules = (try? store.loadAllProjectRules()) ?? []
        let existingPatterns = Set(existingRules.map { $0.pattern.lowercased() })

        // Step 1: Extract tokens from all unassigned activities
        var tokenInfos: [String: TokenInfo] = [:]

        for act in raw {
            // Window title prefix: "project name — rest of title"
            extractWindowTitlePrefix(act: act, into: &tokenInfos)

            // URL domain
            extractURLDomain(act: act, into: &tokenInfos)

            // Terminal folder from extra_info
            extractTerminalFolder(act: act, into: &tokenInfos)

            // Figma file name
            extractFigmaFile(act: act, into: &tokenInfos)
        }

        // Step 2: Filter low-count and already-covered tokens
        let minCount = 2
        let filtered = tokenInfos.filter { $0.value.count >= minCount }

        // Step 3: Group by first word → brand hierarchy
        var brandGroups: [String: [String: TokenInfo]] = [:] // rootToken → [fullToken → info]

        for (token, info) in filtered {
            let words = token.split(separator: " ", maxSplits: 1)
            let root = String(words[0])

            if brandGroups[root] == nil {
                brandGroups[root] = [:]
            }
            brandGroups[root]![token] = info
        }

        // Step 4: Build DetectedBrand array
        var brands: [DetectedBrand] = []

        for (root, members) in brandGroups {
            // Calculate total activities and apps across all members
            let totalActivities = members.values.reduce(0) { $0 + $1.count }
            let allApps = members.values.reduce(into: Set<String>()) { $0.formUnion($1.apps) }

            var projects: [DetectedProject] = []

            for (fullToken, info) in members {
                // Determine project name: if fullToken == root, it's the main project
                let projectName: String
                if fullToken == root {
                    projectName = smartCapitalize(root)
                } else {
                    // Sub-project: extract the part after root
                    let suffix = String(fullToken.dropFirst(root.count)).trimmingCharacters(in: .whitespaces)
                    projectName = suffix.isEmpty ? smartCapitalize(root) : smartCapitalize(suffix)
                }

                // Generate rules for this project
                var rules: [SuggestedRule] = []

                // Window title rule (if we found window title tokens)
                if info.sources.contains(.windowTitle) && !existingPatterns.contains(fullToken) {
                    rules.append(SuggestedRule(
                        ruleType: .windowTitle,
                        pattern: "^\\Q\(fullToken)\\E",
                        isRegex: true
                    ))
                }

                // URL domain rules
                for domain in info.domains where !existingPatterns.contains(domain) {
                    rules.append(SuggestedRule(
                        ruleType: .urlDomain,
                        pattern: domain,
                        isRegex: false
                    ))
                }

                // Terminal folder rules
                for folder in info.folders where !existingPatterns.contains(folder) {
                    rules.append(SuggestedRule(
                        ruleType: .terminalFolder,
                        pattern: folder,
                        isRegex: false
                    ))
                }

                // Figma file rules
                for figma in info.figmaFiles where !existingPatterns.contains(figma) {
                    rules.append(SuggestedRule(
                        ruleType: .figmaFile,
                        pattern: figma,
                        isRegex: false
                    ))
                }

                guard !rules.isEmpty else { continue }

                projects.append(DetectedProject(
                    suggestedName: projectName,
                    fullToken: fullToken,
                    activityCount: info.count,
                    apps: info.apps,
                    suggestedRules: rules
                ))
            }

            guard !projects.isEmpty else { continue }

            projects.sort { $0.activityCount > $1.activityCount }

            let brandName = smartCapitalize(root)

            brands.append(DetectedBrand(
                suggestedName: brandName,
                rootToken: root,
                projects: projects,
                totalActivities: totalActivities,
                apps: allApps
            ))
        }

        // Sort by total activities descending
        brands.sort { $0.totalActivities > $1.totalActivities }

        return brands
    }

    // MARK: - Token Extraction

    private enum TokenSource {
        case windowTitle
        case urlDomain
        case terminalFolder
        case figmaFile
    }

    private struct TokenInfo {
        var count: Int = 0
        var apps: Set<String> = []
        var sources: Set<TokenSource> = []
        var domains: Set<String> = []
        var folders: Set<String> = []
        var figmaFiles: Set<String> = []
    }

    private func extractWindowTitlePrefix(
        act: (id: Int64, appName: String, bundleId: String, windowTitle: String, url: String?, extraInfo: String?),
        into tokenInfos: inout [String: TokenInfo]
    ) {
        let title = act.windowTitle
        guard let dashRange = title.range(of: " — ") else { return }

        let prefix = String(title[title.startIndex..<dashRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard prefix.count >= 3, prefix != "unknown", prefix != "home" else { return }

        var info = tokenInfos[prefix] ?? TokenInfo()
        info.count += 1
        info.apps.insert(act.appName)
        info.sources.insert(.windowTitle)
        tokenInfos[prefix] = info
    }

    private func extractURLDomain(
        act: (id: Int64, appName: String, bundleId: String, windowTitle: String, url: String?, extraInfo: String?),
        into tokenInfos: inout [String: TokenInfo]
    ) {
        guard let urlStr = act.url, !urlStr.isEmpty,
              let comps = URLComponents(string: urlStr),
              let host = comps.host else { return }

        let domain = host
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .lowercased()

        // Skip common non-project domains
        let skipDomains = ["google.com", "github.com", "stackoverflow.com", "apple.com",
                           "youtube.com", "twitter.com", "x.com", "reddit.com",
                           "localhost", "127.0.0.1", "chatgpt.com", "claude.ai"]
        guard !domain.isEmpty, !skipDomains.contains(domain) else { return }

        // Use domain name (without TLD) as grouping token
        let parts = domain.split(separator: ".")
        let token: String
        if parts.count >= 2 {
            token = String(parts[parts.count - 2]) // e.g. "saasbridge" from "saasbridge.io"
        } else {
            token = domain
        }

        guard token.count >= 3 else { return }

        var info = tokenInfos[token] ?? TokenInfo()
        info.count += 1
        info.apps.insert(act.appName)
        info.sources.insert(.urlDomain)
        info.domains.insert(domain)
        tokenInfos[token] = info
    }

    private func extractTerminalFolder(
        act: (id: Int64, appName: String, bundleId: String, windowTitle: String, url: String?, extraInfo: String?),
        into tokenInfos: inout [String: TokenInfo]
    ) {
        guard let extra = act.extraInfo, !extra.isEmpty else { return }

        // extra_info typically contains folder path like "~/projects/saasbridge-web"
        let folderName = (extra as NSString).lastPathComponent
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        guard folderName.count >= 3, folderName != "~" else { return }

        // Use the normalized folder name as token
        var info = tokenInfos[folderName] ?? TokenInfo()
        info.count += 1
        info.apps.insert(act.appName)
        info.sources.insert(.terminalFolder)
        info.folders.insert(extra) // Store original path for rule creation
        tokenInfos[folderName] = info
    }

    private func extractFigmaFile(
        act: (id: Int64, appName: String, bundleId: String, windowTitle: String, url: String?, extraInfo: String?),
        into tokenInfos: inout [String: TokenInfo]
    ) {
        guard act.bundleId == "com.figma.Desktop" else { return }

        let title = act.windowTitle
        guard !title.isEmpty, title != "Home", title != "Figma" else { return }

        // Figma window title is typically the file name
        let normalized = title.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count >= 3 else { return }

        // Extract first word as potential brand grouping key
        let words = normalized.split(separator: " ", maxSplits: 1)
        let token = String(words[0])

        guard token.count >= 3 else { return }

        var info = tokenInfos[token] ?? TokenInfo()
        info.count += 1
        info.apps.insert(act.appName)
        info.sources.insert(.figmaFile)
        info.figmaFiles.insert(title) // Store original title for rule creation
        tokenInfos[token] = info
    }

    // MARK: - Smart Capitalize

    /// Capitalizes each word: "saasbridge web+topluluk" → "Saasbridge Web+Topluluk"
    func smartCapitalize(_ input: String) -> String {
        input.split(separator: " ").map { word in
            let w = String(word)
            guard let first = w.first else { return w }
            return String(first).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }
}
