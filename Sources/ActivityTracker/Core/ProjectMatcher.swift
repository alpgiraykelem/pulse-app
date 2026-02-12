import Foundation

final class ProjectMatcher {
    private let store: ActivityStore
    private var rules: [ProjectRule] = []
    private var lastReload: Date = .distantPast
    private let reloadInterval: TimeInterval = 60

    init(store: ActivityStore) {
        self.store = store
        reloadRules()
    }

    func reloadRules() {
        rules = (try? store.loadAllProjectRules()) ?? []
        lastReload = Date()
    }

    private func reloadIfNeeded() {
        if Date().timeIntervalSince(lastReload) >= reloadInterval {
            reloadRules()
        }
    }

    /// Matches a heartbeat against all rules, returns the project_id of the first matching rule (highest priority first).
    func match(heartbeat: Heartbeat) -> Int64? {
        reloadIfNeeded()

        for rule in rules {
            if matches(rule: rule, heartbeat: heartbeat) {
                return rule.projectId
            }
        }
        return nil
    }

    /// Matches raw activity data (for retroactive assignment).
    func match(appName: String, bundleId: String, windowTitle: String, url: String?, extraInfo: String?) -> Int64? {
        reloadIfNeeded()

        let heartbeat = Heartbeat(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: url,
            extraInfo: extraInfo
        )

        for rule in rules {
            if matches(rule: rule, heartbeat: heartbeat) {
                return rule.projectId
            }
        }
        return nil
    }

    private func matches(rule: ProjectRule, heartbeat: Heartbeat) -> Bool {
        switch rule.ruleType {
        case .terminalFolder:
            guard let extra = heartbeat.extraInfo else { return false }
            return matchPattern(rule.pattern, against: extra, isRegex: rule.isRegex)

        case .urlDomain:
            guard let url = heartbeat.url else { return false }
            return matchDomain(rule.pattern, url: url)

        case .urlPath:
            guard let url = heartbeat.url else { return false }
            return matchPattern(rule.pattern, against: url, isRegex: rule.isRegex)

        case .pageTitle:
            return matchPattern(rule.pattern, against: heartbeat.windowTitle, isRegex: rule.isRegex)

        case .figmaFile:
            return matchPattern(rule.pattern, against: heartbeat.windowTitle, isRegex: rule.isRegex)

        case .bundleId:
            return matchPattern(rule.pattern, against: heartbeat.bundleId, isRegex: rule.isRegex)

        case .windowTitle:
            return matchPattern(rule.pattern, against: heartbeat.windowTitle, isRegex: rule.isRegex)
        }
    }

    private func matchPattern(_ pattern: String, against text: String, isRegex: Bool) -> Bool {
        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        } else {
            return text.localizedCaseInsensitiveContains(pattern)
        }
    }

    private func matchDomain(_ pattern: String, url: String) -> Bool {
        // Extract host from URL
        if let components = URLComponents(string: url), let host = components.host {
            return host.localizedCaseInsensitiveContains(pattern)
        }
        // Fallback: simple string check
        return url.localizedCaseInsensitiveContains(pattern)
    }

    // MARK: - Retroactive Assignment

    /// Runs matcher on all unassigned activities for a given date (or all dates if nil).
    /// Returns the number of newly assigned activities.
    @discardableResult
    func autoAssignUnclassified(date: String? = nil) -> Int {
        reloadRules()
        guard !rules.isEmpty else { return 0 }

        guard let rows = try? store.queryUnassignedRaw(date: date) else { return 0 }

        var count = 0
        for row in rows {
            if let projectId = match(
                appName: row.appName,
                bundleId: row.bundleId,
                windowTitle: row.windowTitle,
                url: row.url,
                extraInfo: row.extraInfo
            ) {
                try? store.updateProjectAssignment(activityId: row.id, projectId: projectId, source: .autoRule)
                count += 1
            }
        }
        return count
    }
}
