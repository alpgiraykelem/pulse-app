import Foundation
import SQLite

final class ActivityStore {
    private let db: Connection

    // Table definition - activities
    private let activities = Table("activities")
    private let colId = SQLite.Expression<Int64>("id")
    private let colTimestamp = SQLite.Expression<Double>("timestamp")
    private let colAppName = SQLite.Expression<String>("app_name")
    private let colBundleId = SQLite.Expression<String>("bundle_id")
    private let colWindowTitle = SQLite.Expression<String>("window_title")
    private let colUrl = SQLite.Expression<String?>("url")
    private let colExtraInfo = SQLite.Expression<String?>("extra_info")
    private let colDurationSeconds = SQLite.Expression<Int>("duration_seconds")
    private let colDate = SQLite.Expression<String>("date")
    private let colProjectId = SQLite.Expression<Int64?>("project_id")
    private let colProjectSource = SQLite.Expression<String?>("project_source")

    // Table definition - brands
    private let brands = Table("brands")
    private let colBrandId = SQLite.Expression<Int64>("id")
    private let colBrandName = SQLite.Expression<String>("name")
    private let colBrandColor = SQLite.Expression<String>("color")
    private let colBrandSortOrder = SQLite.Expression<Int>("sort_order")
    private let colBrandCreatedAt = SQLite.Expression<Double>("created_at")

    // Table definition - projects
    private let projects = Table("projects")
    private let colProjId = SQLite.Expression<Int64>("id")
    private let colProjBrandId = SQLite.Expression<Int64>("brand_id")
    private let colProjName = SQLite.Expression<String>("name")
    private let colProjColor = SQLite.Expression<String>("color")
    private let colProjSortOrder = SQLite.Expression<Int>("sort_order")
    private let colProjCreatedAt = SQLite.Expression<Double>("created_at")

    // Table definition - project_rules
    private let projectRules = Table("project_rules")
    private let colRuleId = SQLite.Expression<Int64>("id")
    private let colRuleProjectId = SQLite.Expression<Int64>("project_id")
    private let colRuleType = SQLite.Expression<String>("rule_type")
    private let colRulePattern = SQLite.Expression<String>("pattern")
    private let colRuleIsRegex = SQLite.Expression<Bool>("is_regex")
    private let colRulePriority = SQLite.Expression<Int>("priority")
    private let colRuleCreatedAt = SQLite.Expression<Double>("created_at")

    init(dbPath: String? = nil) throws {
        let path: String
        if let dbPath = dbPath {
            path = dbPath
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("ActivityTracker")

            try FileManager.default.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true
            )
            path = appSupport.appendingPathComponent("activity.db").path
        }

        db = try Connection(path)
        try db.execute("PRAGMA journal_mode = WAL")
        try createTable()
        try migrateSchema()
    }

    private func createTable() throws {
        try db.run(activities.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: .autoincrement)
            t.column(colTimestamp)
            t.column(colAppName)
            t.column(colBundleId)
            t.column(colWindowTitle)
            t.column(colUrl)
            t.column(colExtraInfo)
            t.column(colDurationSeconds, defaultValue: 0)
            t.column(colDate)
        })

        try db.run(activities.createIndex(colDate, ifNotExists: true))
        try db.run(activities.createIndex(colAppName, ifNotExists: true))
        try db.run(activities.createIndex(colBundleId, ifNotExists: true))
    }

    private func migrateSchema() throws {
        // brands table
        try db.run(brands.create(ifNotExists: true) { t in
            t.column(colBrandId, primaryKey: .autoincrement)
            t.column(colBrandName, unique: true)
            t.column(colBrandColor, defaultValue: "#6366f1")
            t.column(colBrandSortOrder, defaultValue: 0)
            t.column(colBrandCreatedAt, defaultValue: Date().timeIntervalSince1970)
        })

        // projects table
        try db.run(projects.create(ifNotExists: true) { t in
            t.column(colProjId, primaryKey: .autoincrement)
            t.column(colProjBrandId, references: brands, colBrandId)
            t.column(colProjName)
            t.column(colProjColor, defaultValue: "#6366f1")
            t.column(colProjSortOrder, defaultValue: 0)
            t.column(colProjCreatedAt, defaultValue: Date().timeIntervalSince1970)
            t.unique(colProjBrandId, colProjName)
        })

        // project_rules table
        try db.run(projectRules.create(ifNotExists: true) { t in
            t.column(colRuleId, primaryKey: .autoincrement)
            t.column(colRuleProjectId, references: projects, colProjId)
            t.column(colRuleType)
            t.column(colRulePattern)
            t.column(colRuleIsRegex, defaultValue: false)
            t.column(colRulePriority, defaultValue: 0)
            t.column(colRuleCreatedAt, defaultValue: Date().timeIntervalSince1970)
        })

        // Add project_id and project_source columns to activities (if not exist)
        let tableInfo = try db.prepare("PRAGMA table_info(activities)")
        var hasProjectId = false
        var hasProjectSource = false
        for col in tableInfo {
            if let name = col[1] as? String {
                if name == "project_id" { hasProjectId = true }
                if name == "project_source" { hasProjectSource = true }
            }
        }

        if !hasProjectId {
            try db.execute("ALTER TABLE activities ADD COLUMN project_id INTEGER REFERENCES projects(id)")
        }
        if !hasProjectSource {
            try db.execute("ALTER TABLE activities ADD COLUMN project_source TEXT")
        }

        // Index on project_id
        try db.run(activities.createIndex(colProjectId, ifNotExists: true))
    }

    // MARK: - Insert & Update

    @discardableResult
    func insert(_ record: ActivityRecord, projectId: Int64? = nil, projectSource: ProjectSource? = nil) throws -> Int64 {
        if let pid = projectId, let source = projectSource {
            let insert = activities.insert(
                colTimestamp <- record.timestamp.timeIntervalSince1970,
                colAppName <- record.appName,
                colBundleId <- record.bundleId,
                colWindowTitle <- record.windowTitle,
                colUrl <- record.url,
                colExtraInfo <- record.extraInfo,
                colDurationSeconds <- record.durationSeconds,
                colDate <- record.date,
                colProjectId <- pid,
                colProjectSource <- source.rawValue
            )
            return try db.run(insert)
        } else {
            let insert = activities.insert(
                colTimestamp <- record.timestamp.timeIntervalSince1970,
                colAppName <- record.appName,
                colBundleId <- record.bundleId,
                colWindowTitle <- record.windowTitle,
                colUrl <- record.url,
                colExtraInfo <- record.extraInfo,
                colDurationSeconds <- record.durationSeconds,
                colDate <- record.date
            )
            return try db.run(insert)
        }
    }

    func updateDuration(id: Int64, seconds: Int) throws {
        let row = activities.filter(colId == id)
        try db.run(row.update(colDurationSeconds <- seconds))
    }

    func updateWindowTitle(id: Int64, title: String, url: String?, extraInfo: String?) throws {
        let row = activities.filter(colId == id)
        try db.run(row.update(
            colWindowTitle <- title,
            colUrl <- url,
            colExtraInfo <- extraInfo
        ))
    }

    // MARK: - Brand CRUD

    @discardableResult
    func insertBrand(name: String, color: String = "#6366f1") throws -> Int64 {
        let insert = brands.insert(
            colBrandName <- name,
            colBrandColor <- color,
            colBrandSortOrder <- (try allBrands().count),
            colBrandCreatedAt <- Date().timeIntervalSince1970
        )
        return try db.run(insert)
    }

    func allBrands() throws -> [Brand] {
        try db.prepare(brands.order(colBrandSortOrder.asc, colBrandId.asc)).map { row in
            Brand(
                id: row[colBrandId],
                name: row[colBrandName],
                color: row[colBrandColor],
                sortOrder: row[colBrandSortOrder]
            )
        }
    }

    func updateBrand(id: Int64, name: String?, color: String?) throws {
        let row = brands.filter(colBrandId == id)
        if let name = name, let color = color {
            try db.run(row.update(colBrandName <- name, colBrandColor <- color))
        } else if let name = name {
            try db.run(row.update(colBrandName <- name))
        } else if let color = color {
            try db.run(row.update(colBrandColor <- color))
        }
    }

    func deleteBrand(id: Int64) throws {
        // Find all projects under this brand
        let brandProjects = try db.prepare(projects.filter(colProjBrandId == id)).map { $0[colProjId] }
        // Delete rules for each project
        for projId in brandProjects {
            try db.run(projectRules.filter(colRuleProjectId == projId).delete())
        }
        // Unassign activities from these projects
        if !brandProjects.isEmpty {
            let affected = activities.filter(brandProjects.contains(colProjectId))
            try db.run(affected.update(colProjectId <- nil as Int64?, colProjectSource <- nil as String?))
        }
        // Delete projects
        try db.run(projects.filter(colProjBrandId == id).delete())
        // Delete brand
        try db.run(brands.filter(colBrandId == id).delete())
    }

    // MARK: - Project CRUD

    @discardableResult
    func insertProject(brandId: Int64, name: String, color: String = "#6366f1") throws -> Int64 {
        let insert = projects.insert(
            colProjBrandId <- brandId,
            colProjName <- name,
            colProjColor <- color,
            colProjSortOrder <- 0,
            colProjCreatedAt <- Date().timeIntervalSince1970
        )
        return try db.run(insert)
    }

    func allProjects() throws -> [(project: Project, brandName: String)] {
        let query = projects
            .join(brands, on: colProjBrandId == brands[colBrandId])
            .order(projects[colProjSortOrder].asc, projects[colProjId].asc)

        return try db.prepare(query).map { row in
            let project = Project(
                id: row[projects[colProjId]],
                brandId: row[colProjBrandId],
                name: row[projects[colProjName]],
                color: row[projects[colProjColor]],
                sortOrder: row[projects[colProjSortOrder]]
            )
            return (project: project, brandName: row[brands[colBrandName]])
        }
    }

    func updateProject(id: Int64, name: String?, color: String?, brandId: Int64?) throws {
        let row = projects.filter(colProjId == id)
        var setters: [SQLite.Setter] = []
        if let name = name { setters.append(colProjName <- name) }
        if let color = color { setters.append(colProjColor <- color) }
        if let brandId = brandId { setters.append(colProjBrandId <- brandId) }
        if !setters.isEmpty {
            try db.run(row.update(setters))
        }
    }

    func deleteProject(id: Int64) throws {
        // Delete rules
        try db.run(projectRules.filter(colRuleProjectId == id).delete())
        // Unassign activities
        let affected = activities.filter(colProjectId == id)
        try db.run(affected.update(colProjectId <- nil as Int64?, colProjectSource <- nil as String?))
        // Delete project
        try db.run(projects.filter(colProjId == id).delete())
    }

    // MARK: - Rule CRUD

    @discardableResult
    func insertRule(projectId: Int64, ruleType: RuleType, pattern: String, isRegex: Bool = false, priority: Int = 0) throws -> Int64 {
        let insert = projectRules.insert(
            colRuleProjectId <- projectId,
            colRuleType <- ruleType.rawValue,
            colRulePattern <- pattern,
            colRuleIsRegex <- isRegex,
            colRulePriority <- priority,
            colRuleCreatedAt <- Date().timeIntervalSince1970
        )
        return try db.run(insert)
    }

    func loadAllProjectRules() throws -> [ProjectRule] {
        try db.prepare(projectRules.order(colRulePriority.desc, colRuleId.asc)).map { row in
            ProjectRule(
                id: row[colRuleId],
                projectId: row[colRuleProjectId],
                ruleType: RuleType(rawValue: row[colRuleType]) ?? .windowTitle,
                pattern: row[colRulePattern],
                isRegex: row[colRuleIsRegex],
                priority: row[colRulePriority]
            )
        }
    }

    func deleteRule(id: Int64) throws {
        try db.run(projectRules.filter(colRuleId == id).delete())
    }

    // MARK: - Project Assignment

    func updateProjectAssignment(activityId: Int64, projectId: Int64, source: ProjectSource) throws {
        let row = activities.filter(colId == activityId)
        try db.run(row.update(
            colProjectId <- projectId,
            colProjectSource <- source.rawValue
        ))
    }

    func bulkUpdateProjectAssignment(activityIds: [Int64], projectId: Int64, source: ProjectSource) throws {
        let rows = activities.filter(activityIds.contains(colId))
        try db.run(rows.update(
            colProjectId <- projectId,
            colProjectSource <- source.rawValue
        ))
    }

    // MARK: - Project Queries

    func queryDayByProject(date: String) throws -> [BrandSummary] {
        let query = activities
            .filter(colDate == date)
            .filter(colProjectId != nil)

        // Gather data grouped by project
        struct ProjectAccum {
            var projectId: Int64
            var totalSeconds: Int = 0
            var appBreakdown: [String: Int] = [:]
        }

        var projectMap: [Int64: ProjectAccum] = [:]

        for row in try db.prepare(query) {
            guard let pid = row[colProjectId] else { continue }
            let duration = row[colDurationSeconds]
            let appName = row[colAppName]

            var accum = projectMap[pid] ?? ProjectAccum(projectId: pid)
            accum.totalSeconds += duration
            accum.appBreakdown[appName, default: 0] += duration
            projectMap[pid] = accum
        }

        // Load all projects with brand info
        let allProjs = try allProjects()
        let allBrandsList = try allBrands()

        // Build brand -> project hierarchy
        var brandProjectMap: [Int64: (brand: Brand, projects: [ProjectSummary])] = [:]

        for brandItem in allBrandsList {
            brandProjectMap[brandItem.id] = (brand: brandItem, projects: [])
        }

        for (proj, brandName) in allProjs {
            guard let accum = projectMap[proj.id] else { continue }
            let appBreakdown = accum.appBreakdown.map { AppBreakdownEntry(appName: $0.key, seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds }

            let summary = ProjectSummary(
                projectId: proj.id,
                projectName: proj.name,
                brandId: proj.brandId,
                brandName: brandName,
                color: proj.color,
                totalSeconds: accum.totalSeconds,
                appBreakdown: appBreakdown
            )

            if brandProjectMap[proj.brandId] != nil {
                brandProjectMap[proj.brandId]!.projects.append(summary)
            } else {
                // Brand might have been deleted, create placeholder
                let placeholderBrand = Brand(id: proj.brandId, name: brandName, color: "#999", sortOrder: 999)
                brandProjectMap[proj.brandId] = (brand: placeholderBrand, projects: [summary])
            }
        }

        return brandProjectMap.values
            .filter { !$0.projects.isEmpty }
            .map { entry in
                BrandSummary(
                    brandId: entry.brand.id,
                    brandName: entry.brand.name,
                    color: entry.brand.color,
                    totalSeconds: entry.projects.reduce(0) { $0 + $1.totalSeconds },
                    projects: entry.projects.sorted { $0.totalSeconds > $1.totalSeconds }
                )
            }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    func queryUnassignedActivities(date: String) throws -> [UnassignedActivity] {
        let query = activities
            .filter(colDate == date)
            .filter(colProjectId == nil)
            .filter(colDurationSeconds >= 10) // skip very short entries
            .order(colDurationSeconds.desc)

        return try db.prepare(query).map { row in
            UnassignedActivity(
                id: row[colId],
                appName: row[colAppName],
                windowTitle: row[colWindowTitle],
                url: row[colUrl],
                extraInfo: row[colExtraInfo],
                durationSeconds: row[colDurationSeconds]
            )
        }
    }

    /// Returns raw activity rows for unassigned activities (for ProjectMatcher re-processing)
    func queryUnassignedRaw(date: String? = nil) throws -> [(id: Int64, appName: String, bundleId: String, windowTitle: String, url: String?, extraInfo: String?)] {
        var query = activities.filter(colProjectId == nil)
        if let date = date {
            query = query.filter(colDate == date)
        }

        return try db.prepare(query).map { row in
            (
                id: row[colId],
                appName: row[colAppName],
                bundleId: row[colBundleId],
                windowTitle: row[colWindowTitle],
                url: row[colUrl],
                extraInfo: row[colExtraInfo]
            )
        }
    }

    // MARK: - Queries

    func queryDay(date: String) throws -> DaySummary {
        let query = activities.filter(colDate == date)

        struct WindowKey: Hashable {
            let title: String
            let extraInfo: String?
        }

        var appMap: [String: (bundleId: String, totalSeconds: Int, windows: [WindowKey: (url: String?, seconds: Int, ids: [Int64])])] = [:]
        var minTimestamp: Double = .greatestFiniteMagnitude
        var maxTimestamp: Double = 0

        for row in try db.prepare(query) {
            let actId = row[colId]
            let appName = row[colAppName]
            let bundleId = row[colBundleId]
            let windowTitle = row[colWindowTitle]
            let url = row[colUrl]
            let extraInfo = row[colExtraInfo]
            let duration = row[colDurationSeconds]
            let ts = row[colTimestamp]

            if ts < minTimestamp { minTimestamp = ts }
            let endTs = ts + Double(duration)
            if endTs > maxTimestamp { maxTimestamp = endTs }

            let wk = WindowKey(title: windowTitle, extraInfo: extraInfo)

            var app = appMap[appName] ?? (bundleId: bundleId, totalSeconds: 0, windows: [:])
            app.totalSeconds += duration

            var window = app.windows[wk] ?? (url: url, seconds: 0, ids: [])
            window.seconds += duration
            window.url = window.url ?? url
            window.ids.append(actId)
            app.windows[wk] = window

            appMap[appName] = app
        }

        let apps = appMap.map { (appName, data) -> ActivitySummary in
            let windows = data.windows.map { (key, wData) -> WindowDetail in
                WindowDetail(windowTitle: key.title, url: wData.url, extraInfo: key.extraInfo, totalSeconds: wData.seconds, activityIds: wData.ids)
            }.sorted { $0.totalSeconds > $1.totalSeconds }

            return ActivitySummary(
                appName: appName,
                bundleId: data.bundleId,
                totalSeconds: data.totalSeconds,
                windowDetails: windows
            )
        }.sorted { $0.totalSeconds > $1.totalSeconds }

        let totalSeconds = apps.reduce(0) { $0 + $1.totalSeconds }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var wallClockSeconds = 0
        var firstActivity: String?
        var lastActivity: String?

        if minTimestamp < .greatestFiniteMagnitude && maxTimestamp > 0 {
            wallClockSeconds = Int(maxTimestamp - minTimestamp)
            firstActivity = timeFormatter.string(from: Date(timeIntervalSince1970: minTimestamp))
            lastActivity = timeFormatter.string(from: Date(timeIntervalSince1970: maxTimestamp))
        }

        return DaySummary(
            date: date,
            totalSeconds: totalSeconds,
            apps: apps,
            wallClockSeconds: wallClockSeconds,
            activeTrackingSeconds: totalSeconds,
            firstActivity: firstActivity,
            lastActivity: lastActivity
        )
    }

    func queryWeek() throws -> [DaySummary] {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var summaries: [DaySummary] = []
        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = formatter.string(from: date)
            let summary = try queryDay(date: dateStr)
            if summary.totalSeconds > 0 {
                summaries.append(summary)
            }
        }
        return summaries
    }

    func queryApp(appName: String) throws -> AppDetailReport {
        let query = activities.filter(colAppName.like("%\(appName)%"))
        var totalSeconds = 0
        var dayMap: [String: Int] = [:]
        var windowMap: [String: (url: String?, extraInfo: String?, seconds: Int)] = [:]

        for row in try db.prepare(query) {
            let duration = row[colDurationSeconds]
            let date = row[colDate]
            let windowTitle = row[colWindowTitle]
            let url = row[colUrl]
            let extraInfo = row[colExtraInfo]

            totalSeconds += duration
            dayMap[date, default: 0] += duration

            var window = windowMap[windowTitle] ?? (url: url, extraInfo: extraInfo, seconds: 0)
            window.seconds += duration
            window.url = window.url ?? url
            window.extraInfo = window.extraInfo ?? extraInfo
            windowMap[windowTitle] = window
        }

        let days = dayMap.map { DayBreakdown(date: $0.key, totalSeconds: $0.value) }
            .sorted { $0.date > $1.date }

        let topWindows = windowMap.map {
            WindowDetail(windowTitle: $0.key, url: $0.value.url, extraInfo: $0.value.extraInfo, totalSeconds: $0.value.seconds)
        }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(20)

        return AppDetailReport(
            appName: appName,
            totalSeconds: totalSeconds,
            days: days,
            topWindows: Array(topWindows)
        )
    }

    func queryTodayTotalSeconds() throws -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let summary = try queryDay(date: today)
        return summary.totalSeconds
    }

    func queryTodayTopApps(limit: Int = 5) throws -> [(app: String, seconds: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let summary = try queryDay(date: today)
        return summary.apps.prefix(limit).map { (app: $0.appName, seconds: $0.totalSeconds) }
    }

    func queryRecentApps(lastMinutes: Int = 60, minSeconds: Int = 60, limit: Int = 7) throws -> [(app: String, seconds: Int, lastSeen: Date)] {
        let cutoff = Date().addingTimeInterval(-Double(lastMinutes * 60)).timeIntervalSince1970
        let query = activities
            .filter(colTimestamp >= cutoff)
            .select(colAppName, colDurationSeconds.sum, colTimestamp.max)
            .group(colAppName)
            .order(colTimestamp.max.desc)

        return try db.prepare(query).compactMap { row in
            guard let total = row[colDurationSeconds.sum], total >= minSeconds,
                  let maxTs = row[colTimestamp.max] else { return nil }
            return (app: row[colAppName], seconds: total, lastSeen: Date(timeIntervalSince1970: maxTs))
        }.prefix(limit).map { $0 }
    }

    func queryRecentDates(limit: Int = 14) throws -> [(date: String, totalSeconds: Int)] {
        let query = activities
            .select(colDate, colDurationSeconds.sum)
            .group(colDate)
            .order(colDate.desc)
            .limit(limit)

        return try db.prepare(query).compactMap { row in
            guard let total = row[colDurationSeconds.sum], total > 0 else { return nil }
            return (date: row[colDate], totalSeconds: total)
        }
    }

    func queryTimeline(date: String) throws -> [TimelineEntry] {
        let query = activities
            .filter(colDate == date)
            .order(colTimestamp.asc)

        return try db.prepare(query).map { row in
            TimelineEntry(
                timestamp: Date(timeIntervalSince1970: row[colTimestamp]),
                appName: row[colAppName],
                windowTitle: row[colWindowTitle],
                url: row[colUrl],
                extraInfo: row[colExtraInfo],
                durationSeconds: row[colDurationSeconds]
            )
        }
    }

    func queryDays(from: String, to: String) throws -> [DaySummary] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let startDate = formatter.date(from: from),
              let endDate = formatter.date(from: to) else { return [] }

        var summaries: [DaySummary] = []
        var current = startDate
        while current <= endDate {
            let dateStr = formatter.string(from: current)
            let summary = try queryDay(date: dateStr)
            if summary.totalSeconds > 0 {
                summaries.append(summary)
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return summaries
    }
}
