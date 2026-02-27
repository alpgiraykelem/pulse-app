import Foundation

enum HTMLReportGenerator {
    private static var reportsDir: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ActivityTracker/reports")

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    static func generate(
        summary: DaySummary,
        timeline: [TimelineEntry],
        brandSummaries: [BrandSummary] = [],
        projectData: ProjectData? = nil
    ) -> URL {
        let fileName = "report-\(summary.date).html"
        let fileURL = reportsDir.appendingPathComponent(fileName)

        // Check for existing AI analysis
        let analysisFile = reportsDir.appendingPathComponent("analysis-\(summary.date).md")
        let analysisText = try? String(contentsOf: analysisFile, encoding: .utf8)

        let html = buildHTML(
            summary: summary,
            timeline: timeline,
            analysis: analysisText,
            brandSummaries: brandSummaries,
            projectData: projectData
        )
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - JSON Export

    struct DayJSON: Codable {
        let date: String
        let totalSeconds: Int
        let wallClockSeconds: Int
        let firstActivity: String?
        let lastActivity: String?
        let timeline: [TimelineEntry]
    }

    @discardableResult
    static func generateJSON(summary: DaySummary, timeline: [TimelineEntry]) -> URL {
        let fileName = "report-\(summary.date).json"
        let fileURL = reportsDir.appendingPathComponent(fileName)

        let dayJSON = DayJSON(
            date: summary.date,
            totalSeconds: summary.totalSeconds,
            wallClockSeconds: summary.wallClockSeconds,
            firstActivity: summary.firstActivity,
            lastActivity: summary.lastActivity,
            timeline: timeline
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(dayJSON) {
            try? data.write(to: fileURL)
        }
        return fileURL
    }

    static func generateExportJSON(days: [DaySummary]) -> URL {
        let sortedDays = days.sorted { $0.date < $1.date }
        let fromDate = sortedDays.first?.date ?? "unknown"
        let toDate = sortedDays.last?.date ?? "unknown"
        let fileName = "export-\(fromDate)-to-\(toDate).json"
        let fileURL = reportsDir.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(sortedDays) {
            try? data.write(to: fileURL)
        }
        return fileURL
    }

    // MARK: - HTML

    private static func buildHTML(
        summary: DaySummary,
        timeline: [TimelineEntry],
        analysis: String? = nil,
        brandSummaries: [BrandSummary] = [],
        projectData: ProjectData? = nil
    ) -> String {
        let dateDisplay = formatDateDisplay(summary.date)
        let totalTime = dur(summary.totalSeconds)

        let colors = [
            "#6366f1", "#f59e0b", "#10b981", "#ef4444", "#8b5cf6",
            "#ec4899", "#14b8a6", "#f97316", "#06b6d4", "#84cc16"
        ]
        var appColorMap: [String: String] = [:]
        for (i, app) in summary.apps.enumerated() {
            appColorMap[app.appName] = colors[i % colors.count]
        }

        let donutSegments = buildDonutSegments(apps: summary.apps, colors: appColorMap)
        let appCards = buildAppCards(summary: summary, colors: appColorMap)
        let timelineHTML = buildTimelineHTML(timeline: timeline, appColors: appColorMap)
        let metricCards = buildMetricCards(summary: summary)
        let analysisHTML = buildAnalysisSection(analysis: analysis)
        let projectsHTML = buildProjectsSection(brandSummaries: brandSummaries, totalSeconds: summary.totalSeconds, projectData: projectData)
        let hasProjects = !brandSummaries.isEmpty || (projectData?.unassigned.isEmpty == false) || projectData != nil
        let sidebar = buildSidebar(summary: summary, colors: appColorMap, hasAnalysis: analysis != nil, hasProjects: hasProjects)
        let rightPanel = buildRightPanel(projectData: projectData)
        let hasRightPanel = !rightPanel.isEmpty

        // Embed JSON data inline so analyzeWithAI works on file:// URLs
        let dayJSON = DayJSON(
            date: summary.date,
            totalSeconds: summary.totalSeconds,
            wallClockSeconds: summary.wallClockSeconds,
            firstActivity: summary.firstActivity,
            lastActivity: summary.lastActivity,
            timeline: timeline
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inlineJSON = (try? encoder.encode(dayJSON)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        // Embed project data
        let projectDataJSON: String
        if let pd = projectData, let data = try? encoder.encode(pd), let str = String(data: data, encoding: .utf8) {
            projectDataJSON = str
        } else {
            projectDataJSON = "{\"brands\":[],\"projects\":[],\"unassigned\":[],\"apiPort\":18492}"
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Activity Report – \(summary.date)</title>
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif;
            background: #f8f9fb;
            color: #1a1a2e;
            min-height: 100vh;
            -webkit-font-smoothing: antialiased;
        }
        .layout { display: grid; grid-template-columns: 200px 1fr; max-width: 1400px; margin: 0 auto; padding: 48px 24px 80px; gap: 32px; }
        .layout.has-right-panel { grid-template-columns: 180px 1fr 320px; }
        .sidebar {
            position: sticky; top: 24px; height: fit-content;
            max-height: calc(100vh - 48px); overflow-y: auto;
            font-size: 13px;
        }
        .sidebar-section { margin-bottom: 20px; }
        .sidebar-heading {
            font-size: 11px; color: #8e8ea0; text-transform: uppercase;
            letter-spacing: 1.5px; font-weight: 600; margin-bottom: 8px; padding: 0 8px;
        }
        .sidebar a {
            display: flex; align-items: center; gap: 8px;
            text-decoration: none; color: #6b6b80; padding: 5px 8px;
            border-radius: 6px; transition: background 0.15s, color 0.15s;
            white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
        }
        .sidebar a:hover { background: #eef0f5; color: #1a1a2e; }
        .sidebar a.active { background: #eef0ff; color: #6366f1; font-weight: 600; }
        .sidebar .nav-dot { width: 8px; height: 8px; border-radius: 3px; flex-shrink: 0; }
        .sidebar .nav-time { font-size: 11px; color: #a0a0b0; margin-left: auto; flex-shrink: 0; }
        .sidebar .nav-divider { height: 1px; background: #e8e8ee; margin: 12px 8px; }

        .main-content { min-width: 0; }

        .right-panel {
            position: sticky; top: 24px; height: fit-content;
            max-height: calc(100vh - 48px); overflow-y: auto;
            font-size: 13px;
        }
        .right-panel-title {
            font-size: 12px; color: #8e8ea0; text-transform: uppercase;
            letter-spacing: 1.5px; font-weight: 600; margin-bottom: 12px;
        }
        .right-panel .unassigned-section { border-radius: 12px; padding: 16px; margin-bottom: 12px; }
        .right-panel .unassigned-row { flex-wrap: wrap; gap: 8px; padding: 8px 10px; }
        .right-panel .unassigned-app { width: auto; font-size: 12px; }
        .right-panel .unassigned-detail { font-size: 11px; flex-basis: 100%; }
        .right-panel .unassigned-dur { font-size: 12px; width: auto; }
        .right-panel .unassigned-select { width: 100%; min-width: 0; font-size: 11px; margin-top: 4px; }
        .right-panel .unassigned-save-btn { font-size: 10px; padding: 3px 8px; }
        .right-panel .unassigned-rule-check { font-size: 10px; }
        .right-panel .suggestion-card { padding: 12px 14px; }
        .right-panel .suggestion-card-name { font-size: 13px; }
        .right-panel .suggestion-card-apps { font-size: 10px; }
        .right-panel .suggestion-rule-tag { font-size: 9px; }
        .right-panel .suggestion-card-actions { flex-wrap: wrap; }
        .right-panel .suggestion-btn-create, .right-panel .suggestion-btn-assign, .right-panel .suggestion-btn-dismiss { font-size: 11px; padding: 4px 10px; }
        .right-panel .suggestions-container { margin-bottom: 16px; }

        .header { margin-bottom: 32px; }
        .header-label { font-size: 12px; color: #8e8ea0; text-transform: uppercase; letter-spacing: 2px; font-weight: 600; margin-bottom: 8px; }
        .header-date { font-size: 30px; font-weight: 700; color: #1a1a2e; margin-bottom: 6px; }
        .header-total { font-size: 15px; color: #6b6b80; }
        .header-total strong { color: #1a1a2e; font-weight: 700; }

        .metric-cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 32px; }
        .metric-card {
            background: #fff; border-radius: 12px; padding: 16px 20px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06);
        }
        .metric-label { font-size: 11px; color: #8e8ea0; text-transform: uppercase; letter-spacing: 1px; font-weight: 600; margin-bottom: 6px; }
        .metric-value { font-size: 22px; font-weight: 700; color: #1a1a2e; }
        .metric-sub { font-size: 12px; color: #a0a0b0; margin-top: 2px; }

        .overview { display: grid; grid-template-columns: 220px 1fr; gap: 20px; margin-bottom: 44px; align-items: start; }
        .overview-chart {
            background: #fff; border-radius: 16px; padding: 28px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); display:flex; align-items:center; justify-content:center;
        }
        .overview-stats {
            background: #fff; border-radius: 16px; padding: 24px 28px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); display:flex; flex-direction:column; gap:10px;
        }
        .stat-row { display:flex; align-items:center; gap:10px; }
        .stat-dot { width:10px; height:10px; border-radius:50%; flex-shrink:0; }
        .stat-name { flex:1; font-size:14px; color:#6b6b80; }
        .stat-value { font-size:14px; font-weight:600; color:#1a1a2e; min-width:60px; text-align:right; }
        .stat-pct { font-size:12px; color:#a0a0b0; width:40px; text-align:right; }

        .donut-container { position:relative; width:160px; height:160px; }
        .donut-center { position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); text-align:center; }
        .donut-total { font-size:20px; font-weight:700; color:#1a1a2e; }
        .donut-label { font-size:11px; color:#a0a0b0; }

        .section-title {
            font-size: 12px; color: #8e8ea0; text-transform: uppercase;
            letter-spacing: 2px; font-weight: 600; margin-bottom: 16px; margin-top: 8px;
        }

        .app-card {
            background: #fff; border-radius: 14px; padding: 20px 24px; margin-bottom: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); scroll-margin-top: 24px;
        }
        .app-header { display:flex; justify-content:space-between; align-items:center; margin-bottom: 12px; }
        .app-name-row { display:flex; align-items:center; gap:10px; }
        .app-dot { width:12px; height:12px; border-radius:4px; flex-shrink:0; }
        .app-name { font-size:16px; font-weight:600; color:#1a1a2e; }
        .app-meta { display:flex; align-items:baseline; gap:10px; }
        .app-time { font-size:16px; font-weight:700; color:#1a1a2e; }
        .app-pct { font-size:13px; color:#a0a0b0; }
        .app-bar-track { height:5px; background:#f0f0f5; border-radius:3px; margin-bottom:16px; }
        .app-bar-fill { height:100%; border-radius:3px; }

        .windows-list { display:flex; flex-direction:column; gap:6px; }
        .window-row {
            display:flex; justify-content:space-between; align-items:center;
            padding:10px 14px; background:#f8f9fb; border-radius:10px; gap:16px;
        }
        .window-info { flex:1; min-width:0; }
        .window-title { font-size:13px; color:#1a1a2e; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; font-weight:500; }
        .window-detail { font-size:11px; color:#8e8ea0; margin-top:2px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .window-detail .tag { display:inline-block; background:#eef0ff; color:#6366f1; font-size:10px; font-weight:600; padding:1px 6px; border-radius:4px; margin-right:4px; }
        .window-stats { display:flex; align-items:center; gap:10px; flex-shrink:0; }
        .window-bar-track { width:56px; height:4px; background:#eee; border-radius:2px; }
        .window-bar-fill { height:100%; border-radius:2px; }
        .window-time { font-size:13px; font-weight:600; color:#1a1a2e; width:60px; text-align:right; }
        .window-pct { font-size:11px; color:#a0a0b0; width:36px; text-align:right; }
        .window-assign-btn {
            opacity:0; padding:3px 10px; border-radius:5px; font-size:11px; font-weight:600;
            background:#eef0ff; color:#6366f1; border:1px solid #d4d4f8; cursor:pointer;
            transition:opacity .15s, background .1s; white-space:nowrap;
        }
        .window-row:hover .window-assign-btn { opacity:1; }
        .window-assign-btn:hover { background:#dde0ff; }

        /* Bulk Selection */
        .bulk-check {
            width:16px; height:16px; accent-color:#6366f1; cursor:pointer; flex-shrink:0;
            margin:0; border-radius:3px;
        }
        .window-row.selected { background:#eef0ff; }
        .select-all-wrap {
            display:flex; align-items:center; gap:5px; cursor:pointer; font-size:11px; color:#a0a0b0;
            user-select:none; margin-left:auto;
        }
        .select-all-wrap input { margin:0; }
        .bulk-bar {
            position:fixed; bottom:0; left:0; right:0; z-index:1000;
            background:#1a1a2e; color:#fff; padding:12px 24px;
            display:none; align-items:center; gap:16px; justify-content:center;
            box-shadow:0 -4px 20px rgba(0,0,0,0.15);
            animation:slideUp .2s ease;
        }
        .bulk-bar.visible { display:flex; }
        @keyframes slideUp { from{transform:translateY(100%)} to{transform:translateY(0)} }
        .bulk-bar .bulk-count { font-size:13px; font-weight:600; white-space:nowrap; }
        .bulk-bar select {
            padding:6px 10px; border-radius:6px; border:1px solid #444;
            background:#2a2a3e; color:#fff; font-size:12px; min-width:180px;
        }
        .bulk-bar .bulk-assign-btn {
            padding:6px 16px; border-radius:6px; font-size:12px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer;
        }
        .bulk-bar .bulk-assign-btn:hover { background:#4f46e5; }
        .bulk-bar .bulk-assign-btn:disabled { opacity:0.5; cursor:default; }
        .bulk-bar .bulk-rule-label { display:flex; align-items:center; gap:4px; font-size:11px; color:#a0a0b0; }
        .bulk-bar .bulk-rule-label input { margin:0; }
        .bulk-bar .bulk-clear-btn {
            padding:6px 12px; border-radius:6px; font-size:12px; font-weight:500;
            background:#333; color:#ccc; border:1px solid #555; cursor:pointer;
        }
        .bulk-bar .bulk-clear-btn:hover { background:#444; }
        .window-assign-popup {
            display:flex; align-items:center; gap:6px; margin-top:6px;
            padding:6px 10px; background:#f0f0ff; border-radius:8px; animation:fadeIn .1s;
        }
        @keyframes fadeIn { from{opacity:0;transform:translateY(-4px)} to{opacity:1;transform:translateY(0)} }
        .window-assign-popup select { font-size:12px; padding:3px 6px; border:1px solid #d0d0e0; border-radius:5px; background:#fff; color:#1a1a2e; }
        .window-assign-popup .wa-save { padding:3px 10px; border-radius:5px; font-size:11px; font-weight:600; background:#6366f1; color:#fff; border:none; cursor:pointer; }
        .window-assign-popup .wa-save:hover { background:#4f46e5; }
        .window-assign-popup .wa-cancel { padding:3px 8px; border-radius:5px; font-size:11px; background:#e8e8ee; color:#6b6b80; border:none; cursor:pointer; }
        .window-assign-popup .wa-rule { display:flex; align-items:center; gap:3px; font-size:11px; color:#8e8ea0; }
        .window-assign-popup .wa-rule input { margin:0; }

        .timeline { margin-top:44px; scroll-margin-top: 24px; }
        .tl-group { margin-bottom:16px; }
        .tl-app { font-size:14px; font-weight:600; color:#1a1a2e; display:flex; align-items:center; gap:8px; margin-bottom:6px; }
        .tl-dot { width:8px; height:8px; border-radius:50%; }
        .tl-entry { display:flex; align-items:baseline; gap:12px; padding:3px 0 3px 20px; font-size:13px; }
        .tl-time { color:#a0a0b0; font-variant-numeric:tabular-nums; width:48px; flex-shrink:0; font-size:12px; }
        .tl-title { color:#4a4a5a; flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .tl-extra { color:#8e8ea0; font-size:11px; padding:0 0 2px 80px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .tl-dur { color:#6b6b80; flex-shrink:0; font-weight:500; }

        .json-btn {
            display:inline-flex; align-items:center; gap:6px;
            padding:7px 14px; border-radius:8px; font-size:12px; font-weight:600;
            background:#f0f0f5; color:#6366f1; border:none; cursor:pointer;
            text-decoration:none; transition:background .15s;
        }
        .analysis-section {
            background: #fff; border-radius: 14px; padding: 24px 28px; margin-bottom: 32px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); border-left: 3px solid #6366f1;
            scroll-margin-top: 24px;
        }
        .analysis-header { display:flex; align-items:center; gap:10px; margin-bottom:16px; }
        .analysis-icon {
            width:32px; height:32px; border-radius:8px; background:linear-gradient(135deg,#6366f1,#8b5cf6);
            display:flex; align-items:center; justify-content:center; flex-shrink:0;
        }
        .analysis-icon svg { width:16px; height:16px; }
        .analysis-title { font-size:16px; font-weight:700; color:#1a1a2e; }
        .analysis-badge { font-size:10px; font-weight:600; padding:2px 8px; border-radius:4px; background:#eef0ff; color:#6366f1; }
        .analysis-body { font-size:13px; color:#4a4a5a; line-height:1.7; }
        .analysis-body h2 { font-size:15px; font-weight:700; color:#1a1a2e; margin:20px 0 10px; }
        .analysis-body h2:first-child { margin-top:0; }
        .analysis-body h3 { font-size:14px; font-weight:700; color:#6366f1; margin:16px 0 6px; }
        .analysis-body .project-total { font-size:13px; font-weight:600; color:#1a1a2e; margin-bottom:4px; }
        .analysis-body ul { list-style:none; padding:0; margin:0 0 8px; }
        .analysis-body li { padding:3px 0 3px 16px; position:relative; }
        .analysis-body li::before { content:''; position:absolute; left:4px; top:10px; width:5px; height:5px; border-radius:50%; background:#c4c7d4; }
        .analysis-body p { margin:4px 0; }
        .analysis-empty {
            text-align:center; padding:32px; color:#a0a0b0; font-size:13px;
        }

        .json-btn:hover { background:#e4e4ef; }
        .json-btn[style*="6366f1"]:hover { background:#4f46e5 !important; }
        .json-btn svg { width:14px; height:14px; }

        /* Projects Section */
        .projects-section { margin-bottom: 44px; scroll-margin-top: 24px; }
        .brand-bar-container { background:#fff; border-radius:14px; padding:20px 24px; margin-bottom:16px; box-shadow:0 1px 3px rgba(0,0,0,0.06); }
        .brand-stacked-bar { display:flex; height:28px; border-radius:8px; overflow:hidden; background:#f0f0f5; margin-bottom:12px; }
        .brand-stacked-segment { display:flex; align-items:center; justify-content:center; color:#fff; font-size:10px; font-weight:700; cursor:default; transition:opacity .15s; min-width:2px; }
        .brand-stacked-segment:hover { opacity:0.85; }
        .brand-bar-legend { display:flex; flex-wrap:wrap; gap:12px; }
        .brand-legend-item { display:flex; align-items:center; gap:6px; font-size:12px; color:#6b6b80; }
        .brand-legend-dot { width:8px; height:8px; border-radius:50%; flex-shrink:0; }

        .brand-card {
            background:#fff; border-radius:14px; margin-bottom:12px; box-shadow:0 1px 3px rgba(0,0,0,0.06); overflow:hidden;
        }
        .brand-card-header {
            display:flex; justify-content:space-between; align-items:center; padding:16px 24px;
            cursor:pointer; user-select:none; transition:background .15s;
        }
        .brand-card-header:hover { background:#fafafe; }
        .brand-card-left { display:flex; align-items:center; gap:10px; }
        .brand-color-bar { width:4px; height:24px; border-radius:2px; }
        .brand-card-name { font-size:15px; font-weight:600; color:#1a1a2e; }
        .brand-card-right { display:flex; align-items:center; gap:12px; }
        .brand-card-time { font-size:15px; font-weight:700; color:#1a1a2e; }
        .brand-card-pct { font-size:12px; color:#a0a0b0; }
        .brand-card-chevron { color:#a0a0b0; transition:transform .2s; font-size:14px; }
        .brand-card-body { padding:0 24px 16px; display:none; }
        .brand-card.open .brand-card-body { display:block; }
        .brand-card.open .brand-card-chevron { transform:rotate(90deg); }

        .proj-row {
            display:flex; justify-content:space-between; align-items:center;
            padding:10px 14px; background:#f8f9fb; border-radius:10px; margin-bottom:6px; gap:16px;
        }
        .proj-info { flex:1; min-width:0; }
        .proj-name { font-size:13px; font-weight:600; color:#1a1a2e; }
        .proj-apps { font-size:11px; color:#8e8ea0; margin-top:2px; }
        .proj-stats { display:flex; align-items:center; gap:10px; flex-shrink:0; }
        .proj-bar-track { width:56px; height:4px; background:#eee; border-radius:2px; }
        .proj-bar-fill { height:100%; border-radius:2px; }
        .proj-time { font-size:13px; font-weight:600; color:#1a1a2e; width:60px; text-align:right; }
        .proj-pct { font-size:11px; color:#a0a0b0; width:36px; text-align:right; }

        /* Unassigned Table */
        .unassigned-section { background:#fff; border-radius:14px; padding:20px 24px; margin-top:16px; box-shadow:0 1px 3px rgba(0,0,0,0.06); border-left:3px solid #f59e0b; }
        .unassigned-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; }
        .unassigned-title { font-size:14px; font-weight:700; color:#1a1a2e; }
        .unassigned-count { font-size:12px; color:#a0a0b0; }
        .unassigned-row {
            display:flex; align-items:center; gap:12px; padding:8px 0; border-bottom:1px solid #f0f0f5; font-size:13px;
        }
        .unassigned-row:last-child { border-bottom:none; }
        .unassigned-app { font-weight:600; color:#1a1a2e; width:100px; flex-shrink:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .unassigned-detail { flex:1; min-width:0; color:#6b6b80; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .unassigned-dur { font-weight:600; color:#1a1a2e; width:60px; text-align:right; flex-shrink:0; }
        .unassigned-select { width:160px; flex-shrink:0; font-size:12px; padding:4px 8px; border:1px solid #e0e0e8; border-radius:6px; background:#fff; color:#1a1a2e; }
        .unassigned-save-btn {
            padding:4px 12px; border-radius:6px; font-size:11px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer; flex-shrink:0;
        }
        .unassigned-save-btn:hover { background:#4f46e5; }
        .unassigned-save-btn:disabled { background:#c0c0c8; cursor:default; }
        .unassigned-save-all {
            display:inline-flex; align-items:center; gap:6px;
            padding:7px 14px; border-radius:8px; font-size:12px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer; margin-top:12px;
        }
        .unassigned-save-all:hover { background:#4f46e5; }
        .unassigned-api-error { color:#ef4444; font-size:12px; margin-top:8px; display:none; }
        .unassigned-rule-check { display:flex; align-items:center; gap:4px; font-size:11px; color:#8e8ea0; flex-shrink:0; }
        .unassigned-rule-check input { margin:0; }

        /* Create Entity Bar & Modal */
        .create-entity-bar { display:flex; gap:8px; }
        .create-entity-btn {
            display:inline-flex; align-items:center; gap:4px;
            padding:5px 12px; border-radius:6px; font-size:12px; font-weight:600;
            background:#f0f0f5; color:#6366f1; border:1px solid #e0e0e8; cursor:pointer;
            transition:background .15s, border-color .15s;
        }
        .create-entity-btn:hover { background:#eef0ff; border-color:#c7c7f4; }
        .create-modal-overlay {
            position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.3);
            display:flex; align-items:center; justify-content:center; z-index:1000;
        }
        .create-modal {
            background:#fff; border-radius:16px; padding:28px 32px; width:420px; max-width:90vw;
            box-shadow:0 20px 60px rgba(0,0,0,0.15); animation:modalIn .15s ease-out;
        }
        @keyframes modalIn { from { opacity:0; transform:scale(0.95); } to { opacity:1; transform:scale(1); } }
        .create-modal h3 { font-size:16px; font-weight:700; color:#1a1a2e; margin-bottom:20px; }
        .create-form { display:flex; flex-direction:column; gap:14px; }
        .create-form label { font-size:12px; font-weight:600; color:#6b6b80; text-transform:uppercase; letter-spacing:0.5px; }
        .create-form input[type="text"], .create-form select {
            width:100%; padding:8px 12px; border:1px solid #e0e0e8; border-radius:8px;
            font-size:14px; color:#1a1a2e; background:#fff; outline:none; transition:border-color .15s;
        }
        .create-form input[type="text"]:focus, .create-form select:focus { border-color:#6366f1; }
        .color-picker { display:flex; gap:8px; flex-wrap:wrap; margin-top:4px; }
        .color-swatch {
            width:28px; height:28px; border-radius:50%; border:3px solid transparent; cursor:pointer;
            transition:border-color .15s, transform .1s;
        }
        .color-swatch:hover { transform:scale(1.1); }
        .color-swatch.selected { border-color:#1a1a2e; }
        .create-form-actions { display:flex; justify-content:flex-end; gap:8px; margin-top:8px; }
        .create-form-actions button {
            padding:8px 20px; border-radius:8px; font-size:13px; font-weight:600; cursor:pointer; border:none;
        }
        .btn-cancel { background:#f0f0f5; color:#6b6b80; }
        .btn-cancel:hover { background:#e4e4ef; }
        .btn-create { background:#6366f1; color:#fff; }
        .btn-create:hover { background:#4f46e5; }
        .btn-create:disabled { background:#c0c0c8; cursor:default; }
        .create-form-error { color:#ef4444; font-size:12px; display:none; }

        /* Suggestion Cards */
        .suggestions-container { margin-bottom:20px; }
        .suggestions-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; }
        .suggestions-title { font-size:14px; font-weight:700; color:#1a1a2e; }
        .suggestions-badge { font-size:10px; font-weight:600; padding:2px 8px; border-radius:4px; background:#fef3c7; color:#b45309; }
        .suggestion-card {
            background:#fff; border-radius:12px; padding:16px 20px; margin-bottom:10px;
            box-shadow:0 1px 3px rgba(0,0,0,0.06); border-left:3px solid #f59e0b;
            transition:opacity .3s, max-height .3s;
        }
        .suggestion-card.dismissed { opacity:0; max-height:0; overflow:hidden; padding:0 20px; margin:0; border:none; }
        .suggestion-card-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; }
        .suggestion-card-name { font-size:15px; font-weight:600; color:#1a1a2e; }
        .suggestion-card-meta { font-size:12px; color:#8e8ea0; }
        .suggestion-card-apps { font-size:11px; color:#8e8ea0; margin-bottom:8px; }
        .suggestion-card-rules { display:flex; flex-wrap:wrap; gap:4px; margin-bottom:10px; }
        .suggestion-rule-tag { display:inline-block; font-size:10px; font-weight:600; padding:2px 8px; border-radius:4px; background:#f0f0f5; color:#6b6b80; }
        .suggestion-card-actions { display:flex; align-items:center; gap:8px; }
        .suggestion-btn-create {
            padding:5px 14px; border-radius:6px; font-size:12px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer;
        }
        .suggestion-btn-create:hover { background:#4f46e5; }
        .suggestion-btn-assign {
            padding:5px 10px; border-radius:6px; font-size:12px; font-weight:600;
            background:#f0f0f5; color:#6366f1; border:1px solid #d4d4f8; cursor:pointer;
        }
        .suggestion-btn-assign:hover { background:#eef0ff; }
        .suggestion-btn-dismiss {
            padding:5px 10px; border-radius:6px; font-size:12px;
            background:transparent; color:#a0a0b0; border:1px solid #e8e8ee; cursor:pointer; margin-left:auto;
        }
        .suggestion-btn-dismiss:hover { background:#f8f8fa; color:#6b6b80; }
        .suggestion-assign-row { display:flex; align-items:center; gap:6px; margin-top:8px; animation:fadeIn .15s; }
        .suggestion-assign-select { font-size:12px; padding:4px 8px; border:1px solid #e0e0e8; border-radius:6px; background:#fff; color:#1a1a2e; }
        .suggestion-loading { text-align:center; padding:20px; color:#a0a0b0; font-size:13px; }

        .footer { margin-top:60px; text-align:center; font-size:12px; color:#c0c0c8; }

        @media (max-width:1100px) {
            .layout.has-right-panel { grid-template-columns: 1fr 300px; }
            .layout.has-right-panel .sidebar { display: none; }
        }
        @media (max-width:900px) {
            .layout { grid-template-columns: 1fr; }
            .layout.has-right-panel { grid-template-columns: 1fr; }
            .sidebar { display: none; }
            .right-panel { position: static; max-height: none; }
        }
        @media (max-width:640px) {
            .overview { grid-template-columns:1fr; }
            .layout { padding:24px 16px 60px; }
            .metric-cards { grid-template-columns:1fr; }
        }
        </style>
        </head>
        <body>
        <div class="layout\(hasRightPanel ? " has-right-panel" : "")">
            \(sidebar)
            <div class="main-content">
                <div class="header" id="overview">
                    <div class="header-label">Activity Report</div>
                    <div class="header-date">\(dateDisplay)</div>
                    <div class="header-total">Total active time <strong>\(totalTime)</strong> across <strong>\(summary.apps.count)</strong> app\(summary.apps.count == 1 ? "" : "s")</div>
                    <div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap">
                        <a href="report-\(summary.date).json" download class="json-btn">
                            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2v8m0 0l-3-3m3 3l3-3M3 12h10"/></svg>
                            Download JSON
                        </a>
                        <button onclick="analyzeWithAI()" class="json-btn" id="analyze-btn" style="background:#6366f1;color:#fff">
                            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg>
                            Analyze with AI
                        </button>
                    </div>
                </div>

                \(metricCards)

                \(analysisHTML)

                \(projectsHTML)

                <div class="overview">
                    <div class="overview-chart">
                        <div class="donut-container">
                            <svg viewBox="0 0 36 36" width="160" height="160">
                                \(donutSegments)
                            </svg>
                            <div class="donut-center">
                                <div class="donut-total">\(totalTime)</div>
                                <div class="donut-label">total</div>
                            </div>
                        </div>
                    </div>
                    <div class="overview-stats">
                        \(summary.apps.prefix(10).enumerated().map { i, app in
                            let color = appColorMap[app.appName] ?? "#6366f1"
                            let pct = summary.totalSeconds > 0
                                ? Double(app.totalSeconds) / Double(summary.totalSeconds) * 100 : 0
                            return """
                            <div class="stat-row">
                                <span class="stat-dot" style="background:\(color)"></span>
                                <span class="stat-name">\(esc(app.appName))</span>
                                <span class="stat-value">\(dur(app.totalSeconds))</span>
                                <span class="stat-pct">\(String(format:"%.0f", pct))%</span>
                            </div>
                            """
                        }.joined(separator: "\n"))
                    </div>
                </div>

                <div id="apps" class="section-title" style="scroll-margin-top:24px">Applications</div>
                \(appCards)

                \(timelineHTML)

                <div class="footer">Generated by Pulse</div>
            </div>
            \(rightPanel)
        </div>
        <script>var __reportData = \(inlineJSON);</script>
        <script>var __projectData = \(projectDataJSON);</script>
        <script>
        (function() {
            const sections = document.querySelectorAll('[id]');
            const navLinks = document.querySelectorAll('.sidebar a[href^="#"]');
            if (!navLinks.length) return;
            const observer = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    if (entry.isIntersecting) {
                        const id = entry.target.getAttribute('id');
                        navLinks.forEach(function(link) {
                            link.classList.toggle('active', link.getAttribute('href') === '#' + id);
                        });
                    }
                });
            }, { rootMargin: '-20% 0px -70% 0px' });
            sections.forEach(function(section) { observer.observe(section); });

            // Brand card toggle
            document.querySelectorAll('.brand-card-header').forEach(function(h) {
                h.addEventListener('click', function() {
                    h.closest('.brand-card').classList.toggle('open');
                });
            });
        })();

        // API helper
        var API_PORT = (__projectData && __projectData.apiPort) || 18492;
        var API_BASE = 'http://127.0.0.1:' + API_PORT;

        function apiCall(path, body) {
            return fetch(API_BASE + path, {
                method: body ? 'POST' : 'GET',
                headers: {'Content-Type': 'application/json'},
                body: body ? JSON.stringify(body) : undefined
            }).then(function(r) { return r.json(); });
        }

        // Resolve "new:brandId" values by creating a project first, returns Promise<int>
        function resolveProjectId(val) {
            if (typeof val === 'string' && val.indexOf('new:') === 0) {
                var brandId = parseInt(val.substring(4));
                var brandName = '';
                (__projectData.brands || []).forEach(function(b) { if (b.id === brandId) brandName = b.name; });
                var projName = prompt('New project name for "'+brandName+'":', brandName);
                if (!projName) return Promise.reject(new Error('Cancelled'));
                return apiCall('/api/project', {brandId: brandId, name: projName, color: '#6366f1'}).then(function(res) {
                    if (res.id) {
                        __projectData.projects.push({id:res.id, brandId:brandId, brandName:brandName, name:projName, color:'#6366f1'});
                        return res.id;
                    }
                    throw new Error(res.error || 'Failed to create project');
                });
            }
            var pid = parseInt(val);
            if (!pid || isNaN(pid)) return Promise.reject(new Error('No project selected'));
            return Promise.resolve(pid);
        }

        function classifyRow(btn) {
            var row = btn.closest('.unassigned-row');
            var actId = parseInt(row.dataset.activityId);
            var sel = row.querySelector('.unassigned-select');
            var pid = parseInt(sel.value);
            if (!pid || isNaN(pid)) return;

            var createRule = row.querySelector('.rule-check') ? row.querySelector('.rule-check').checked : false;
            var body = { activityIds: [actId], projectId: pid };

            if (createRule) {
                var detail = row.querySelector('.unassigned-detail');
                var text = detail ? detail.textContent.trim() : '';
                if (text.indexOf('http') === 0 || text.indexOf('www.') === 0) {
                    try {
                        var u = new URL(text.indexOf('http') !== 0 ? 'https://' + text : text);
                        body.createRule = true;
                        body.ruleType = 'urlDomain';
                        body.rulePattern = u.hostname;
                    } catch(e) {}
                } else if (text.indexOf('/') !== -1 || text.indexOf('~') === 0) {
                    body.createRule = true;
                    body.ruleType = 'terminalFolder';
                    body.rulePattern = text.split('/').pop() || text;
                }
            }

            btn.disabled = true;
            btn.textContent = '...';
            apiCall('/api/classify', body).then(function(res) {
                if (res.error) { showApiError(res.error); btn.disabled = false; btn.textContent = 'Save'; return; }
                row.style.opacity = '0.4';
                row.style.pointerEvents = 'none';
                btn.textContent = 'Done';
            }).catch(function(e) {
                showApiError('Cannot connect to Pulse. Make sure it is running.');
                btn.disabled = false;
                btn.textContent = 'Save';
            });
        }

        function classifyAll() {
            var rows = document.querySelectorAll('.unassigned-row');
            var promises = [];
            rows.forEach(function(row) {
                if (row.style.opacity === '0.4') return;
                var sel = row.querySelector('.unassigned-select');
                var pid = parseInt(sel.value);
                if (!pid || isNaN(pid)) return;
                var actId = parseInt(row.dataset.activityId);
                promises.push(apiCall('/api/classify', { activityIds: [actId], projectId: pid }));
                row.style.opacity = '0.4';
                row.style.pointerEvents = 'none';
            });
            if (promises.length === 0) return;
            Promise.all(promises).then(function() {
                var saveAllBtn = document.getElementById('save-all-btn');
                if (saveAllBtn) { saveAllBtn.textContent = 'All Saved'; saveAllBtn.disabled = true; }
            }).catch(function(e) {
                showApiError('Cannot connect to Pulse. Make sure it is running.');
            });
        }

        function showApiError(msg) {
            var el = document.getElementById('api-error');
            if (el) { el.textContent = msg; el.style.display = 'block'; }
        }

        var CREATE_COLORS = [
            {name:'Indigo',hex:'#6366f1'},{name:'Amber',hex:'#f59e0b'},{name:'Emerald',hex:'#10b981'},
            {name:'Red',hex:'#ef4444'},{name:'Purple',hex:'#8b5cf6'},{name:'Pink',hex:'#ec4899'},
            {name:'Teal',hex:'#14b8a6'},{name:'Orange',hex:'#f97316'},{name:'Cyan',hex:'#06b6d4'},
            {name:'Lime',hex:'#84cc16'}
        ];

        function buildColorPicker(selectedHex) {
            return CREATE_COLORS.map(function(c) {
                var sel = c.hex === selectedHex ? ' selected' : '';
                return '<span class="color-swatch' + sel + '" data-color="' + c.hex + '" style="background:' + c.hex + '" title="' + c.name + '" onclick="pickColor(this)"></span>';
            }).join('');
        }

        function pickColor(el) {
            el.closest('.color-picker').querySelectorAll('.color-swatch').forEach(function(s) { s.classList.remove('selected'); });
            el.classList.add('selected');
        }

        function closeModal() {
            var overlay = document.querySelector('.create-modal-overlay');
            if (overlay) overlay.remove();
        }

        function showCreateBrand() {
            var html = '<div class="create-modal-overlay" onclick="if(event.target===this)closeModal()">' +
                '<div class="create-modal">' +
                '<h3>Create Brand</h3>' +
                '<div class="create-form">' +
                '  <div><label>Brand Name</label><input type="text" id="create-brand-name" placeholder="e.g. Acme Corp" autofocus></div>' +
                '  <div><label>Color</label><div class="color-picker">' + buildColorPicker('#6366f1') + '</div></div>' +
                '  <div class="create-form-error" id="create-brand-error"></div>' +
                '  <div class="create-form-actions">' +
                '    <button class="btn-cancel" onclick="closeModal()">Cancel</button>' +
                '    <button class="btn-create" id="create-brand-btn" onclick="doCreateBrand()">Create</button>' +
                '  </div>' +
                '</div></div></div>';
            document.body.insertAdjacentHTML('beforeend', html);
            document.getElementById('create-brand-name').focus();
        }

        function showCreateProject() {
            var brands = (__projectData && __projectData.brands) || [];
            var brandOpts = brands.map(function(b) {
                return '<option value="' + b.id + '">' + b.name + '</option>';
            }).join('');
            if (!brandOpts) brandOpts = '<option value="">No brands yet</option>';

            var html = '<div class="create-modal-overlay" onclick="if(event.target===this)closeModal()">' +
                '<div class="create-modal">' +
                '<h3>Create Project</h3>' +
                '<div class="create-form">' +
                '  <div><label>Brand</label><select id="create-proj-brand">' + brandOpts + '</select></div>' +
                '  <div><label>Project Name</label><input type="text" id="create-proj-name" placeholder="e.g. Website Redesign"></div>' +
                '  <div><label>Color</label><div class="color-picker">' + buildColorPicker('#10b981') + '</div></div>' +
                '  <div class="create-form-error" id="create-proj-error"></div>' +
                '  <div class="create-form-actions">' +
                '    <button class="btn-cancel" onclick="closeModal()">Cancel</button>' +
                '    <button class="btn-create" id="create-proj-btn" onclick="doCreateProject()">Create</button>' +
                '  </div>' +
                '</div></div></div>';
            document.body.insertAdjacentHTML('beforeend', html);
            document.getElementById('create-proj-name').focus();
        }

        function doCreateBrand() {
            var name = document.getElementById('create-brand-name').value.trim();
            var errEl = document.getElementById('create-brand-error');
            if (!name) { errEl.textContent = 'Brand name is required'; errEl.style.display = 'block'; return; }
            var colorEl = document.querySelector('.create-modal .color-swatch.selected');
            var color = colorEl ? colorEl.dataset.color : '#6366f1';

            var btn = document.getElementById('create-brand-btn');
            btn.disabled = true;
            btn.textContent = 'Creating...';

            apiCall('/api/brand', {name: name, color: color}).then(function(res) {
                if (res.error) { errEl.textContent = res.error; errEl.style.display = 'block'; btn.disabled = false; btn.textContent = 'Create'; return; }
                closeModal();
                refreshProjectDropdowns();
            }).catch(function(e) {
                errEl.textContent = 'Cannot connect to Pulse.';
                errEl.style.display = 'block';
                btn.disabled = false;
                btn.textContent = 'Create';
            });
        }

        function doCreateProject() {
            var brandId = parseInt(document.getElementById('create-proj-brand').value);
            var name = document.getElementById('create-proj-name').value.trim();
            var errEl = document.getElementById('create-proj-error');
            if (!brandId) { errEl.textContent = 'Please select a brand'; errEl.style.display = 'block'; return; }
            if (!name) { errEl.textContent = 'Project name is required'; errEl.style.display = 'block'; return; }
            var colorEl = document.querySelector('.create-modal .color-swatch.selected');
            var color = colorEl ? colorEl.dataset.color : '#10b981';

            var btn = document.getElementById('create-proj-btn');
            btn.disabled = true;
            btn.textContent = 'Creating...';

            apiCall('/api/project', {brandId: brandId, name: name, color: color}).then(function(res) {
                if (res.error) { errEl.textContent = res.error; errEl.style.display = 'block'; btn.disabled = false; btn.textContent = 'Create'; return; }
                closeModal();
                refreshProjectDropdowns();
            }).catch(function(e) {
                errEl.textContent = 'Cannot connect to Pulse.';
                errEl.style.display = 'block';
                btn.disabled = false;
                btn.textContent = 'Create';
            });
        }

        function refreshProjectDropdowns() {
            apiCall('/api/projects').then(function(res) {
                if (res.error) return;
                // Update __projectData
                if (res.brands) __projectData.brands = res.brands;
                if (res.projects) __projectData.projects = res.projects;

                // Build new options HTML
                var optionsHTML = buildProjectOptions(res.brands, res.projects);

                // Replace all dropdowns (preserve current selection)
                document.querySelectorAll('.unassigned-select').forEach(function(sel) {
                    var prev = sel.value;
                    sel.innerHTML = optionsHTML;
                    if (prev) sel.value = prev;
                });
            }).catch(function() {});
        }

        function showWindowAssign(btn) {
            // Remove any existing popups
            document.querySelectorAll('.window-assign-popup').forEach(function(p) { p.remove(); });

            var row = btn.closest('.window-row');
            var ids = JSON.parse(row.dataset.ids || '[]');
            if (!ids.length) return;

            // Show loading popup
            var popup = document.createElement('div');
            popup.className = 'window-assign-popup';
            popup.innerHTML = '<span style="color:#8e8ea0;font-size:12px">Loading projects...</span>';
            row.after(popup);

            // Fetch fresh data from API
            apiCall('/api/projects').then(function(res) {
                var optionsHTML = buildProjectOptions(res.brands, res.projects);

                // Also update __projectData for other uses
                if (res.brands) __projectData.brands = res.brands;
                if (res.projects) __projectData.projects = res.projects;

                popup.innerHTML =
                    '<select class="wa-select">' + optionsHTML + '</select>' +
                    '<label class="wa-rule"><input type="checkbox" class="wa-rule-check" checked>Rule</label>' +
                    '<button class="wa-save" onclick="saveWindowAssign(this)">Save</button>' +
                    '<button class="wa-cancel" onclick="this.closest(\\'.window-assign-popup\\').remove()">Cancel</button>';
            }).catch(function() {
                popup.innerHTML = '<span style="color:#ef4444;font-size:12px">Cannot connect to Pulse</span>' +
                    '<button class="wa-cancel" onclick="this.closest(\\'.window-assign-popup\\').remove()">Close</button>';
            });
        }

        function saveWindowAssign(btn) {
            var popup = btn.closest('.window-assign-popup');
            var row = popup.previousElementSibling;
            var ids = JSON.parse(row.dataset.ids || '[]');
            var sel = popup.querySelector('.wa-select');
            var pid = parseInt(sel.value);
            if (!pid || !ids.length) return;

            var body = { activityIds: ids, projectId: pid };

            // Optionally create rule from window info
            var createRule = popup.querySelector('.wa-rule-check') ? popup.querySelector('.wa-rule-check').checked : false;
            if (createRule) {
                var detail = row.querySelector('.window-detail');
                var tag = row.querySelector('.tag');
                var titleEl = row.querySelector('.window-title');
                var text = detail ? detail.textContent.trim() : '';
                if (tag) {
                    // Extra info tag (terminal folder, etc)
                    var tagText = tag.textContent.trim();
                    if (tagText.indexOf('/') !== -1 || tagText.indexOf('~') === 0) {
                        body.createRule = true;
                        body.ruleType = 'terminalFolder';
                        body.rulePattern = tagText.split('/').pop() || tagText;
                    }
                }
                if (!body.createRule && text) {
                    if (text.indexOf('http') === 0 || text.indexOf('www.') === 0) {
                        try {
                            var u = new URL(text.indexOf('http') !== 0 ? 'https://' + text : text);
                            body.createRule = true;
                            body.ruleType = 'urlDomain';
                            body.rulePattern = u.hostname;
                        } catch(e) {}
                    } else if (text.indexOf('/') !== -1) {
                        body.createRule = true;
                        body.ruleType = 'terminalFolder';
                        body.rulePattern = text.split('/').pop() || text;
                    }
                }
                if (!body.createRule && titleEl) {
                    // Fallback: create windowTitle rule
                    var title = titleEl.textContent.trim();
                    if (title.length > 3) {
                        body.createRule = true;
                        body.ruleType = 'windowTitle';
                        body.rulePattern = title;
                    }
                }
            }

            btn.disabled = true;
            btn.textContent = '...';
            apiCall('/api/classify', body).then(function(res) {
                if (res.error) { btn.disabled = false; btn.textContent = 'Save'; return; }
                row.style.opacity = '0.4';
                popup.innerHTML = '<span style="color:#10b981;font-size:12px;font-weight:600">Assigned ' + ids.length + ' activities</span>';
                setTimeout(function() { popup.remove(); }, 2000);
            }).catch(function(e) {
                btn.disabled = false;
                btn.textContent = 'Save';
            });
        }

        // Refresh all dropdowns on page load with fresh API data
        (function() {
            try { refreshProjectDropdowns(); } catch(e) {}
        })();

        // === Suggestions ===
        (function() {
            var container = document.getElementById('suggestions-container');
            if (!container) return;

            // Store rules data per card (keyed by card id)
            var cardRulesMap = {};

            apiCall('/api/suggestions').then(function(res) {
                if (!res.suggestions || !res.suggestions.length) return;
                renderSuggestions(res.suggestions);
            }).catch(function() {});

            function renderSuggestions(brands) {
                var html = '<div class="suggestions-header">' +
                    '<span class="suggestions-title">Suggested Projects</span>' +
                    '<span class="suggestions-badge">Auto-detected</span>' +
                    '</div>';

                brands.forEach(function(brand, bi) {
                    brand.projects.forEach(function(proj, pi) {
                        var cardId = 'sug-' + bi + '-' + pi;
                        var appsStr = proj.apps.join(', ');

                        // Store rules data for this card
                        cardRulesMap[cardId] = proj.suggestedRules;

                        var rulesHTML = proj.suggestedRules.map(function(r) {
                            return '<span class="suggestion-rule-tag">' + escH(r.ruleType) + ': ' + escH(r.pattern) + '</span>';
                        }).join('');

                        html += '<div class="suggestion-card" id="' + cardId + '"' +
                            ' data-brand="' + escA(brand.suggestedName) + '"' +
                            ' data-project="' + escA(proj.suggestedName) + '"' +
                            ' data-token="' + escA(proj.fullToken) + '">' +
                            '<div class="suggestion-card-header">' +
                            '  <span class="suggestion-card-name">' + escH(brand.suggestedName) + ' \\u203A ' + escH(proj.suggestedName) + '</span>' +
                            '  <span class="suggestion-card-meta">' + proj.activityCount + ' activities</span>' +
                            '</div>' +
                            '<div class="suggestion-card-apps">Apps: ' + escH(appsStr) + '</div>' +
                            '<div class="suggestion-card-rules">' + rulesHTML + '</div>' +
                            '<div class="suggestion-card-actions"></div>' +
                            '<div class="suggestion-card-form" style="display:none"></div>' +
                            '</div>';
                    });
                });

                container.innerHTML = html;

                // Attach button event listeners (avoids inline onclick escaping issues)
                container.querySelectorAll('.suggestion-card').forEach(function(card) {
                    var actions = card.querySelector('.suggestion-card-actions');
                    actions.innerHTML =
                        '<button class="suggestion-btn-create sug-create-btn">Create</button>' +
                        '<button class="suggestion-btn-assign sug-assign-btn">Assign to...</button>' +
                        '<button class="suggestion-btn-dismiss sug-dismiss-btn">Dismiss</button>';

                    actions.querySelector('.sug-create-btn').addEventListener('click', function() { showCreateForm(card); });
                    actions.querySelector('.sug-assign-btn').addEventListener('click', function() { showAssignForm(card); });
                    actions.querySelector('.sug-dismiss-btn').addEventListener('click', function() {
                        var token = card.dataset.token;
                        if (token) apiCall('/api/suggestion/dismiss',{token:token}).catch(function(){});
                        card.classList.add('dismissed');
                    });
                });
            }

            function escH(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
            function escA(s) { return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;'); }

            function getRulesForCard(card) {
                var data = cardRulesMap[card.id];
                if (data) return data.map(function(r) {
                    return { ruleType: r.ruleType, pattern: r.pattern, isRegex: r.isRegex || false };
                });
                return [];
            }

            function clearForm(card) {
                var form = card.querySelector('.suggestion-card-form');
                form.style.display = 'none';
                form.innerHTML = '';
            }

            // --- Create flow: show editable name form ---
            function showCreateForm(card) {
                clearForm(card);
                var form = card.querySelector('.suggestion-card-form');
                var brandName = card.dataset.brand;
                var projName = card.dataset.project;

                form.style.display = 'block';
                form.innerHTML =
                    '<div class="suggestion-assign-row" style="flex-wrap:wrap;gap:8px">' +
                    '  <div style="display:flex;flex-direction:column;gap:4px;flex:1;min-width:140px">' +
                    '    <label style="font-size:11px;color:#8e8ea0;font-weight:600">Brand Name</label>' +
                    '    <input type="text" class="sug-brand-input" value="' + escA(brandName) + '" style="padding:6px 10px;border:1px solid #e0e0e8;border-radius:6px;font-size:13px;color:#1a1a2e;outline:none">' +
                    '  </div>' +
                    '  <div style="display:flex;flex-direction:column;gap:4px;flex:1;min-width:140px">' +
                    '    <label style="font-size:11px;color:#8e8ea0;font-weight:600">Project Name</label>' +
                    '    <input type="text" class="sug-proj-input" value="' + escA(projName) + '" style="padding:6px 10px;border:1px solid #e0e0e8;border-radius:6px;font-size:13px;color:#1a1a2e;outline:none">' +
                    '  </div>' +
                    '  <div style="display:flex;align-items:flex-end;gap:6px;padding-bottom:1px">' +
                    '    <button class="suggestion-btn-create sug-confirm-btn" style="padding:7px 16px">Save</button>' +
                    '    <button class="suggestion-btn-dismiss sug-cancel-btn" style="padding:7px 10px">Cancel</button>' +
                    '  </div>' +
                    '</div>';

                form.querySelector('.sug-confirm-btn').addEventListener('click', function() { doCreate(card); });
                form.querySelector('.sug-cancel-btn').addEventListener('click', function() { clearForm(card); });
                form.querySelector('.sug-brand-input').focus();
                form.querySelector('.sug-brand-input').select();
            }

            function doCreate(card) {
                var form = card.querySelector('.suggestion-card-form');
                var brandName = form.querySelector('.sug-brand-input').value.trim();
                var projName = form.querySelector('.sug-proj-input').value.trim();
                if (!brandName) { form.querySelector('.sug-brand-input').style.borderColor = '#ef4444'; return; }
                if (!projName) projName = brandName;

                var rules = getRulesForCard(card);
                var btn = form.querySelector('.sug-confirm-btn');
                btn.disabled = true;
                btn.textContent = 'Creating...';

                apiCall('/api/suggestion/accept', {
                    brandName: brandName,
                    projectName: projName,
                    rules: rules
                }).then(function(res) {
                    if (res.error) { btn.disabled = false; btn.textContent = 'Save'; showApiError(res.error); return; }
                    card.innerHTML = '<div style="padding:12px 0;color:#10b981;font-weight:600;font-size:13px">Created ' + escH(brandName) + ' \\u203A ' + escH(projName) + ' (' + (res.assigned || 0) + ' activities auto-assigned)</div>';
                    setTimeout(function() { card.classList.add('dismissed'); }, 3000);
                    refreshProjectDropdowns();
                }).catch(function() {
                    btn.disabled = false;
                    btn.textContent = 'Save';
                    showApiError('Cannot connect to Pulse.');
                });
            }

            // --- Assign flow: show project dropdown ---
            function showAssignForm(card) {
                clearForm(card);
                var form = card.querySelector('.suggestion-card-form');
                form.style.display = 'block';
                form.innerHTML =
                    '<div class="suggestion-assign-row">' +
                    '  <select class="suggestion-assign-select"><option value="">Loading...</option></select>' +
                    '  <button class="suggestion-btn-create sug-assign-confirm" style="font-size:11px;padding:5px 12px">Assign</button>' +
                    '  <button class="suggestion-btn-dismiss sug-assign-cancel" style="font-size:11px;padding:5px 10px">Cancel</button>' +
                    '</div>';

                form.querySelector('.sug-assign-confirm').addEventListener('click', function() { doAssign(card); });
                form.querySelector('.sug-assign-cancel').addEventListener('click', function() { clearForm(card); });

                apiCall('/api/projects').then(function(res) {
                    var optHTML = buildProjectOptions(res.brands, res.projects);
                    var sel = form.querySelector('select');
                    if (sel) sel.innerHTML = optHTML;
                }).catch(function() {
                    var sel = form.querySelector('select');
                    if (sel) sel.innerHTML = '<option value="">Cannot load projects</option>';
                });
            }

            function doAssign(card) {
                var form = card.querySelector('.suggestion-card-form');
                var selVal = form.querySelector('select').value;
                if (!selVal) return;

                var rules = getRulesForCard(card);
                var btn = form.querySelector('.sug-assign-confirm');
                btn.disabled = true;
                btn.textContent = '...';

                resolveProjectId(selVal).then(function(pid) {
                    return apiCall('/api/suggestion/accept', {
                        existingProjectId: pid,
                        rules: rules
                    });
                }).then(function(res) {
                    if (res.error) { btn.disabled = false; btn.textContent = 'Assign'; showApiError(res.error); return; }
                    card.innerHTML = '<div style="padding:12px 0;color:#10b981;font-weight:600;font-size:13px">Rules assigned (' + (res.assigned || 0) + ' activities matched)</div>';
                    setTimeout(function() { card.classList.add('dismissed'); }, 3000);
                    refreshProjectDropdowns();
                }).catch(function() {
                    btn.disabled = false;
                    btn.textContent = 'Assign';
                });
            }
        })();

        function analyzeWithAI() {
            var btn = document.getElementById('analyze-btn');
            btn.disabled = true;
            btn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg> Analyzing\\u2026';
            var style = document.createElement('style');
            style.textContent = '@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}';
            document.head.appendChild(style);

            try {
                var data = __reportData;
                var apiKey = localStorage.getItem('activity-tracker-api-key');
                if (!apiKey) {
                    apiKey = prompt('Enter your Claude API key to analyze:');
                    if (!apiKey) { resetBtn(); return; }
                    localStorage.setItem('activity-tracker-api-key', apiKey);
                }
                callClaude(apiKey, data);
            } catch(e) {
                alert('Error: ' + e.message);
                resetBtn();
            }

            function resetBtn() {
                btn.disabled = false;
                btn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg> Analyze with AI';
            }

            function callClaude(key, data) {
                var tl = data.timeline || [];
                var lines = tl.map(function(e) {
                    var t = new Date(e.timestamp).toTimeString().substring(0,5);
                    var extra = [e.extraInfo, e.url].filter(Boolean).join(' ');
                    var suffix = extra ? ' (' + extra + ')' : '';
                    return t + ' ' + e.appName + ': ' + e.windowTitle + ' [' + e.durationSeconds + 's]' + suffix;
                }).join('\\n');

                var systemMsg = 'You are a timesheet grouping tool. Group app usage entries by project/client and sum durations. Identify projects by recurring keywords in window titles, URLs, file paths. Same keyword across different apps = same project. Entries with no match go under Other. Sort by total time descending. Convert seconds to Xh Ym. Output ONLY the markdown format shown. No commentary, no tips, no analysis, no headers like Productivity Analysis.';

                var userMsg = 'Group by project:\\n\\n' + lines;

                return fetch('https://api.anthropic.com/v1/messages', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'x-api-key': key,
                        'anthropic-version': '2023-06-01',
                        'anthropic-dangerous-direct-browser-access': 'true'
                    },
                    body: JSON.stringify({
                        model: 'claude-haiku-4-5-20251001',
                        max_tokens: 2000,
                        system: systemMsg,
                        messages: [
                            {role: 'user', content: userMsg},
                            {role: 'assistant', content: '## Projects'}
                        ]
                    })
                }).then(function(r){return r.json()}).then(function(res) {
                    if (res.error) {
                        if (res.error.message && res.error.message.includes('invalid')) {
                            localStorage.removeItem('activity-tracker-api-key');
                        }
                        alert('API Error: ' + (res.error.message || JSON.stringify(res.error)));
                        resetBtn();
                        return;
                    }
                    var raw = (res.content || []).map(function(b){return b.text || ''}).join('\\n');
                    var text = '## Projects' + raw;
                    showAnalysis(text);
                    resetBtn();
                    btn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg> Re-analyze';
                }).catch(function(e) {
                    alert('Network error: ' + e.message);
                    resetBtn();
                });
            }

            function showAnalysis(text) {
                var existing = document.getElementById('analysis');
                if (existing) existing.remove();

                var div = document.createElement('div');
                div.id = 'analysis';
                div.className = 'analysis-section';

                var bodyHtml = mdToHtml(text);

                div.innerHTML = '<div class="analysis-header">' +
                    '<div class="analysis-icon"><svg viewBox="0 0 16 16" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg></div>' +
                    '<span class="analysis-title">Project Analysis</span>' +
                    '<span class="analysis-badge">AI</span>' +
                    '<button onclick="navigator.clipboard.writeText(this.closest(\\'#analysis\\').querySelector(\\'.analysis-body\\').textContent)" class="json-btn" style="font-size:11px;padding:4px 10px;margin-left:auto">Copy</button>' +
                    '</div>' +
                    '<div class="analysis-body">' + bodyHtml + '</div>';

                var overview = document.querySelector('.overview');
                overview.parentNode.insertBefore(div, overview);
                div.scrollIntoView({behavior:'smooth', block:'start'});
            }

            function mdToHtml(text) {
                var lines = text.split('\\n');
                var html = '';
                var inList = false;
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (!line) { if (inList) { html += '</ul>'; inList = false; } continue; }
                    if (line.indexOf('## ') === 0 && line.indexOf('### ') !== 0) {
                        if (inList) { html += '</ul>'; inList = false; }
                        html += '<h2>' + esc(line.substring(3)) + '</h2>';
                    } else if (line.indexOf('### ') === 0) {
                        if (inList) { html += '</ul>'; inList = false; }
                        html += '<h3>' + esc(line.substring(4)) + '</h3>';
                    } else if (line.indexOf('Total:') === 0 || line.indexOf('**Total') === 0) {
                        html += '<div class="project-total">' + esc(line.replace(/\\*\\*/g,'')) + '</div>';
                    } else if (line.indexOf('- ') === 0) {
                        if (!inList) { html += '<ul>'; inList = true; }
                        html += '<li>' + esc(line.substring(2)) + '</li>';
                    } else {
                        if (inList) { html += '</ul>'; inList = false; }
                        html += '<p>' + esc(line) + '</p>';
                    }
                }
                if (inList) html += '</ul>';
                return html;
            }

            function esc(s) {
                return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
            }
        }
        // === Bulk Selection ===
        function toggleBulkCheck(cb) {
            var row = cb.closest('.window-row');
            if (cb.checked) { row.classList.add('selected'); } else { row.classList.remove('selected'); }
            // Update select-all state for this card
            var card = row.closest('.app-card');
            if (card) {
                var all = card.querySelectorAll('.bulk-check');
                var checked = card.querySelectorAll('.bulk-check:checked');
                var sa = card.querySelector('.select-all-check');
                if (sa) { sa.checked = checked.length === all.length; sa.indeterminate = checked.length > 0 && checked.length < all.length; }
            }
            updateBulkBar();
        }

        function toggleSelectAll(sa) {
            var card = sa.closest('.app-card');
            if (!card) return;
            var boxes = card.querySelectorAll('.bulk-check');
            boxes.forEach(function(cb) {
                cb.checked = sa.checked;
                var row = cb.closest('.window-row');
                if (sa.checked) { row.classList.add('selected'); } else { row.classList.remove('selected'); }
            });
            updateBulkBar();
        }

        function updateBulkBar() {
            var selected = document.querySelectorAll('.bulk-check:checked');
            var bar = document.getElementById('bulk-bar');
            if (selected.length > 0) {
                bar.classList.add('visible');
                document.getElementById('bulk-count').textContent = selected.length + ' item' + (selected.length > 1 ? 's' : '') + ' selected';
            } else {
                bar.classList.remove('visible');
            }
        }

        function clearBulkSelection() {
            document.querySelectorAll('.bulk-check:checked').forEach(function(cb) {
                cb.checked = false;
                cb.closest('.window-row').classList.remove('selected');
            });
            document.querySelectorAll('.select-all-check').forEach(function(sa) {
                sa.checked = false;
                sa.indeterminate = false;
            });
            updateBulkBar();
        }

        function bulkAssign() {
            var sel = document.getElementById('bulk-project-select');
            var pid = parseInt(sel.value);
            if (!pid) return;

            var checked = document.querySelectorAll('.bulk-check:checked');
            if (!checked.length) return;

            // Collect all IDs
            var allIds = [];
            checked.forEach(function(cb) {
                var row = cb.closest('.window-row');
                var ids = JSON.parse(row.dataset.ids || '[]');
                allIds = allIds.concat(ids);
            });

            if (!allIds.length) return;

            var btn = document.getElementById('bulk-assign-btn');
            btn.disabled = true;
            btn.textContent = 'Assigning...';

            apiCall('/api/classify', { activityIds: allIds, projectId: pid }).then(function(res) {
                if (res.error) { btn.disabled = false; btn.textContent = 'Assign All'; showApiError(res.error); return; }
                // Fade assigned rows
                checked.forEach(function(cb) {
                    var row = cb.closest('.window-row');
                    row.style.opacity = '0.4';
                    cb.checked = false;
                    row.classList.remove('selected');
                });
                document.querySelectorAll('.select-all-check').forEach(function(sa) { sa.checked = false; sa.indeterminate = false; });
                btn.textContent = 'Done!';
                setTimeout(function() {
                    btn.disabled = false;
                    btn.textContent = 'Assign All';
                    updateBulkBar();
                }, 1500);
            }).catch(function() {
                btn.disabled = false;
                btn.textContent = 'Assign All';
            });
        }

        // Populate bulk bar dropdown on load
        (function() {
            var sel = document.getElementById('bulk-project-select');
            if (!sel) return;
            apiCall('/api/projects').then(function(res) {
                var optHTML = buildProjectOptions(res.brands, res.projects);
                sel.innerHTML = optHTML;
            }).catch(function() {});
        })();
        </script>

        <div id="bulk-bar" class="bulk-bar">
            <span id="bulk-count" class="bulk-count">0 items selected</span>
            <select id="bulk-project-select"><option value="">Loading projects...</option></select>
            <button id="bulk-assign-btn" class="bulk-assign-btn" onclick="bulkAssign()">Assign All</button>
            <button class="bulk-clear-btn" onclick="clearBulkSelection()">Clear</button>
        </div>

        </body>
        </html>
        """
    }

    // MARK: - Projects Section (main content - only brand summaries)

    private static func buildProjectsSection(brandSummaries: [BrandSummary], totalSeconds: Int, projectData: ProjectData?) -> String {
        let hasData = !brandSummaries.isEmpty
        guard hasData && totalSeconds > 0 else { return "" }

        var html = "<div class=\"projects-section\" id=\"projects\">\n"
        html += "<div class=\"section-title\">Projects</div>\n"

        // Stacked bar showing brand distribution
        html += "<div class=\"brand-bar-container\">\n"
        html += "<div class=\"brand-stacked-bar\">\n"
        for brand in brandSummaries {
            let pct = Double(brand.totalSeconds) / Double(totalSeconds) * 100
            if pct >= 0.5 {
                let label = pct >= 8 ? "\(esc(brand.brandName)) \(dur(brand.totalSeconds))" : dur(brand.totalSeconds)
                html += "<div class=\"brand-stacked-segment\" style=\"width:\(String(format:"%.1f", pct))%;background:\(brand.color)\" title=\"\(esc(brand.brandName)): \(dur(brand.totalSeconds))\">\(label)</div>\n"
            }
        }
        html += "</div>\n"

        // Legend
        html += "<div class=\"brand-bar-legend\">\n"
        for brand in brandSummaries {
            html += "<div class=\"brand-legend-item\"><span class=\"brand-legend-dot\" style=\"background:\(brand.color)\"></span>\(esc(brand.brandName)) \(dur(brand.totalSeconds))</div>\n"
        }
        html += "</div>\n"
        html += "</div>\n"

        // Brand cards (expandable)
        for brand in brandSummaries {
            let brandPct = totalSeconds > 0 ? Double(brand.totalSeconds) / Double(totalSeconds) * 100 : 0
            html += "<div class=\"brand-card\">\n"
            html += "<div class=\"brand-card-header\">\n"
            html += "  <div class=\"brand-card-left\"><div class=\"brand-color-bar\" style=\"background:\(brand.color)\"></div><span class=\"brand-card-name\">\(esc(brand.brandName))</span></div>\n"
            html += "  <div class=\"brand-card-right\"><span class=\"brand-card-time\">\(dur(brand.totalSeconds))</span><span class=\"brand-card-pct\">\(String(format:"%.0f", brandPct))%</span><span class=\"brand-card-chevron\">&#9654;</span></div>\n"
            html += "</div>\n"
            html += "<div class=\"brand-card-body\">\n"

            let maxProjSeconds = brand.projects.first?.totalSeconds ?? 1
            for proj in brand.projects {
                let projPct = brand.totalSeconds > 0 ? Double(proj.totalSeconds) / Double(brand.totalSeconds) * 100 : 0
                let barW = Double(proj.totalSeconds) / Double(maxProjSeconds) * 100
                let appsStr = proj.appBreakdown.prefix(3).map { "\($0.appName) \(dur($0.seconds))" }.joined(separator: ", ")
                html += "<div class=\"proj-row\">\n"
                html += "  <div class=\"proj-info\"><div class=\"proj-name\">\(esc(proj.projectName))</div><div class=\"proj-apps\">\(esc(appsStr))</div></div>\n"
                html += "  <div class=\"proj-stats\"><div class=\"proj-bar-track\"><div class=\"proj-bar-fill\" style=\"width:\(String(format:"%.1f", barW))%;background:\(proj.color)\"></div></div><span class=\"proj-time\">\(dur(proj.totalSeconds))</span><span class=\"proj-pct\">\(String(format:"%.0f", projPct))%</span></div>\n"
                html += "</div>\n"
            }

            html += "</div>\n</div>\n"
        }

        html += "</div>\n"
        return html
    }

    // MARK: - Right Panel (unclassified activities + suggestions)

    private static func buildRightPanel(projectData: ProjectData?) -> String {
        guard let pd = projectData else { return "" }

        // Filter out non-work apps from unassigned
        let filteredUnassigned = pd.unassigned.filter { !nonWorkApps.contains($0.appName) }
        guard !filteredUnassigned.isEmpty else { return "" }

        var html = "<div class=\"right-panel\">\n"
        html += "<div class=\"right-panel-title\">Unclassified</div>\n"

        // Suggestion container — populated via JS from /api/suggestions
        html += "<div id=\"suggestions-container\" class=\"suggestions-container\"></div>\n"

        // Unassigned activities
        html += "<div class=\"unassigned-section\">\n"
        html += "<div class=\"unassigned-header\">\n"
        html += "  <span class=\"unassigned-title\">Activities</span>\n"
        html += "  <span class=\"unassigned-count\">\(filteredUnassigned.count) items</span>\n"
        html += "</div>\n"

        // Build options for the project select dropdown
        var optionsHTML = "<option value=\"\">Select project...</option>"
        var brandMap: [Int64: (name: String, projects: [(id: Int64, name: String)])] = [:]
        for b in pd.brands {
            brandMap[b.id] = (name: b.name, projects: [])
        }
        for p in pd.projects {
            if brandMap[p.brandId] != nil {
                brandMap[p.brandId]!.projects.append((id: p.id, name: p.name))
            }
        }
        for (bid, entry) in brandMap.sorted(by: { $0.key < $1.key }) {
            optionsHTML += "<optgroup label=\"\(esc(entry.name))\">"
            if entry.projects.isEmpty {
                optionsHTML += "<option value=\"new:\(bid)\">\(esc(entry.name)) (new project)</option>"
            } else {
                for p in entry.projects {
                    optionsHTML += "<option value=\"\(p.id)\">\(esc(p.name))</option>"
                }
            }
            optionsHTML += "</optgroup>"
        }

        for act in filteredUnassigned.prefix(30) {
            let detail = act.url ?? act.extraInfo ?? act.windowTitle
            html += "<div class=\"unassigned-row\" data-activity-id=\"\(act.id)\">\n"
            html += "  <span class=\"unassigned-app\">\(esc(act.appName))</span>\n"
            html += "  <span class=\"unassigned-detail\" title=\"\(esc(act.windowTitle))\">\(esc(String(detail.prefix(50))))</span>\n"
            html += "  <span class=\"unassigned-dur\">\(dur(act.durationSeconds))</span>\n"
            html += "  <select class=\"unassigned-select\">\(optionsHTML)</select>\n"
            html += "  <label class=\"unassigned-rule-check\"><input type=\"checkbox\" class=\"rule-check\" checked> Rule</label>\n"
            html += "  <button class=\"unassigned-save-btn\" onclick=\"classifyRow(this)\">Save</button>\n"
            html += "</div>\n"
        }

        html += "<button class=\"unassigned-save-all\" id=\"save-all-btn\" onclick=\"classifyAll()\">Save All Selected</button>\n"
        html += "<div class=\"unassigned-api-error\" id=\"api-error\"></div>\n"
        html += "</div>\n"

        html += "</div>\n"
        return html
    }

    // MARK: - Metric Cards

    private static func buildMetricCards(summary: DaySummary) -> String {
        let wallTime = dur(summary.wallClockSeconds)
        let trackTime = dur(summary.activeTrackingSeconds)
        let timeRange: String
        if let first = summary.firstActivity, let last = summary.lastActivity {
            timeRange = "\(first) – \(last)"
        } else {
            timeRange = "–"
        }

        return """
        <div class="metric-cards">
            <div class="metric-card">
                <div class="metric-label">Wall Clock</div>
                <div class="metric-value">\(wallTime)</div>
                <div class="metric-sub">\(timeRange)</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Tracked Time</div>
                <div class="metric-value">\(trackTime)</div>
                <div class="metric-sub">total tracked</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Apps</div>
                <div class="metric-value">\(summary.apps.count)</div>
                <div class="metric-sub">apps used</div>
            </div>
        </div>
        """
    }

    // MARK: - Analysis Section

    private static func buildAnalysisSection(analysis: String?) -> String {
        guard let analysis = analysis, !analysis.isEmpty else { return "" }

        let htmlBody = markdownToHTML(analysis)

        return """
        <div class="analysis-section" id="analysis">
            <div class="analysis-header">
                <div class="analysis-icon">
                    <svg viewBox="0 0 16 16" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg>
                </div>
                <span class="analysis-title">Project Analysis</span>
                <span class="analysis-badge">AI</span>
            </div>
            <div class="analysis-body">
                \(htmlBody)
            </div>
        </div>
        """
    }

    private static func markdownToHTML(_ markdown: String) -> String {
        var html = ""
        var inList = false

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if inList { html += "</ul>"; inList = false }
                continue
            }

            if trimmed.hasPrefix("## ") {
                if inList { html += "</ul>"; inList = false }
                let text = String(trimmed.dropFirst(3))
                html += "<h2>\(esc(text))</h2>\n"
            } else if trimmed.hasPrefix("### ") {
                if inList { html += "</ul>"; inList = false }
                let text = String(trimmed.dropFirst(4))
                html += "<h3>\(esc(text))</h3>\n"
            } else if trimmed.hasPrefix("Total:") || trimmed.hasPrefix("**Total") {
                let cleaned = trimmed
                    .replacingOccurrences(of: "**", with: "")
                html += "<div class=\"project-total\">\(esc(cleaned))</div>\n"
            } else if trimmed.hasPrefix("- ") {
                if !inList { html += "<ul>"; inList = true }
                let text = String(trimmed.dropFirst(2))
                // Bold text within list items
                let formatted = esc(text)
                    .replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
                html += "<li>\(formatted)</li>\n"
            } else {
                if inList { html += "</ul>"; inList = false }
                let formatted = esc(trimmed)
                    .replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
                html += "<p>\(formatted)</p>\n"
            }
        }

        if inList { html += "</ul>" }
        return html
    }

    // MARK: - Sidebar

    private static func buildSidebar(summary: DaySummary, colors: [String: String], hasAnalysis: Bool = false, hasProjects: Bool = false) -> String {
        let appLinks = summary.apps.enumerated().map { i, app -> String in
            let color = colors[app.appName] ?? "#6366f1"
            return """
            <a href="#app-\(i)">
                <span class="nav-dot" style="background:\(color)"></span>
                \(esc(app.appName))
                <span class="nav-time">\(dur(app.totalSeconds))</span>
            </a>
            """
        }.joined(separator: "\n")

        let analysisLink = hasAnalysis ? """
            <a href="#analysis">
                <span class="nav-dot" style="background:#6366f1"></span>
                AI Analysis
            </a>
        """ : ""

        let projectsLink = hasProjects ? """
            <a href="#projects">
                <span class="nav-dot" style="background:#f59e0b"></span>
                Projects
            </a>
        """ : ""

        return """
        <nav class="sidebar">
            <div class="sidebar-section">
                <div class="sidebar-heading">Navigation</div>
                <a href="#overview">Overview</a>
                \(analysisLink)
                \(projectsLink)
                <a href="#apps">Applications</a>
                <a href="#timeline">Timeline</a>
            </div>
            <div class="nav-divider"></div>
            <div class="sidebar-section">
                <div class="sidebar-heading">Apps</div>
                \(appLinks)
            </div>
        </nav>
        """
    }

    // MARK: - App Cards

    private static let mediaApps: Set<String> = ["Spotify", "Music", "YouTube"]
    private static let nonWorkApps: Set<String> = ["WhatsApp", "Apple Music", "Music", "Spotify", "YouTube", "Finder", "Messages", "FaceTime", "Photos", "Preview"]

    private static func buildAppCards(summary: DaySummary, colors: [String: String]) -> String {
        summary.apps.enumerated().map { i, app -> String in
            let color = colors[app.appName] ?? "#6366f1"
            let pct = summary.totalSeconds > 0
                ? Double(app.totalSeconds) / Double(summary.totalSeconds) * 100 : 0
            let barWidth = summary.totalSeconds > 0
                ? Double(app.totalSeconds) / Double(summary.apps.first?.totalSeconds ?? 1) * 100 : 0
            let isMedia = mediaApps.contains(app.appName)

            let windowRows = app.windowDetails.prefix(12).map { w -> String in
                let wPct = app.totalSeconds > 0
                    ? Double(w.totalSeconds) / Double(app.totalSeconds) * 100 : 0
                let wBarWidth = app.windowDetails.first.map {
                    Double(w.totalSeconds) / Double($0.totalSeconds) * 100
                } ?? 0

                let title = esc(String(w.windowTitle.prefix(80)))

                // Build detail line (url and/or extraInfo)
                var detailParts: [String] = []
                if let extra = w.extraInfo, !extra.isEmpty {
                    detailParts.append("<span class=\"tag\">\(esc(extra))</span>")
                }
                if let url = w.url, !url.isEmpty {
                    detailParts.append(esc(String(url.prefix(70))))
                }
                let detailLine = detailParts.isEmpty ? "" :
                    "<div class=\"window-detail\">\(detailParts.joined(separator: " "))</div>"

                let idsJSON = w.activityIds.map { String($0) }.joined(separator: ",")

                let statsHTML: String
                if isMedia {
                    statsHTML = """
                        <div class="window-stats">
                            <button class="window-assign-btn" onclick="showWindowAssign(this)">Assign</button>
                        </div>
                    """
                } else {
                    statsHTML = """
                        <div class="window-stats">
                            <div class="window-bar-track">
                                <div class="window-bar-fill" style="width:\(String(format:"%.1f", wBarWidth))%;background:\(color)30"></div>
                            </div>
                            <span class="window-time">\(dur(w.totalSeconds))</span>
                            <span class="window-pct">\(String(format:"%.0f", wPct))%</span>
                            <button class="window-assign-btn" onclick="showWindowAssign(this)">Assign</button>
                        </div>
                    """
                }

                return """
                <div class="window-row" data-ids="[\(idsJSON)]">
                    <input type="checkbox" class="bulk-check" onchange="toggleBulkCheck(this)">
                    <div class="window-info">
                        <div class="window-title">\(title)</div>
                        \(detailLine)
                    </div>
                    \(statsHTML)
                </div>
                """
            }.joined(separator: "\n")

            return """
            <div class="app-card" id="app-\(i)">
                <div class="app-header">
                    <div class="app-name-row">
                        <span class="app-dot" style="background:\(color)"></span>
                        <span class="app-name">\(esc(app.appName))</span>
                    </div>
                    <div class="app-meta">
                        <span class="app-time">\(dur(app.totalSeconds))</span>
                        <span class="app-pct">\(String(format:"%.1f", pct))%</span>
                        <label class="select-all-wrap"><input type="checkbox" class="select-all-check" onchange="toggleSelectAll(this)">All</label>
                    </div>
                </div>
                <div class="app-bar-track">
                    <div class="app-bar-fill" style="width:\(String(format:"%.1f", barWidth))%;background:\(color)"></div>
                </div>
                <div class="windows-list">
                    \(windowRows)
                </div>
            </div>
            """
        }.joined(separator: "\n")
    }

    // MARK: - Donut Chart

    private static func buildDonutSegments(apps: [ActivitySummary], colors: [String: String]) -> String {
        guard !apps.isEmpty else { return "" }
        let total = apps.reduce(0) { $0 + $1.totalSeconds }
        guard total > 0 else { return "" }

        let radius: Double = 15.9155
        let circumference = 2 * Double.pi * radius
        var offset: Double = 25

        return apps.map { app -> String in
            let fraction = Double(app.totalSeconds) / Double(total)
            let dashLen = fraction * circumference
            let gap = circumference - dashLen
            let color = colors[app.appName] ?? "#6366f1"

            let segment = """
            <circle cx="18" cy="18" r="\(String(format:"%.4f", radius))"
                fill="none" stroke="\(color)" stroke-width="3.8"
                stroke-dasharray="\(String(format:"%.2f", dashLen)) \(String(format:"%.2f", gap))"
                stroke-dashoffset="\(String(format:"%.2f", -offset))"
                stroke-linecap="round"/>
            """
            offset += dashLen
            return segment
        }.joined(separator: "\n")
    }

    // MARK: - Timeline

    private static func buildTimelineHTML(timeline: [TimelineEntry], appColors: [String: String]) -> String {
        guard !timeline.isEmpty else { return "" }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var groups: [(app: String, entries: [(time: String, title: String, url: String?, extra: String?, dur: Int)])] = []

        for entry in timeline {
            let time = timeFormatter.string(from: entry.timestamp)
            let item = (time: time, title: entry.windowTitle, url: entry.url, extra: entry.extraInfo, dur: entry.durationSeconds)

            if let last = groups.last, last.app == entry.appName {
                groups[groups.count - 1].entries.append(item)
            } else {
                groups.append((app: entry.appName, entries: [item]))
            }
        }

        let groupsHTML = groups.map { group -> String in
            let color = appColors[group.app] ?? "#6366f1"
            let isMedia = mediaApps.contains(group.app)
            let entriesHTML = group.entries.map { e -> String in
                var extraLine = ""
                var parts: [String] = []
                if let extra = e.extra, !extra.isEmpty { parts.append(extra) }
                if let url = e.url, !url.isEmpty { parts.append(String(url.prefix(80))) }
                if !parts.isEmpty {
                    extraLine = "\n<div class=\"tl-extra\">\(esc(parts.joined(separator: " · ")))</div>"
                }
                let durSpan = isMedia ? "" : "<span class=\"tl-dur\">\(dur(e.dur))</span>"
                return """
                <div class="tl-entry">
                    <span class="tl-time">\(e.time)</span>
                    <span class="tl-title">\(esc(String(e.title.prefix(65))))</span>
                    \(durSpan)
                </div>\(extraLine)
                """
            }.joined(separator: "\n")

            return """
            <div class="tl-group">
                <div class="tl-app">
                    <span class="tl-dot" style="background:\(color)"></span>
                    \(esc(group.app))
                </div>
                \(entriesHTML)
            </div>
            """
        }.joined(separator: "\n")

        return """
        <div class="timeline" id="timeline">
            <div class="section-title">Timeline</div>
            \(groupsHTML)
        </div>
        """
    }

    // MARK: - Helpers

    static func dur(_ seconds: Int) -> String {
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

    private static func formatDateDisplay(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "EEEE, d MMMM yyyy"
        return display.string(from: date)
    }

    private static func esc(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - SPA Report

    static func generateSPA(apiPort: Int) -> URL {
        let fileURL = reportsDir.appendingPathComponent("report.html")
        let html = buildSPAHTML(apiPort: apiPort)
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func buildSPAHTML(apiPort: Int) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Pulse – Activity Report</title>
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif;
            background: #f8f9fb;
            color: #1a1a2e;
            min-height: 100vh;
            -webkit-font-smoothing: antialiased;
        }
        .layout { display: grid; grid-template-columns: 180px 1fr 320px; max-width: 1400px; margin: 0 auto; padding: 48px 24px 80px; gap: 32px; }
        .sidebar {
            position: sticky; top: 24px; height: fit-content;
            max-height: calc(100vh - 48px); overflow-y: auto;
            font-size: 13px;
        }
        .sidebar-section { margin-bottom: 20px; }
        .sidebar-heading {
            font-size: 11px; color: #8e8ea0; text-transform: uppercase;
            letter-spacing: 1.5px; font-weight: 600; margin-bottom: 8px; padding: 0 8px;
        }
        .sidebar a {
            display: flex; align-items: center; gap: 8px;
            text-decoration: none; color: #6b6b80; padding: 5px 8px;
            border-radius: 6px; transition: background 0.15s, color 0.15s;
            white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
            cursor: pointer;
        }
        .sidebar a:hover { background: #eef0f5; color: #1a1a2e; }
        .sidebar a.active { background: #eef0ff; color: #6366f1; font-weight: 600; }
        .sidebar .nav-dot { width: 8px; height: 8px; border-radius: 3px; flex-shrink: 0; }
        .sidebar .nav-time { font-size: 11px; color: #a0a0b0; margin-left: auto; flex-shrink: 0; }
        .sidebar .nav-divider { height: 1px; background: #e8e8ee; margin: 12px 8px; }

        .main-content { min-width: 0; }

        .right-panel {
            position: sticky; top: 24px; height: fit-content;
            max-height: calc(100vh - 48px); overflow-y: auto;
            font-size: 13px;
        }
        .right-panel-title {
            font-size: 12px; color: #8e8ea0; text-transform: uppercase;
            letter-spacing: 1.5px; font-weight: 600; margin-bottom: 12px;
        }
        .right-panel .unassigned-section { border-radius: 12px; padding: 16px; margin-bottom: 12px; }
        .right-panel .unassigned-row { flex-wrap: wrap; gap: 8px; padding: 8px 10px; }
        .right-panel .unassigned-app { width: auto; font-size: 12px; }
        .right-panel .unassigned-detail { font-size: 11px; flex-basis: 100%; }
        .right-panel .unassigned-dur { font-size: 12px; width: auto; }
        .right-panel .unassigned-select { width: 100%; min-width: 0; font-size: 11px; margin-top: 4px; }
        .right-panel .unassigned-save-btn { font-size: 10px; padding: 3px 8px; }
        .right-panel .unassigned-rule-check { font-size: 10px; }
        .right-panel .suggestion-card { padding: 12px 14px; }
        .right-panel .suggestion-card-name { font-size: 13px; }
        .right-panel .suggestion-card-apps { font-size: 10px; }
        .right-panel .suggestion-rule-tag { font-size: 9px; }
        .right-panel .suggestion-card-actions { flex-wrap: wrap; }
        .right-panel .suggestion-btn-create, .right-panel .suggestion-btn-assign, .right-panel .suggestion-btn-dismiss { font-size: 11px; padding: 4px 10px; }
        .right-panel .suggestions-container { margin-bottom: 16px; }

        .header { margin-bottom: 32px; }
        .header-label { font-size: 12px; color: #8e8ea0; text-transform: uppercase; letter-spacing: 2px; font-weight: 600; margin-bottom: 8px; }
        .header-date { font-size: 30px; font-weight: 700; color: #1a1a2e; margin-bottom: 6px; display: flex; align-items: center; gap: 12px; }
        .header-total { font-size: 15px; color: #6b6b80; }
        .header-total strong { color: #1a1a2e; font-weight: 700; }
        .nav-arrow {
            width: 32px; height: 32px; border-radius: 8px; border: 1px solid #e0e0e8;
            background: #fff; cursor: pointer; display: flex; align-items: center; justify-content: center;
            font-size: 16px; color: #6b6b80; transition: background 0.15s, color 0.15s; flex-shrink: 0;
        }
        .nav-arrow:hover { background: #eef0ff; color: #6366f1; }

        .view-tabs { display: flex; gap: 4px; margin-bottom: 24px; }
        .view-tab {
            padding: 6px 16px; border-radius: 8px; font-size: 13px; font-weight: 600;
            background: #f0f0f5; color: #6b6b80; border: none; cursor: pointer;
            transition: background 0.15s, color 0.15s;
        }
        .view-tab:hover { background: #e4e4ef; }
        .view-tab.active { background: #6366f1; color: #fff; }

        .metric-cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 32px; }
        .metric-card {
            background: #fff; border-radius: 12px; padding: 16px 20px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06);
        }
        .metric-label { font-size: 11px; color: #8e8ea0; text-transform: uppercase; letter-spacing: 1px; font-weight: 600; margin-bottom: 6px; }
        .metric-value { font-size: 22px; font-weight: 700; color: #1a1a2e; }
        .metric-sub { font-size: 12px; color: #a0a0b0; margin-top: 2px; }

        .overview { display: grid; grid-template-columns: 220px 1fr; gap: 20px; margin-bottom: 44px; align-items: start; }
        .overview-chart {
            background: #fff; border-radius: 16px; padding: 28px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); display:flex; align-items:center; justify-content:center;
        }
        .overview-stats {
            background: #fff; border-radius: 16px; padding: 24px 28px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); display:flex; flex-direction:column; gap:10px;
        }
        .stat-row { display:flex; align-items:center; gap:10px; }
        .stat-dot { width:10px; height:10px; border-radius:50%; flex-shrink:0; }
        .stat-name { flex:1; font-size:14px; color:#6b6b80; }
        .stat-value { font-size:14px; font-weight:600; color:#1a1a2e; min-width:60px; text-align:right; }
        .stat-pct { font-size:12px; color:#a0a0b0; width:40px; text-align:right; }

        .donut-container { position:relative; width:160px; height:160px; }
        .donut-center { position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); text-align:center; }
        .donut-total { font-size:20px; font-weight:700; color:#1a1a2e; }
        .donut-label { font-size:11px; color:#a0a0b0; }

        .section-title {
            font-size: 12px; color: #8e8ea0; text-transform: uppercase;
            letter-spacing: 2px; font-weight: 600; margin-bottom: 16px; margin-top: 8px;
        }

        .app-card {
            background: #fff; border-radius: 14px; padding: 20px 24px; margin-bottom: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); scroll-margin-top: 24px;
        }
        .app-header { display:flex; justify-content:space-between; align-items:center; margin-bottom: 12px; }
        .app-name-row { display:flex; align-items:center; gap:10px; }
        .app-dot { width:12px; height:12px; border-radius:4px; flex-shrink:0; }
        .app-name { font-size:16px; font-weight:600; color:#1a1a2e; }
        .app-meta { display:flex; align-items:baseline; gap:10px; }
        .app-time { font-size:16px; font-weight:700; color:#1a1a2e; }
        .app-pct { font-size:13px; color:#a0a0b0; }
        .app-bar-track { height:5px; background:#f0f0f5; border-radius:3px; margin-bottom:16px; }
        .app-bar-fill { height:100%; border-radius:3px; }

        .windows-list { display:flex; flex-direction:column; gap:6px; }
        .window-row {
            display:flex; justify-content:space-between; align-items:center;
            padding:10px 14px; background:#f8f9fb; border-radius:10px; gap:16px;
        }
        .window-info { flex:1; min-width:0; }
        .window-title { font-size:13px; color:#1a1a2e; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; font-weight:500; }
        .window-detail { font-size:11px; color:#8e8ea0; margin-top:2px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .window-detail .tag { display:inline-block; background:#eef0ff; color:#6366f1; font-size:10px; font-weight:600; padding:1px 6px; border-radius:4px; margin-right:4px; }
        .window-stats { display:flex; align-items:center; gap:10px; flex-shrink:0; }
        .window-bar-track { width:56px; height:4px; background:#eee; border-radius:2px; }
        .window-bar-fill { height:100%; border-radius:2px; }
        .window-time { font-size:13px; font-weight:600; color:#1a1a2e; width:60px; text-align:right; }
        .window-pct { font-size:11px; color:#a0a0b0; width:36px; text-align:right; }
        .window-assign-btn {
            opacity:0; padding:3px 10px; border-radius:5px; font-size:11px; font-weight:600;
            background:#eef0ff; color:#6366f1; border:1px solid #d4d4f8; cursor:pointer;
            transition:opacity .15s, background .1s; white-space:nowrap;
        }
        .window-row:hover .window-assign-btn { opacity:1; }
        .window-assign-btn:hover { background:#dde0ff; }

        /* Bulk Selection */
        .bulk-check {
            width:16px; height:16px; accent-color:#6366f1; cursor:pointer; flex-shrink:0;
            margin:0; border-radius:3px;
        }
        .window-row.selected { background:#eef0ff; }
        .select-all-wrap {
            display:flex; align-items:center; gap:5px; cursor:pointer; font-size:11px; color:#a0a0b0;
            user-select:none; margin-left:auto;
        }
        .select-all-wrap input { margin:0; }
        .bulk-bar {
            position:fixed; bottom:0; left:0; right:0; z-index:1000;
            background:#1a1a2e; color:#fff; padding:12px 24px;
            display:none; align-items:center; gap:16px; justify-content:center;
            box-shadow:0 -4px 20px rgba(0,0,0,0.15);
            animation:slideUp .2s ease;
        }
        .bulk-bar.visible { display:flex; }
        @keyframes slideUp { from{transform:translateY(100%)} to{transform:translateY(0)} }
        .bulk-bar .bulk-count { font-size:13px; font-weight:600; white-space:nowrap; }
        .bulk-bar select {
            padding:6px 10px; border-radius:6px; border:1px solid #444;
            background:#2a2a3e; color:#fff; font-size:12px; min-width:180px;
        }
        .bulk-bar .bulk-assign-btn {
            padding:6px 16px; border-radius:6px; font-size:12px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer;
        }
        .bulk-bar .bulk-assign-btn:hover { background:#4f46e5; }
        .bulk-bar .bulk-assign-btn:disabled { opacity:0.5; cursor:default; }
        .bulk-bar .bulk-rule-label { display:flex; align-items:center; gap:4px; font-size:11px; color:#a0a0b0; }
        .bulk-bar .bulk-rule-label input { margin:0; }
        .bulk-bar .bulk-clear-btn {
            padding:6px 12px; border-radius:6px; font-size:12px; font-weight:500;
            background:#333; color:#ccc; border:1px solid #555; cursor:pointer;
        }
        .bulk-bar .bulk-clear-btn:hover { background:#444; }
        .window-assign-popup {
            display:flex; align-items:center; gap:6px; margin-top:6px;
            padding:6px 10px; background:#f0f0ff; border-radius:8px; animation:fadeIn .1s;
        }
        @keyframes fadeIn { from{opacity:0;transform:translateY(-4px)} to{opacity:1;transform:translateY(0)} }
        .window-assign-popup select { font-size:12px; padding:3px 6px; border:1px solid #d0d0e0; border-radius:5px; background:#fff; color:#1a1a2e; }
        .window-assign-popup .wa-save { padding:3px 10px; border-radius:5px; font-size:11px; font-weight:600; background:#6366f1; color:#fff; border:none; cursor:pointer; }
        .window-assign-popup .wa-save:hover { background:#4f46e5; }
        .window-assign-popup .wa-cancel { padding:3px 8px; border-radius:5px; font-size:11px; background:#e8e8ee; color:#6b6b80; border:none; cursor:pointer; }
        .window-assign-popup .wa-rule { display:flex; align-items:center; gap:3px; font-size:11px; color:#8e8ea0; }
        .window-assign-popup .wa-rule input { margin:0; }

        .timeline { margin-top:44px; scroll-margin-top: 24px; }
        .tl-group { margin-bottom:16px; }
        .tl-app { font-size:14px; font-weight:600; color:#1a1a2e; display:flex; align-items:center; gap:8px; margin-bottom:6px; }
        .tl-dot { width:8px; height:8px; border-radius:50%; }
        .tl-entry { display:flex; align-items:baseline; gap:12px; padding:3px 0 3px 20px; font-size:13px; }
        .tl-time { color:#a0a0b0; font-variant-numeric:tabular-nums; width:48px; flex-shrink:0; font-size:12px; }
        .tl-title { color:#4a4a5a; flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .tl-extra { color:#8e8ea0; font-size:11px; padding:0 0 2px 80px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .tl-dur { color:#6b6b80; flex-shrink:0; font-weight:500; }

        .json-btn {
            display:inline-flex; align-items:center; gap:6px;
            padding:7px 14px; border-radius:8px; font-size:12px; font-weight:600;
            background:#f0f0f5; color:#6366f1; border:none; cursor:pointer;
            text-decoration:none; transition:background .15s;
        }
        .json-btn:hover { background:#e4e4ef; }
        .json-btn[style*="6366f1"]:hover { background:#4f46e5 !important; }
        .json-btn svg { width:14px; height:14px; }

        .analysis-section {
            background: #fff; border-radius: 14px; padding: 24px 28px; margin-bottom: 32px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06); border-left: 3px solid #6366f1;
            scroll-margin-top: 24px;
        }
        .analysis-header { display:flex; align-items:center; gap:10px; margin-bottom:16px; }
        .analysis-icon {
            width:32px; height:32px; border-radius:8px; background:linear-gradient(135deg,#6366f1,#8b5cf6);
            display:flex; align-items:center; justify-content:center; flex-shrink:0;
        }
        .analysis-icon svg { width:16px; height:16px; }
        .analysis-title { font-size:16px; font-weight:700; color:#1a1a2e; }
        .analysis-badge { font-size:10px; font-weight:600; padding:2px 8px; border-radius:4px; background:#eef0ff; color:#6366f1; }
        .analysis-body { font-size:13px; color:#4a4a5a; line-height:1.7; }
        .analysis-body h2 { font-size:15px; font-weight:700; color:#1a1a2e; margin:20px 0 10px; }
        .analysis-body h2:first-child { margin-top:0; }
        .analysis-body h3 { font-size:14px; font-weight:700; color:#6366f1; margin:16px 0 6px; }
        .analysis-body .project-total { font-size:13px; font-weight:600; color:#1a1a2e; margin-bottom:4px; }
        .analysis-body ul { list-style:none; padding:0; margin:0 0 8px; }
        .analysis-body li { padding:3px 0 3px 16px; position:relative; }
        .analysis-body li::before { content:''; position:absolute; left:4px; top:10px; width:5px; height:5px; border-radius:50%; background:#c4c7d4; }
        .analysis-body p { margin:4px 0; }

        /* Projects Section */
        .projects-section { margin-bottom: 44px; scroll-margin-top: 24px; }
        .brand-bar-container { background:#fff; border-radius:14px; padding:20px 24px; margin-bottom:16px; box-shadow:0 1px 3px rgba(0,0,0,0.06); }
        .brand-stacked-bar { display:flex; height:28px; border-radius:8px; overflow:hidden; background:#f0f0f5; margin-bottom:12px; }
        .brand-stacked-segment { display:flex; align-items:center; justify-content:center; color:#fff; font-size:10px; font-weight:700; cursor:default; transition:opacity .15s; min-width:2px; }
        .brand-stacked-segment:hover { opacity:0.85; }
        .brand-bar-legend { display:flex; flex-wrap:wrap; gap:12px; }
        .brand-legend-item { display:flex; align-items:center; gap:6px; font-size:12px; color:#6b6b80; }
        .brand-legend-dot { width:8px; height:8px; border-radius:50%; flex-shrink:0; }

        .brand-card {
            background:#fff; border-radius:14px; margin-bottom:12px; box-shadow:0 1px 3px rgba(0,0,0,0.06); overflow:hidden;
        }
        .brand-card-header {
            display:flex; justify-content:space-between; align-items:center; padding:16px 24px;
            cursor:pointer; user-select:none; transition:background .15s;
        }
        .brand-card-header:hover { background:#fafafe; }
        .brand-card-left { display:flex; align-items:center; gap:10px; }
        .brand-color-bar { width:4px; height:24px; border-radius:2px; }
        .brand-card-name { font-size:15px; font-weight:600; color:#1a1a2e; }
        .brand-card-right { display:flex; align-items:center; gap:12px; }
        .brand-card-time { font-size:15px; font-weight:700; color:#1a1a2e; }
        .brand-card-pct { font-size:12px; color:#a0a0b0; }
        .brand-card-chevron { color:#a0a0b0; transition:transform .2s; font-size:14px; }
        .brand-card-body { padding:0 24px 16px; display:none; }
        .brand-card.open .brand-card-body { display:block; }
        .brand-card.open .brand-card-chevron { transform:rotate(90deg); }

        .proj-row {
            display:flex; justify-content:space-between; align-items:center;
            padding:10px 14px; background:#f8f9fb; border-radius:10px; margin-bottom:6px; gap:16px;
        }
        .proj-info { flex:1; min-width:0; }
        .proj-name { font-size:13px; font-weight:600; color:#1a1a2e; }
        .proj-apps { font-size:11px; color:#8e8ea0; margin-top:2px; }
        .proj-stats { display:flex; align-items:center; gap:10px; flex-shrink:0; }
        .proj-bar-track { width:56px; height:4px; background:#eee; border-radius:2px; }
        .proj-bar-fill { height:100%; border-radius:2px; }
        .proj-time { font-size:13px; font-weight:600; color:#1a1a2e; width:60px; text-align:right; }
        .proj-pct { font-size:11px; color:#a0a0b0; width:36px; text-align:right; }

        /* Unassigned Table */
        .unassigned-section { background:#fff; border-radius:14px; padding:20px 24px; margin-top:16px; box-shadow:0 1px 3px rgba(0,0,0,0.06); border-left:3px solid #f59e0b; }
        .unassigned-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; }
        .unassigned-title { font-size:14px; font-weight:700; color:#1a1a2e; }
        .unassigned-count { font-size:12px; color:#a0a0b0; }
        .unassigned-row {
            display:flex; align-items:center; gap:12px; padding:8px 0; border-bottom:1px solid #f0f0f5; font-size:13px;
        }
        .unassigned-row:last-child { border-bottom:none; }
        .unassigned-app { font-weight:600; color:#1a1a2e; width:100px; flex-shrink:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .unassigned-detail { flex:1; min-width:0; color:#6b6b80; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .unassigned-dur { font-weight:600; color:#1a1a2e; width:60px; text-align:right; flex-shrink:0; }
        .unassigned-select { width:160px; flex-shrink:0; font-size:12px; padding:4px 8px; border:1px solid #e0e0e8; border-radius:6px; background:#fff; color:#1a1a2e; }
        .unassigned-save-btn {
            padding:4px 12px; border-radius:6px; font-size:11px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer; flex-shrink:0;
        }
        .unassigned-save-btn:hover { background:#4f46e5; }
        .unassigned-save-btn:disabled { background:#c0c0c8; cursor:default; }
        .unassigned-save-all {
            display:inline-flex; align-items:center; gap:6px;
            padding:7px 14px; border-radius:8px; font-size:12px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer; margin-top:12px;
        }
        .unassigned-save-all:hover { background:#4f46e5; }
        .unassigned-api-error { color:#ef4444; font-size:12px; margin-top:8px; display:none; }
        .unassigned-rule-check { display:flex; align-items:center; gap:4px; font-size:11px; color:#8e8ea0; flex-shrink:0; }
        .unassigned-rule-check input { margin:0; }

        /* Create Entity Bar & Modal */
        .create-entity-bar { display:flex; gap:8px; }
        .create-entity-btn {
            display:inline-flex; align-items:center; gap:4px;
            padding:5px 12px; border-radius:6px; font-size:12px; font-weight:600;
            background:#f0f0f5; color:#6366f1; border:1px solid #e0e0e8; cursor:pointer;
            transition:background .15s, border-color .15s;
        }
        .create-entity-btn:hover { background:#eef0ff; border-color:#c7c7f4; }
        .create-modal-overlay {
            position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.3);
            display:flex; align-items:center; justify-content:center; z-index:1000;
        }
        .create-modal {
            background:#fff; border-radius:16px; padding:28px 32px; width:420px; max-width:90vw;
            box-shadow:0 20px 60px rgba(0,0,0,0.15); animation:modalIn .15s ease-out;
        }
        @keyframes modalIn { from { opacity:0; transform:scale(0.95); } to { opacity:1; transform:scale(1); } }
        .create-modal h3 { font-size:16px; font-weight:700; color:#1a1a2e; margin-bottom:20px; }
        .create-form { display:flex; flex-direction:column; gap:14px; }
        .create-form label { font-size:12px; font-weight:600; color:#6b6b80; text-transform:uppercase; letter-spacing:0.5px; }
        .create-form input[type="text"], .create-form select {
            width:100%; padding:8px 12px; border:1px solid #e0e0e8; border-radius:8px;
            font-size:14px; color:#1a1a2e; background:#fff; outline:none; transition:border-color .15s;
        }
        .create-form input[type="text"]:focus, .create-form select:focus { border-color:#6366f1; }
        .color-picker { display:flex; gap:8px; flex-wrap:wrap; margin-top:4px; }
        .color-swatch {
            width:28px; height:28px; border-radius:50%; border:3px solid transparent; cursor:pointer;
            transition:border-color .15s, transform .1s;
        }
        .color-swatch:hover { transform:scale(1.1); }
        .color-swatch.selected { border-color:#1a1a2e; }
        .create-form-actions { display:flex; justify-content:flex-end; gap:8px; margin-top:8px; }
        .create-form-actions button {
            padding:8px 20px; border-radius:8px; font-size:13px; font-weight:600; cursor:pointer; border:none;
        }
        .btn-cancel { background:#f0f0f5; color:#6b6b80; }
        .btn-cancel:hover { background:#e4e4ef; }
        .btn-create { background:#6366f1; color:#fff; }
        .btn-create:hover { background:#4f46e5; }
        .btn-create:disabled { background:#c0c0c8; cursor:default; }
        .create-form-error { color:#ef4444; font-size:12px; display:none; }

        /* Suggestion Cards */
        .suggestions-container { margin-bottom:20px; }
        .suggestions-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; }
        .suggestions-title { font-size:14px; font-weight:700; color:#1a1a2e; }
        .suggestions-badge { font-size:10px; font-weight:600; padding:2px 8px; border-radius:4px; background:#fef3c7; color:#b45309; }
        .suggestion-card {
            background:#fff; border-radius:12px; padding:16px 20px; margin-bottom:10px;
            box-shadow:0 1px 3px rgba(0,0,0,0.06); border-left:3px solid #f59e0b;
            transition:opacity .3s, max-height .3s;
        }
        .suggestion-card.dismissed { opacity:0; max-height:0; overflow:hidden; padding:0 20px; margin:0; border:none; }
        .suggestion-card-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; }
        .suggestion-card-name { font-size:15px; font-weight:600; color:#1a1a2e; }
        .suggestion-card-meta { font-size:12px; color:#8e8ea0; }
        .suggestion-card-apps { font-size:11px; color:#8e8ea0; margin-bottom:8px; }
        .suggestion-card-rules { display:flex; flex-wrap:wrap; gap:4px; margin-bottom:10px; }
        .suggestion-rule-tag { display:inline-block; font-size:10px; font-weight:600; padding:2px 8px; border-radius:4px; background:#f0f0f5; color:#6b6b80; }
        .suggestion-card-actions { display:flex; align-items:center; gap:8px; }
        .suggestion-btn-create {
            padding:5px 14px; border-radius:6px; font-size:12px; font-weight:600;
            background:#6366f1; color:#fff; border:none; cursor:pointer;
        }
        .suggestion-btn-create:hover { background:#4f46e5; }
        .suggestion-btn-assign {
            padding:5px 10px; border-radius:6px; font-size:12px; font-weight:600;
            background:#f0f0f5; color:#6366f1; border:1px solid #d4d4f8; cursor:pointer;
        }
        .suggestion-btn-assign:hover { background:#eef0ff; }
        .suggestion-btn-dismiss {
            padding:5px 10px; border-radius:6px; font-size:12px;
            background:transparent; color:#a0a0b0; border:1px solid #e8e8ee; cursor:pointer; margin-left:auto;
        }
        .suggestion-btn-dismiss:hover { background:#f8f8fa; color:#6b6b80; }
        .suggestion-assign-row { display:flex; align-items:center; gap:6px; margin-top:8px; animation:fadeIn .15s; }
        .suggestion-assign-select { font-size:12px; padding:4px 8px; border:1px solid #e0e0e8; border-radius:6px; background:#fff; color:#1a1a2e; }
        .suggestion-loading { text-align:center; padding:20px; color:#a0a0b0; font-size:13px; }

        .footer { margin-top:60px; text-align:center; font-size:12px; color:#c0c0c8; }

        /* Management forms */
        .mgmt-card { background:#fff; border-radius:14px; padding:20px 24px; margin-bottom:16px; box-shadow:0 1px 3px rgba(0,0,0,0.06); }
        .mgmt-card-header { display:flex; align-items:center; justify-content:space-between; margin-bottom:12px; }
        .mgmt-card-title { font-size:15px; font-weight:700; color:#1a1a2e; display:flex; align-items:center; gap:8px; }
        .mgmt-row { display:flex; align-items:center; gap:10px; padding:8px 0; border-bottom:1px solid #f0f0f5; }
        .mgmt-row:last-child { border-bottom:none; }
        .mgmt-color { width:20px; height:20px; border-radius:5px; cursor:pointer; border:2px solid transparent; flex-shrink:0; }
        .mgmt-color:hover { border-color:#6366f1; }
        .mgmt-name { flex:1; font-size:13px; color:#1a1a2e; font-weight:500; }
        .mgmt-input { flex:1; font-size:13px; padding:6px 10px; border:1px solid #e0e0e8; border-radius:6px; background:#fafafc; color:#1a1a2e; outline:none; }
        .mgmt-input:focus { border-color:#6366f1; background:#fff; }
        .mgmt-color-input { width:32px; height:28px; border:1px solid #e0e0e8; border-radius:6px; cursor:pointer; padding:1px; background:#fff; }
        .mgmt-btn { padding:5px 12px; border-radius:6px; font-size:12px; font-weight:600; border:none; cursor:pointer; transition:background .15s; }
        .mgmt-btn-primary { background:#6366f1; color:#fff; }
        .mgmt-btn-primary:hover { background:#4f46e5; }
        .mgmt-btn-danger { background:#fee2e2; color:#ef4444; }
        .mgmt-btn-danger:hover { background:#fca5a5; color:#991b1b; }
        .mgmt-btn-ghost { background:transparent; color:#8e8ea0; }
        .mgmt-btn-ghost:hover { background:#f0f0f5; color:#1a1a2e; }
        .mgmt-add-row { display:flex; gap:8px; margin-top:12px; }
        .mgmt-sub-list { margin-left:28px; }
        .mgmt-badge { font-size:11px; color:#8e8ea0; background:#f0f0f5; padding:2px 8px; border-radius:99px; }
        .mgmt-empty { color:#a0a0b0; font-size:13px; padding:12px 0; text-align:center; }
        .mgmt-toast { position:fixed; bottom:80px; left:50%; transform:translateX(-50%); background:#1a1a2e; color:#fff; padding:10px 20px; border-radius:10px; font-size:13px; font-weight:500; z-index:999; opacity:0; transition:opacity .3s; pointer-events:none; }
        .mgmt-toast.show { opacity:1; }

        /* Week/Month charts */
        .week-chart { background:#fff; border-radius:14px; padding:20px 24px; margin-bottom:24px; box-shadow:0 1px 3px rgba(0,0,0,0.06); }
        .week-bars { display:flex; align-items:flex-end; gap:8px; height:160px; padding-top:8px; }
        .week-bar-col { flex:1; display:flex; flex-direction:column; align-items:center; gap:4px; height:100%; justify-content:flex-end; }
        .week-bar {
            width:100%; border-radius:6px 6px 0 0; background:#6366f1; min-height:2px;
            cursor:pointer; transition:opacity .15s;
        }
        .week-bar:hover { opacity:0.8; }
        .week-bar-label { font-size:11px; color:#8e8ea0; }
        .week-bar-value { font-size:10px; color:#6b6b80; font-weight:600; }
        .week-day-cards { display:grid; grid-template-columns:repeat(auto-fill, minmax(180px,1fr)); gap:12px; }
        .week-day-card {
            background:#fff; border-radius:12px; padding:14px 18px; box-shadow:0 1px 3px rgba(0,0,0,0.06);
            cursor:pointer; transition:background .15s, box-shadow .15s;
        }
        .week-day-card:hover { background:#eef0ff; box-shadow:0 2px 8px rgba(99,102,241,0.15); }
        .week-day-card-date { font-size:13px; font-weight:600; color:#1a1a2e; margin-bottom:4px; }
        .week-day-card-time { font-size:18px; font-weight:700; color:#6366f1; }
        .week-day-card-apps { font-size:11px; color:#8e8ea0; margin-top:4px; }

        .month-grid { display:grid; grid-template-columns:repeat(7,1fr); gap:4px; margin-bottom:24px; }
        .month-grid-header { font-size:11px; color:#8e8ea0; text-align:center; padding:4px; font-weight:600; }
        .month-cell {
            aspect-ratio:1; border-radius:6px; display:flex; align-items:center; justify-content:center;
            font-size:11px; cursor:pointer; transition:transform .1s;
        }
        .month-cell:hover { transform:scale(1.1); }
        .month-cell.empty { cursor:default; }
        .month-cell.empty:hover { transform:none; }

        .loading-spinner {
            display:flex; align-items:center; justify-content:center; padding:60px;
            color:#a0a0b0; font-size:14px;
        }
        @keyframes spin { from{transform:rotate(0)} to{transform:rotate(360deg)} }

        @media (max-width:1100px) {
            .layout { grid-template-columns: 1fr 300px; }
            .layout .sidebar { display: none; }
        }
        @media (max-width:900px) {
            .layout { grid-template-columns: 1fr; }
            .sidebar { display: none; }
            .right-panel { position: static; max-height: none; }
        }
        @media (max-width:640px) {
            .overview { grid-template-columns:1fr; }
            .layout { padding:24px 16px 60px; }
            .metric-cards { grid-template-columns:1fr; }
        }
        </style>
        </head>
        <body>

        <div class="layout">
            <nav class="sidebar" id="sidebar-nav"></nav>
            <div class="main-content" id="main-content">
                <div class="loading-spinner" id="loading">
                    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg>
                    &nbsp; Loading report...
                </div>
            </div>
            <div class="right-panel" id="right-panel"></div>
        </div>

        <div id="bulk-bar" class="bulk-bar">
            <span id="bulk-count" class="bulk-count">0 items selected</span>
            <select id="bulk-project-select"><option value="">Loading projects...</option></select>
            <button id="bulk-assign-btn" class="bulk-assign-btn" onclick="bulkAssign()">Assign All</button>
            <button class="bulk-clear-btn" onclick="clearBulkSelection()">Clear</button>
        </div>

        <script>
        var API_PORT = \(apiPort);
        var API_BASE = 'http://127.0.0.1:' + API_PORT;
        var __projectData = {brands:[], projects:[]};
        var __reportData = {};
        var currentDate = '';
        var currentView = 'day'; // 'day','week','month'
        var currentMonth = new Date().getMonth() + 1;
        var currentYear = new Date().getFullYear();

        var APP_COLORS = [
            '#6366f1','#f59e0b','#10b981','#ef4444','#8b5cf6',
            '#ec4899','#14b8a6','#f97316','#06b6d4','#84cc16'
        ];
        var MEDIA_APPS = ['Spotify','Music','YouTube'];
        var NON_WORK_APPS = ['WhatsApp','Apple Music','Music','Spotify','YouTube','Finder','Messages','FaceTime','Photos','Preview'];
        var DAY_NAMES = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
        var MONTH_NAMES = ['January','February','March','April','May','June','July','August','September','October','November','December'];

        // ---- Helpers ----
        function dur(s) {
            if (!s || s <= 0) return '0s';
            if (s < 60) return s + 's';
            if (s < 3600) { var m = Math.floor(s/60), r = s%60; return r > 0 ? m+'m '+r+'s' : m+'m'; }
            var h = Math.floor(s/3600), m = Math.floor((s%3600)/60);
            return m > 0 ? h+'h '+m+'m' : h+'h';
        }
        function esc(s) { if (!s) return ''; return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
        function escA(s) { return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;'); }
        function formatDateDisplay(ds) {
            if (!ds) return '';
            var parts = ds.split('-');
            var d = new Date(parseInt(parts[0]), parseInt(parts[1])-1, parseInt(parts[2]));
            var days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
            var months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
            return days[d.getDay()] + ', ' + d.getDate() + ' ' + months[d.getMonth()] + ' ' + d.getFullYear();
        }
        function prevDay(ds) { var p = ds.split('-'); var d = new Date(+p[0],+p[1]-1,+p[2]); d.setDate(d.getDate()-1); return fmt(d); }
        function nextDay(ds) { var p = ds.split('-'); var d = new Date(+p[0],+p[1]-1,+p[2]); d.setDate(d.getDate()+1); return fmt(d); }
        function fmt(d) { return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); }
        function today() { return fmt(new Date()); }

        function apiCall(path, body) {
            return fetch(API_BASE + path, {
                method: body ? 'POST' : 'GET',
                headers: {'Content-Type':'application/json'},
                body: body ? JSON.stringify(body) : undefined
            }).then(function(r) { return r.json(); });
        }

        // Resolve "new:brandId" values by creating a project first, returns Promise<int>
        function resolveProjectId(val) {
            if (typeof val === 'string' && val.indexOf('new:') === 0) {
                var brandId = parseInt(val.substring(4));
                var brandName = '';
                (__projectData.brands || []).forEach(function(b) { if (b.id === brandId) brandName = b.name; });
                var projName = prompt('New project name for "'+brandName+'":', brandName);
                if (!projName) return Promise.reject(new Error('Cancelled'));
                return apiCall('/api/project', {brandId: brandId, name: projName, color: '#6366f1'}).then(function(res) {
                    if (res.id) {
                        __projectData.projects.push({id:res.id, brandId:brandId, brandName:brandName, name:projName, color:'#6366f1'});
                        return res.id;
                    }
                    throw new Error(res.error || 'Failed to create project');
                });
            }
            var pid = parseInt(val);
            if (!pid || isNaN(pid)) return Promise.reject(new Error('No project selected'));
            return Promise.resolve(pid);
        }

        function buildProjectOptions(brands, projects) {
            var optHTML = '<option value="">Select project...</option>';
            var bMap = {};
            (brands||[]).forEach(function(b){bMap[b.id]={name:b.name,projects:[]};});
            (projects||[]).forEach(function(p){if(bMap[p.brandId])bMap[p.brandId].projects.push(p);});
            Object.keys(bMap).sort().forEach(function(bid){
                var e=bMap[bid];
                optHTML+='<optgroup label="'+esc(e.name)+'">';
                e.projects.forEach(function(p){optHTML+='<option value="'+p.id+'">'+esc(p.name)+'</option>';});
                optHTML+='<option value="new:'+bid+'">+ New project</option>';
                optHTML+='</optgroup>';
            });
            return optHTML;
        }

        // ---- Page Init ----
        var INITIAL_DATE = null;
        (function() {
            if (INITIAL_DATE) {
                currentDate = INITIAL_DATE;
                loadDay(INITIAL_DATE);
                return;
            }
            apiCall('/api/days').then(function(res) {
                var dates = res.dates || [];
                var dateToLoad = dates.length > 0 ? dates[0] : today();
                currentDate = dateToLoad;
                loadDay(dateToLoad);
            }).catch(function() {
                currentDate = today();
                loadDay(today());
            });
        })();

        // ---- Day View ----
        function loadDay(dateStr) {
            currentDate = dateStr;
            currentView = 'day';
            var main = document.getElementById('main-content');
            main.innerHTML = '<div class="loading-spinner"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg>&nbsp; Loading...</div>';

            apiCall('/api/report?date=' + dateStr).then(function(res) {
                var summary = res.summary || {};
                var timeline = res.timeline || [];
                var brandSummaries = res.brandSummaries || [];
                var unassigned = res.unassigned || [];
                var brands = res.brands || [];
                var projects = res.projects || [];
                var assignedIds = {};
                (res.assignedIds || []).forEach(function(id){ assignedIds[id] = true; });
                __projectData = {brands:brands, projects:projects};
                __reportData = {date:summary.date, totalSeconds:summary.totalSeconds, wallClockSeconds:summary.wallClockSeconds, firstActivity:summary.firstActivity, lastActivity:summary.lastActivity, timeline:timeline};

                renderDayView(summary, timeline, brandSummaries, unassigned, brands, projects, assignedIds);
                renderSidebar(summary);
                renderRightPanel(unassigned, brands, projects);
                loadSuggestions();
                refreshBulkBarDropdown();
            }).catch(function(e) {
                main.innerHTML = '<div class="loading-spinner" style="color:#ef4444">Cannot connect to Pulse. Make sure it is running on port '+API_PORT+'.</div>';
            });
        }

        function renderDayView(summary, timeline, brandSummaries, unassigned, brands, projects, assignedIds) {
            assignedIds = assignedIds || {};
            var apps = summary.apps || [];
            var totalSec = summary.totalSeconds || 0;
            var colors = {};
            apps.forEach(function(a,i){ colors[a.appName] = APP_COLORS[i % APP_COLORS.length]; });

            var html = '';
            // Header
            html += '<div class="header" id="overview">';
            html += '<div class="header-label">Activity Report</div>';
            html += '<div class="header-date">';
            html += '<button class="nav-arrow" onclick="loadDay(prevDay(currentDate))" title="Previous day">&#9664;</button>';
            html += '<span>' + formatDateDisplay(summary.date) + '</span>';
            html += '<button class="nav-arrow" onclick="loadDay(nextDay(currentDate))" title="Next day">&#9654;</button>';
            html += '</div>';
            html += '<div class="header-total">Total active time <strong>' + dur(totalSec) + '</strong> across <strong>' + apps.length + '</strong> app' + (apps.length===1?'':'s') + '</div>';
            html += '<div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap">';
            html += '<button onclick="downloadJSON()" class="json-btn"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2v8m0 0l-3-3m3 3l3-3M3 12h10"/></svg> Download JSON</button>';
            html += '<button onclick="analyzeWithAI()" class="json-btn" id="analyze-btn" style="background:#6366f1;color:#fff"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg> Analyze with AI</button>';
            html += '</div></div>';

            // View Tabs
            html += '<div class="view-tabs">';
            html += '<button class="view-tab active" onclick="switchView(\\x27day\\x27)">Day</button>';
            html += '<button class="view-tab" onclick="switchView(\\x27week\\x27)">Week</button>';
            html += '<button class="view-tab" onclick="switchView(\\x27month\\x27)">Month</button>';
            html += '</div>';

            // Metrics
            var wallTime = dur(summary.wallClockSeconds || 0);
            var trackTime = dur(summary.activeTrackingSeconds || 0);
            var timeRange = (summary.firstActivity && summary.lastActivity) ? summary.firstActivity + ' \\u2013 ' + summary.lastActivity : '\\u2013';
            html += '<div class="metric-cards">';
            html += '<div class="metric-card"><div class="metric-label">Wall Clock</div><div class="metric-value">'+wallTime+'</div><div class="metric-sub">'+esc(timeRange)+'</div></div>';
            html += '<div class="metric-card"><div class="metric-label">Tracked Time</div><div class="metric-value">'+trackTime+'</div><div class="metric-sub">total tracked</div></div>';
            html += '<div class="metric-card"><div class="metric-label">Apps</div><div class="metric-value">'+apps.length+'</div><div class="metric-sub">apps used</div></div>';
            html += '</div>';

            // Projects section
            if (brandSummaries.length > 0 && totalSec > 0) {
                html += '<div class="projects-section" id="projects"><div class="section-title">Projects</div>';
                // Stacked bar
                html += '<div class="brand-bar-container"><div class="brand-stacked-bar">';
                brandSummaries.forEach(function(b){
                    var pct = b.totalSeconds / totalSec * 100;
                    if (pct >= 0.5) {
                        var label = pct >= 8 ? esc(b.brandName)+' '+dur(b.totalSeconds) : dur(b.totalSeconds);
                        html += '<div class="brand-stacked-segment" style="width:'+pct.toFixed(1)+'%;background:'+esc(b.color)+'" title="'+esc(b.brandName)+': '+dur(b.totalSeconds)+'">'+label+'</div>';
                    }
                });
                html += '</div><div class="brand-bar-legend">';
                brandSummaries.forEach(function(b){
                    html += '<div class="brand-legend-item"><span class="brand-legend-dot" style="background:'+esc(b.color)+'"></span>'+esc(b.brandName)+' '+dur(b.totalSeconds)+'</div>';
                });
                html += '</div></div>';

                // Brand cards
                brandSummaries.forEach(function(b){
                    var bPct = totalSec > 0 ? b.totalSeconds / totalSec * 100 : 0;
                    html += '<div class="brand-card"><div class="brand-card-header" onclick="this.closest(\\x27.brand-card\\x27).classList.toggle(\\x27open\\x27)">';
                    html += '<div class="brand-card-left"><div class="brand-color-bar" style="background:'+esc(b.color)+'"></div><span class="brand-card-name">'+esc(b.brandName)+'</span></div>';
                    html += '<div class="brand-card-right"><span class="brand-card-time">'+dur(b.totalSeconds)+'</span><span class="brand-card-pct">'+bPct.toFixed(0)+'%</span><span class="brand-card-chevron">&#9654;</span></div>';
                    html += '</div><div class="brand-card-body">';
                    var maxPS = (b.projects && b.projects[0]) ? b.projects[0].totalSeconds : 1;
                    (b.projects||[]).forEach(function(p){
                        var pPct = b.totalSeconds > 0 ? p.totalSeconds / b.totalSeconds * 100 : 0;
                        var barW = p.totalSeconds / maxPS * 100;
                        var appsStr = (p.appBreakdown||[]).slice(0,3).map(function(a){return a.appName+' '+dur(a.seconds);}).join(', ');
                        html += '<div class="proj-row"><div class="proj-info"><div class="proj-name">'+esc(p.projectName)+'</div><div class="proj-apps">'+esc(appsStr)+'</div></div>';
                        html += '<div class="proj-stats"><div class="proj-bar-track"><div class="proj-bar-fill" style="width:'+barW.toFixed(1)+'%;background:'+esc(p.color)+'"></div></div><span class="proj-time">'+dur(p.totalSeconds)+'</span><span class="proj-pct">'+pPct.toFixed(0)+'%</span></div></div>';
                    });
                    html += '</div></div>';
                });
                html += '</div>';
            }

            // Overview: Donut + Stats
            html += '<div class="overview" id="overview-chart"><div class="overview-chart"><div class="donut-container">';
            html += buildDonutSVG(apps, colors, totalSec);
            html += '<div class="donut-center"><div class="donut-total">'+dur(totalSec)+'</div><div class="donut-label">total</div></div>';
            html += '</div></div><div class="overview-stats">';
            apps.slice(0,10).forEach(function(app){
                var c = colors[app.appName]||'#6366f1';
                var pct = totalSec > 0 ? app.totalSeconds/totalSec*100 : 0;
                html += '<div class="stat-row"><span class="stat-dot" style="background:'+c+'"></span><span class="stat-name">'+esc(app.appName)+'</span><span class="stat-value">'+dur(app.totalSeconds)+'</span><span class="stat-pct">'+pct.toFixed(0)+'%</span></div>';
            });
            html += '</div></div>';

            // Applications
            html += '<div id="apps" class="section-title" style="scroll-margin-top:24px">Applications</div>';
            apps.forEach(function(app, i){
                var color = colors[app.appName]||'#6366f1';
                var pct = totalSec > 0 ? app.totalSeconds/totalSec*100 : 0;
                var barW = totalSec > 0 ? app.totalSeconds/((apps[0]||{}).totalSeconds||1)*100 : 0;
                var isMedia = MEDIA_APPS.indexOf(app.appName) >= 0;

                html += '<div class="app-card" id="app-'+i+'"><div class="app-header"><div class="app-name-row"><span class="app-dot" style="background:'+color+'"></span><span class="app-name">'+esc(app.appName)+'</span></div>';
                html += '<div class="app-meta"><span class="app-time">'+dur(app.totalSeconds)+'</span><span class="app-pct">'+pct.toFixed(1)+'%</span>';
                html += '<label class="select-all-wrap"><input type="checkbox" class="select-all-check" onchange="toggleSelectAll(this)">All</label></div></div>';
                html += '<div class="app-bar-track"><div class="app-bar-fill" style="width:'+barW.toFixed(1)+'%;background:'+color+'"></div></div>';
                html += '<div class="windows-list">';

                (app.windowDetails||[]).slice(0,12).forEach(function(w){
                    // Skip fully assigned windows
                    var wIds = w.activityIds||[];
                    if (wIds.length > 0 && wIds.every(function(id){ return assignedIds[id]; })) return;

                    var wPct = app.totalSeconds > 0 ? w.totalSeconds/app.totalSeconds*100 : 0;
                    var wBarW = (app.windowDetails[0]) ? w.totalSeconds/app.windowDetails[0].totalSeconds*100 : 0;
                    var title = esc(String(w.windowTitle).substring(0,80));
                    var detailParts = [];
                    if (w.extraInfo) detailParts.push('<span class="tag">'+esc(w.extraInfo)+'</span>');
                    if (w.url) detailParts.push(esc(String(w.url).substring(0,70)));
                    var detailLine = detailParts.length ? '<div class="window-detail">'+detailParts.join(' ')+'</div>' : '';
                    var idsJSON = JSON.stringify(w.activityIds||[]);

                    html += '<div class="window-row" data-ids=\\''+idsJSON+'\\'>';
                    html += '<input type="checkbox" class="bulk-check" onchange="toggleBulkCheck(this)">';
                    html += '<div class="window-info"><div class="window-title">'+title+'</div>'+detailLine+'</div>';
                    if (isMedia) {
                        html += '<div class="window-stats"><button class="window-assign-btn" onclick="showWindowAssign(this)">Assign</button></div>';
                    } else {
                        html += '<div class="window-stats"><div class="window-bar-track"><div class="window-bar-fill" style="width:'+wBarW.toFixed(1)+'%;background:'+color+'30"></div></div>';
                        html += '<span class="window-time">'+dur(w.totalSeconds)+'</span><span class="window-pct">'+wPct.toFixed(0)+'%</span>';
                        html += '<button class="window-assign-btn" onclick="showWindowAssign(this)">Assign</button></div>';
                    }
                    html += '</div>';
                });

                html += '</div></div>';
            });

            // Timeline
            if (timeline.length > 0) {
                html += '<div class="timeline" id="timeline"><div class="section-title">Timeline</div>';
                var groups = [];
                timeline.forEach(function(e){
                    var time = e.timestamp ? new Date(e.timestamp).toTimeString().substring(0,5) : '';
                    if (groups.length && groups[groups.length-1].app === e.appName) {
                        groups[groups.length-1].entries.push({time:time,title:e.windowTitle,url:e.url,extra:e.extraInfo,dur:e.durationSeconds});
                    } else {
                        groups.push({app:e.appName, entries:[{time:time,title:e.windowTitle,url:e.url,extra:e.extraInfo,dur:e.durationSeconds}]});
                    }
                });
                groups.forEach(function(g){
                    var c = colors[g.app]||'#6366f1';
                    var isMedia = MEDIA_APPS.indexOf(g.app) >= 0;
                    html += '<div class="tl-group"><div class="tl-app"><span class="tl-dot" style="background:'+c+'"></span>'+esc(g.app)+'</div>';
                    g.entries.forEach(function(e){
                        var parts = [];
                        if (e.extra) parts.push(e.extra);
                        if (e.url) parts.push(String(e.url).substring(0,80));
                        var extraLine = parts.length ? '<div class="tl-extra">'+esc(parts.join(' \\u00B7 '))+'</div>' : '';
                        var durSpan = isMedia ? '' : '<span class="tl-dur">'+dur(e.dur)+'</span>';
                        html += '<div class="tl-entry"><span class="tl-time">'+e.time+'</span><span class="tl-title">'+esc(String(e.title).substring(0,65))+'</span>'+durSpan+'</div>'+extraLine;
                    });
                    html += '</div>';
                });
                html += '</div>';
            }

            html += '<div class="footer">Generated by Pulse</div>';
            document.getElementById('main-content').innerHTML = html;
        }

        function buildDonutSVG(apps, colors, totalSec) {
            if (!apps.length || !totalSec) return '<svg viewBox="0 0 36 36" width="160" height="160"><circle cx="18" cy="18" r="15.9155" fill="none" stroke="#f0f0f5" stroke-width="3.8"/></svg>';
            var R = 15.9155;
            var C = 2 * Math.PI * R;
            var offset = 25;
            var segs = '';
            apps.forEach(function(app){
                var frac = app.totalSeconds / totalSec;
                var dashLen = frac * C;
                var gap = C - dashLen;
                var c = colors[app.appName]||'#6366f1';
                segs += '<circle cx="18" cy="18" r="'+R.toFixed(4)+'" fill="none" stroke="'+c+'" stroke-width="3.8" stroke-dasharray="'+dashLen.toFixed(2)+' '+gap.toFixed(2)+'" stroke-dashoffset="'+(-offset).toFixed(2)+'" stroke-linecap="round"/>';
                offset += dashLen;
            });
            return '<svg viewBox="0 0 36 36" width="160" height="160">'+segs+'</svg>';
        }

        // ---- Sidebar ----
        var __lastSidebarSummary = null;
        var __sidebarBrands = [];
        function renderSidebar(summary) {
            __lastSidebarSummary = summary;
            var apps = summary.apps || [];
            var colors = {};
            apps.forEach(function(a,i){ colors[a.appName] = APP_COLORS[i % APP_COLORS.length]; });
            var html = '<div class="sidebar-section"><div class="sidebar-heading">Navigation</div>';
            html += '<a onclick="scrollToEl(\\x27overview\\x27)">Overview</a>';
            html += '<a onclick="scrollToEl(\\x27projects\\x27)">Projects</a>';
            html += '<a onclick="scrollToEl(\\x27apps\\x27)">Applications</a>';
            html += '<a onclick="scrollToEl(\\x27timeline\\x27)">Timeline</a>';
            html += '</div>';

            // Clients / Projects section
            html += '<div class="nav-divider"></div><div class="sidebar-section"><div class="sidebar-heading">Clients</div>';
            if (__sidebarBrands.length > 0) {
                __sidebarBrands.forEach(function(b){
                    var isActive = currentView==='brand' && __currentBrandId === b.id;
                    html += '<a onclick="loadBrandView('+b.id+')" style="cursor:pointer" class="'+(isActive?'active':'')+'"><span class="nav-dot" style="background:'+esc(b.color)+'"></span>'+esc(b.name)+'</a>';
                });
            }
            html += '<a onclick="loadManageView()" style="cursor:pointer;color:#8e8ea0;font-size:12px;margin-top:4px"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="12" height="12" style="vertical-align:-1px;margin-right:4px"><path d="M8 1a1.5 1.5 0 011.5 1.5v.3a5.5 5.5 0 011.3.75l.21-.21a1.5 1.5 0 012.12 2.12l-.21.21c.32.4.57.84.75 1.3h.3a1.5 1.5 0 010 3h-.3a5.5 5.5 0 01-.75 1.3l.21.21a1.5 1.5 0 01-2.12 2.12l-.21-.21a5.5 5.5 0 01-1.3.75v.3a1.5 1.5 0 01-3 0v-.3a5.5 5.5 0 01-1.3-.75l-.21.21a1.5 1.5 0 01-2.12-2.12l.21-.21A5.5 5.5 0 012.32 9.5H2A1.5 1.5 0 012 6.5h.3a5.5 5.5 0 01.75-1.3l-.21-.21a1.5 1.5 0 012.12-2.12l.21.21a5.5 5.5 0 011.3-.75V2A1.5 1.5 0 018 1z"/><circle cx="8" cy="8" r="2"/></svg>Manage</a>';
            html += '</div>';

            html += '<div class="nav-divider"></div><div class="sidebar-section"><div class="sidebar-heading">Apps</div>';
            var totalAppSec = apps.reduce(function(s,a){ return s + (a.totalSeconds||0); }, 0);
            html += '<a onclick="loadDay(currentDate)" style="cursor:pointer;font-weight:600" class="' + (currentView==='day'?'active':'') + '"><span class="nav-dot" style="background:linear-gradient(135deg,#7C5CFC,#5B8DEF);border:1px solid rgba(255,255,255,.15)"></span>All<span class="nav-time">'+dur(totalAppSec)+'</span></a>';
            apps.forEach(function(app, i){
                var c = colors[app.appName]||'#6366f1';
                var safeName = app.appName.replace(/'/g,"\\\\'");
                var isAppActive = currentView==='app' && __currentAppName === app.appName;
                html += '<a onclick="loadAppView(\\x27'+safeName+'\\x27)" style="cursor:pointer" class="'+(isAppActive?'active':'')+'"><span class="nav-dot" style="background:'+c+'"></span>'+esc(app.appName)+'<span class="nav-time">'+dur(app.totalSeconds)+'</span></a>';
            });
            html += '</div>';
            document.getElementById('sidebar-nav').innerHTML = html;
        }

        // Load brands for sidebar on init
        function loadSidebarBrands() {
            apiCall('/api/projects').then(function(res) {
                __sidebarBrands = res.brands || [];
                if (__lastSidebarSummary) renderSidebar(__lastSidebarSummary);
            }).catch(function(){});
        }
        loadSidebarBrands();

        function scrollToEl(id) {
            var el = document.getElementById(id);
            if (el) el.scrollIntoView({behavior:'smooth', block:'start'});
        }

        // ---- Brand Detail View State ----
        var __currentBrandId = null;
        var __currentBrandPeriod = 'all'; // 'all','week','month','custom'
        var __brandCustomFrom = null;
        var __brandCustomTo = null;

        // ---- App Detail View ----
        var __currentAppName = null;
        var __currentAppPeriod = 'all'; // 'all','week','month'

        function loadAppView(appName, period) {
            currentView = 'app';
            __currentAppName = appName;
            __currentAppPeriod = period || 'all';
            var main = document.getElementById('main-content');
            main.innerHTML = '<div class="loading-spinner"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg>&nbsp; Loading '+esc(appName)+'...</div>';
            document.getElementById('right-panel').innerHTML = '';

            var url = '/api/app?name='+encodeURIComponent(appName);
            if (__currentAppPeriod === 'week') {
                var d = new Date(currentDate+'T12:00:00');
                var day = d.getDay(); var diff = d.getDate() - day + (day===0?-6:1);
                var mon = new Date(d); mon.setDate(diff);
                var sun = new Date(mon); sun.setDate(mon.getDate()+6);
                url += '&from='+fmt(mon)+'&to='+fmt(sun);
            } else if (__currentAppPeriod === 'month') {
                var p = currentDate.split('-');
                var yr = p[0], mo = p[1];
                var lastDay = new Date(parseInt(yr), parseInt(mo), 0).getDate();
                url += '&from='+yr+'-'+mo+'-01&to='+yr+'-'+mo+'-'+String(lastDay).padStart(2,'0');
            }

            apiCall(url).then(function(res) {
                renderAppView(res);
            }).catch(function() {
                main.innerHTML = '<div class="loading-spinner" style="color:#ef4444">Cannot load app data.</div>';
            });
        }

        function switchAppPeriod(period) {
            loadAppView(__currentAppName, period);
        }

        function renderAppView(report) {
            var appName = report.appName || '';
            var totalSec = report.totalSeconds || 0;
            var days = report.days || [];
            var topWindows = report.topWindows || [];
            var isMedia = MEDIA_APPS.indexOf(appName) >= 0;

            // Group days by month
            var monthMap = {};
            days.forEach(function(d){
                var key = d.date.substring(0,7); // YYYY-MM
                if (!monthMap[key]) monthMap[key] = {month:key, totalSeconds:0, days:[], dayCount:0};
                monthMap[key].totalSeconds += d.totalSeconds;
                monthMap[key].days.push(d);
                monthMap[key].dayCount++;
            });
            var months = Object.values(monthMap).sort(function(a,b){ return b.month.localeCompare(a.month); });

            var html = '';

            // Header
            html += '<div class="header" id="overview"><div class="header-label">App Detail</div>';
            html += '<div class="header-date" style="display:flex;align-items:center;gap:12px">';
            html += '<button class="nav-arrow" onclick="loadDay(currentDate)" title="Back to day report">&#9664;</button>';
            html += '<span>'+esc(appName)+'</span></div>';
            var periodLabel = __currentAppPeriod === 'week' ? 'this week' : __currentAppPeriod === 'month' ? 'this month' : 'all time';
            html += '<div class="header-total">Total: <strong>'+dur(totalSec)+'</strong> across <strong>'+days.length+'</strong> days ('+periodLabel+')</div></div>';

            // Period tabs
            html += '<div class="view-tabs">';
            html += '<button class="view-tab'+(__currentAppPeriod==='all'?' active':'')+'" onclick="switchAppPeriod(\\x27all\\x27)">All Time</button>';
            html += '<button class="view-tab'+(__currentAppPeriod==='week'?' active':'')+'" onclick="switchAppPeriod(\\x27week\\x27)">Week</button>';
            html += '<button class="view-tab'+(__currentAppPeriod==='month'?' active':'')+'" onclick="switchAppPeriod(\\x27month\\x27)">Month</button>';
            html += '</div>';

            // Metric cards
            var avgPerDay = days.length > 0 ? Math.round(totalSec / days.length) : 0;
            var maxDay = days.reduce(function(mx,d){ return d.totalSeconds > mx.totalSeconds ? d : mx; }, {totalSeconds:0,date:'-'});
            html += '<div class="metric-cards">';
            html += '<div class="metric-card"><div class="metric-label">Total Time</div><div class="metric-value">'+dur(totalSec)+'</div><div class="metric-sub">'+periodLabel+'</div></div>';
            html += '<div class="metric-card"><div class="metric-label">Daily Average</div><div class="metric-value">'+dur(avgPerDay)+'</div><div class="metric-sub">across '+days.length+' days</div></div>';
            html += '<div class="metric-card"><div class="metric-label">Peak Day</div><div class="metric-value">'+dur(maxDay.totalSeconds)+'</div><div class="metric-sub">'+maxDay.date+'</div></div>';
            html += '</div>';

            // Monthly breakdown (only for 'all' period)
            if (months.length > 0 && __currentAppPeriod === 'all') {
                html += '<div class="section-title">Monthly Breakdown</div>';
                var maxMonthSec = Math.max.apply(null, months.map(function(m){return m.totalSeconds;}).concat([1]));

                months.forEach(function(m){
                    var parts = m.month.split('-');
                    var mName = MONTH_NAMES[parseInt(parts[1])-1] + ' ' + parts[0];
                    var barW = m.totalSeconds / maxMonthSec * 100;
                    var avgD = m.dayCount > 0 ? Math.round(m.totalSeconds / m.dayCount) : 0;

                    html += '<div class="app-card">';
                    html += '<div class="app-header"><div class="app-name-row"><span class="app-name">'+mName+'</span></div>';
                    html += '<div class="app-meta"><span class="app-time">'+dur(m.totalSeconds)+'</span></div></div>';
                    html += '<div class="app-bar-track"><div class="app-bar-fill" style="width:'+barW.toFixed(1)+'%;background:#6366f1"></div></div>';
                    html += '<div style="display:flex;gap:16px;font-size:12px;color:#8e8ea0">';
                    html += '<span>'+m.dayCount+' days active</span>';
                    html += '<span>Avg: '+dur(avgD)+'/day</span>';
                    html += '</div>';

                    // Mini day bars
                    var maxDaySec = Math.max.apply(null, m.days.map(function(d){return d.totalSeconds;}).concat([1]));
                    html += '<div style="display:flex;gap:2px;margin-top:8px;height:32px;align-items:flex-end">';
                    m.days.sort(function(a,b){return a.date.localeCompare(b.date);}).forEach(function(d){
                        var pct = d.totalSeconds / maxDaySec * 100;
                        html += '<div style="flex:1;min-width:2px;background:#6366f1;border-radius:2px 2px 0 0;height:'+Math.max(pct,4)+'%;opacity:'+(0.3+0.7*pct/100)+';cursor:pointer" onclick="loadDay(\\x27'+d.date+'\\x27)" title="'+d.date+': '+dur(d.totalSeconds)+'"></div>';
                    });
                    html += '</div>';
                    html += '</div>';
                });
            }

            // Top windows / content
            if (topWindows.length > 0) {
                if (isMedia) {
                    // Entertainment apps: show content list without per-item durations
                    html += '<div class="section-title">'+esc(appName)+' \\u2014 Content Played</div>';
                    html += '<div class="app-card"><div class="windows-list">';
                    topWindows.forEach(function(w){
                        var title = esc(String(w.windowTitle).substring(0,100));
                        var detailParts = [];
                        if (w.extraInfo) detailParts.push('<span class="tag">'+esc(w.extraInfo)+'</span>');
                        if (w.url) detailParts.push(esc(String(w.url).substring(0,70)));
                        var detailLine = detailParts.length ? '<div class="window-detail">'+detailParts.join(' ')+'</div>' : '';
                        html += '<div class="window-row"><div class="window-info"><div class="window-title">'+title+'</div>'+detailLine+'</div></div>';
                    });
                    html += '</div></div>';
                } else {
                    html += '<div class="section-title">Top Windows / Tabs</div>';
                    html += '<div class="app-card"><div class="windows-list">';
                    var maxWinSec = topWindows[0].totalSeconds || 1;
                    topWindows.forEach(function(w){
                        var wBarW = w.totalSeconds / maxWinSec * 100;
                        var title = esc(String(w.windowTitle).substring(0,80));
                        var detailParts = [];
                        if (w.extraInfo) detailParts.push('<span class="tag">'+esc(w.extraInfo)+'</span>');
                        if (w.url) detailParts.push(esc(String(w.url).substring(0,70)));
                        var detailLine = detailParts.length ? '<div class="window-detail">'+detailParts.join(' ')+'</div>' : '';

                        html += '<div class="window-row">';
                        html += '<div class="window-info"><div class="window-title">'+title+'</div>'+detailLine+'</div>';
                        html += '<div class="window-stats">';
                        html += '<div class="window-bar-track"><div class="window-bar-fill" style="width:'+wBarW.toFixed(1)+'%;background:#6366f130"></div></div>';
                        html += '<span class="window-time">'+dur(w.totalSeconds)+'</span>';
                        html += '</div></div>';
                    });
                    html += '</div></div>';
                }
            }

            // Recent days
            if (days.length > 0) {
                html += '<div class="section-title">Recent Days</div>';
                days.slice(0,14).forEach(function(d){
                    html += '<div class="proj-row" style="cursor:pointer" onclick="loadDay(\\x27'+d.date+'\\x27)">';
                    html += '<div class="proj-info"><div class="proj-name">'+formatDateShort(d.date)+'</div></div>';
                    html += '<div class="proj-stats"><span class="proj-time">'+dur(d.totalSeconds)+'</span></div>';
                    html += '</div>';
                });
            }

            html += '<div class="footer">Generated by Pulse</div>';
            document.getElementById('main-content').innerHTML = html;
        }

        // ---- Brand/Project Detail View ----
        function loadBrandView(brandId, period) {
            currentView = 'brand';
            __currentBrandId = brandId;
            __currentBrandPeriod = period || 'all';
            var main = document.getElementById('main-content');
            main.innerHTML = '<div class="loading-spinner"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg>&nbsp; Loading...</div>';
            document.getElementById('right-panel').innerHTML = '';

            var url = '/api/brand/detail?id='+brandId;
            if (__currentBrandPeriod === 'week') {
                var d = new Date(currentDate+'T12:00:00');
                var day = d.getDay(); var diff = d.getDate() - day + (day===0?-6:1);
                var mon = new Date(d); mon.setDate(diff);
                var sun = new Date(mon); sun.setDate(mon.getDate()+6);
                url += '&from='+fmt(mon)+'&to='+fmt(sun);
            } else if (__currentBrandPeriod === 'month') {
                var p = currentDate.split('-');
                var yr = p[0], mo = p[1];
                var lastDay = new Date(parseInt(yr), parseInt(mo), 0).getDate();
                url += '&from='+yr+'-'+mo+'-01&to='+yr+'-'+mo+'-'+String(lastDay).padStart(2,'0');
            } else if (__currentBrandPeriod === 'custom' && __brandCustomFrom && __brandCustomTo) {
                url += '&from='+__brandCustomFrom+'&to='+__brandCustomTo;
            }

            apiCall(url).then(function(res) {
                renderBrandView(res);
                if (__lastSidebarSummary) renderSidebar(__lastSidebarSummary);
            }).catch(function() {
                main.innerHTML = '<div class="loading-spinner" style="color:#ef4444">Cannot load brand data.</div>';
            });
        }

        function switchBrandPeriod(period) {
            if (period === 'custom') {
                __currentBrandPeriod = 'custom';
                // Re-render to show date pickers, don't reload yet
                loadBrandView(__currentBrandId, 'custom');
            } else {
                loadBrandView(__currentBrandId, period);
            }
        }

        function applyBrandCustomRange() {
            var fromEl = document.getElementById('brand-custom-from');
            var toEl = document.getElementById('brand-custom-to');
            if (fromEl && toEl && fromEl.value && toEl.value) {
                __brandCustomFrom = fromEl.value;
                __brandCustomTo = toEl.value;
                loadBrandView(__currentBrandId, 'custom');
            }
        }

        function renderBrandView(report) {
            var brandName = report.brandName || '';
            var color = report.color || '#6366f1';
            var totalSec = report.totalSeconds || 0;
            var days = report.days || [];
            var brandProjects = report.projects || [];

            // Group days by month
            var monthMap = {};
            days.forEach(function(d){
                var key = d.date.substring(0,7);
                if (!monthMap[key]) monthMap[key] = {month:key, totalSeconds:0, days:[], dayCount:0};
                monthMap[key].totalSeconds += d.totalSeconds;
                monthMap[key].days.push(d);
                monthMap[key].dayCount++;
            });
            var months = Object.values(monthMap).sort(function(a,b){ return b.month.localeCompare(a.month); });

            var html = '';

            // Header
            var periodLabel = __currentBrandPeriod === 'week' ? 'this week' : __currentBrandPeriod === 'month' ? 'this month' : __currentBrandPeriod === 'custom' ? 'custom range' : 'all time';
            html += '<div class="header" id="overview"><div class="header-label">Client / Brand</div>';
            html += '<div class="header-date" style="display:flex;align-items:center;gap:12px">';
            html += '<button class="nav-arrow" onclick="loadDay(currentDate)" title="Back to day report">&#9664;</button>';
            html += '<span style="display:flex;align-items:center;gap:8px"><span style="width:12px;height:12px;border-radius:3px;background:'+esc(color)+'"></span>'+esc(brandName)+'</span></div>';
            html += '<div class="header-total">Total: <strong>'+dur(totalSec)+'</strong> across <strong>'+days.length+'</strong> days ('+periodLabel+')</div></div>';

            // Period tabs
            html += '<div class="view-tabs">';
            html += '<button class="view-tab'+(__currentBrandPeriod==='all'?' active':'')+'" onclick="switchBrandPeriod(\\x27all\\x27)">All Time</button>';
            html += '<button class="view-tab'+(__currentBrandPeriod==='week'?' active':'')+'" onclick="switchBrandPeriod(\\x27week\\x27)">Week</button>';
            html += '<button class="view-tab'+(__currentBrandPeriod==='month'?' active':'')+'" onclick="switchBrandPeriod(\\x27month\\x27)">Month</button>';
            html += '<button class="view-tab'+(__currentBrandPeriod==='custom'?' active':'')+'" onclick="switchBrandPeriod(\\x27custom\\x27)">Custom</button>';
            html += '</div>';

            // Custom date range picker
            if (__currentBrandPeriod === 'custom') {
                html += '<div style="display:flex;align-items:center;gap:12px;margin:0 0 16px 0;padding:12px 16px;background:rgba(99,102,241,.06);border-radius:10px;border:1px solid rgba(99,102,241,.12)">';
                html += '<label style="font-size:13px;color:#8e8ea0">From</label>';
                html += '<input type="date" id="brand-custom-from" value="'+(__brandCustomFrom||'')+'" style="background:#1a1a2e;color:#e0e0e0;border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:6px 10px;font-size:13px">';
                html += '<label style="font-size:13px;color:#8e8ea0">To</label>';
                html += '<input type="date" id="brand-custom-to" value="'+(__brandCustomTo||'')+'" style="background:#1a1a2e;color:#e0e0e0;border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:6px 10px;font-size:13px">';
                html += '<button onclick="applyBrandCustomRange()" style="background:#6366f1;color:#fff;border:none;border-radius:6px;padding:6px 16px;font-size:13px;cursor:pointer">Apply</button>';
                html += '</div>';
            }

            // Metric cards
            var avgPerDay = days.length > 0 ? Math.round(totalSec / days.length) : 0;
            var maxDay = days.reduce(function(mx,d){ return d.totalSeconds > mx.totalSeconds ? d : mx; }, {totalSeconds:0,date:'-'});
            html += '<div class="metric-cards">';
            html += '<div class="metric-card"><div class="metric-label">Total Time</div><div class="metric-value">'+dur(totalSec)+'</div><div class="metric-sub">'+periodLabel+'</div></div>';
            html += '<div class="metric-card"><div class="metric-label">Daily Average</div><div class="metric-value">'+dur(avgPerDay)+'</div><div class="metric-sub">across '+days.length+' days</div></div>';
            html += '<div class="metric-card"><div class="metric-label">Projects</div><div class="metric-value">'+brandProjects.length+'</div><div class="metric-sub">active projects</div></div>';
            html += '</div>';

            // Projects breakdown
            if (brandProjects.length > 0) {
                html += '<div class="section-title">Projects</div>';
                var maxProjSec = Math.max.apply(null, brandProjects.map(function(p){return p.totalSeconds||0;}).concat([1]));
                brandProjects.forEach(function(proj){
                    var barW = proj.totalSeconds / maxProjSec * 100;
                    var pDays = proj.days || [];
                    var pct = totalSec > 0 ? (proj.totalSeconds / totalSec * 100).toFixed(0) : 0;

                    html += '<div class="app-card">';
                    html += '<div class="app-header"><div class="app-name-row"><span class="app-dot" style="background:'+(proj.color||color)+'"></span><span class="app-name">'+esc(proj.name)+'</span></div>';
                    html += '<div class="app-meta"><span class="app-time">'+dur(proj.totalSeconds)+'</span><span class="app-pct">'+pct+'%</span></div></div>';
                    html += '<div class="app-bar-track"><div class="app-bar-fill" style="width:'+barW.toFixed(1)+'%;background:'+(proj.color||color)+'"></div></div>';
                    html += '<div style="display:flex;gap:16px;font-size:12px;color:#8e8ea0"><span>'+pDays.length+' days active</span></div>';

                    // Mini day bars for project
                    if (pDays.length > 0) {
                        var maxPDaySec = Math.max.apply(null, pDays.map(function(d){return d.totalSeconds||0;}).concat([1]));
                        html += '<div style="display:flex;gap:2px;margin-top:8px;height:24px;align-items:flex-end">';
                        pDays.sort(function(a,b){return a.date.localeCompare(b.date);}).forEach(function(d){
                            var pctH = d.totalSeconds / maxPDaySec * 100;
                            html += '<div style="flex:1;min-width:2px;background:'+(proj.color||color)+';border-radius:2px 2px 0 0;height:'+Math.max(pctH,4)+'%;opacity:'+(0.3+0.7*pctH/100)+';cursor:pointer" onclick="loadDay(\\x27'+d.date+'\\x27)" title="'+d.date+': '+dur(d.totalSeconds)+'"></div>';
                        });
                        html += '</div>';
                    }
                    html += '</div>';
                });
            }

            // Monthly breakdown (only for 'all' period)
            if (months.length > 0 && __currentBrandPeriod === 'all') {
                html += '<div class="section-title">Monthly Breakdown</div>';
                var maxMonthSec = Math.max.apply(null, months.map(function(m){return m.totalSeconds;}).concat([1]));

                months.forEach(function(m){
                    var parts = m.month.split('-');
                    var mName = MONTH_NAMES[parseInt(parts[1])-1] + ' ' + parts[0];
                    var barW = m.totalSeconds / maxMonthSec * 100;
                    var avgD = m.dayCount > 0 ? Math.round(m.totalSeconds / m.dayCount) : 0;

                    html += '<div class="app-card">';
                    html += '<div class="app-header"><div class="app-name-row"><span class="app-name">'+mName+'</span></div>';
                    html += '<div class="app-meta"><span class="app-time">'+dur(m.totalSeconds)+'</span></div></div>';
                    html += '<div class="app-bar-track"><div class="app-bar-fill" style="width:'+barW.toFixed(1)+'%;background:'+esc(color)+'"></div></div>';
                    html += '<div style="display:flex;gap:16px;font-size:12px;color:#8e8ea0">';
                    html += '<span>'+m.dayCount+' days active</span>';
                    html += '<span>Avg: '+dur(avgD)+'/day</span>';
                    html += '</div></div>';
                });
            }

            // Recent days
            if (days.length > 0) {
                html += '<div class="section-title">Recent Days</div>';
                days.slice(0,14).forEach(function(d){
                    html += '<div class="proj-row" style="cursor:pointer" onclick="loadDay(\\x27'+d.date+'\\x27)">';
                    html += '<div class="proj-info"><div class="proj-name">'+formatDateShort(d.date)+'</div></div>';
                    html += '<div class="proj-stats"><span class="proj-time">'+dur(d.totalSeconds)+'</span></div>';
                    html += '</div>';
                });
            }

            html += '<div class="footer">Generated by Pulse</div>';
            document.getElementById('main-content').innerHTML = html;
        }

        // ---- Right Panel ----
        function renderRightPanel(unassigned, brands, projects) {
            var filtered = (unassigned||[]).filter(function(a){ return NON_WORK_APPS.indexOf(a.appName) < 0; });
            var panel = document.getElementById('right-panel');
            if (!filtered.length) { panel.innerHTML = ''; return; }

            var optHTML = buildProjectOptions(brands, projects);
            var html = '<div class="right-panel-title">Unclassified</div>';
            html += '<div id="suggestions-container" class="suggestions-container"></div>';
            html += '<div class="unassigned-section"><div class="unassigned-header"><span class="unassigned-title">Activities</span><span class="unassigned-count">'+filtered.length+' items</span></div>';

            filtered.slice(0,30).forEach(function(act){
                var detail = act.url || act.extraInfo || act.windowTitle || '';
                html += '<div class="unassigned-row" data-activity-id="'+act.id+'">';
                html += '<span class="unassigned-app">'+esc(act.appName)+'</span>';
                html += '<span class="unassigned-detail" title="'+escA(act.windowTitle||'')+'">'+esc(String(detail).substring(0,50))+'</span>';
                html += '<span class="unassigned-dur">'+dur(act.durationSeconds)+'</span>';
                html += '<select class="unassigned-select">'+optHTML+'</select>';
                html += '<label class="unassigned-rule-check"><input type="checkbox" class="rule-check" checked> Rule</label>';
                html += '<button class="unassigned-save-btn" onclick="classifyRow(this)">Save</button>';
                html += '</div>';
            });

            html += '<button class="unassigned-save-all" id="save-all-btn" onclick="classifyAll()">Save All Selected</button>';
            html += '<div class="unassigned-api-error" id="api-error"></div>';
            html += '</div>';
            panel.innerHTML = html;
        }

        // ---- Week View ----
        function loadWeek(dateStr) {
            currentDate = dateStr || currentDate;
            currentView = 'week';
            var main = document.getElementById('main-content');
            main.innerHTML = '<div class="loading-spinner"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg>&nbsp; Loading week...</div>';

            apiCall('/api/report/week?date=' + currentDate).then(function(res) {
                renderWeekView(res);
            }).catch(function() {
                main.innerHTML = '<div class="loading-spinner" style="color:#ef4444">Cannot load week data.</div>';
            });
        }

        function renderWeekView(res) {
            var days = res.days || [];
            var weekStart = res.weekStart || '';
            var weekEnd = res.weekEnd || '';
            var totalSec = days.reduce(function(s,d){return s+(d.totalSeconds||0);},0);
            var maxSec = Math.max.apply(null, days.map(function(d){return d.totalSeconds||0;}).concat([1]));

            var html = '';
            // Header
            html += '<div class="header" id="overview"><div class="header-label">Week Report</div>';
            html += '<div class="header-date">';
            html += '<button class="nav-arrow" onclick="loadWeek(prevWeek())" title="Previous week">&#9664;</button>';
            html += '<span>'+formatDateDisplay(weekStart)+' \\u2013 '+formatDateDisplay(weekEnd)+'</span>';
            html += '<button class="nav-arrow" onclick="loadWeek(nextWeek())" title="Next week">&#9654;</button>';
            html += '</div>';
            html += '<div class="header-total">Total: <strong>'+dur(totalSec)+'</strong></div></div>';

            // View Tabs
            html += '<div class="view-tabs">';
            html += '<button class="view-tab" onclick="switchView(\\x27day\\x27)">Day</button>';
            html += '<button class="view-tab active" onclick="switchView(\\x27week\\x27)">Week</button>';
            html += '<button class="view-tab" onclick="switchView(\\x27month\\x27)">Month</button>';
            html += '</div>';

            // Bar chart
            html += '<div class="week-chart"><div class="week-bars">';
            days.forEach(function(d){
                var pct = maxSec > 0 ? (d.totalSeconds||0)/maxSec*100 : 0;
                var p = d.date.split('-');
                var dt = new Date(+p[0],+p[1]-1,+p[2]);
                var dayName = DAY_NAMES[dt.getDay()];
                html += '<div class="week-bar-col">';
                html += '<div class="week-bar-value">'+dur(d.totalSeconds||0)+'</div>';
                html += '<div class="week-bar" style="height:'+Math.max(pct,2)+'%" onclick="loadDay(\\x27'+d.date+'\\x27)" title="'+d.date+'"></div>';
                html += '<div class="week-bar-label">'+dayName+'</div>';
                html += '</div>';
            });
            html += '</div></div>';

            // Day cards
            html += '<div class="week-day-cards">';
            days.forEach(function(d){
                var appCount = (d.apps||[]).length;
                html += '<div class="week-day-card" onclick="loadDay(\\x27'+d.date+'\\x27)">';
                html += '<div class="week-day-card-date">'+formatDateDisplay(d.date)+'</div>';
                html += '<div class="week-day-card-time">'+dur(d.totalSeconds||0)+'</div>';
                html += '<div class="week-day-card-apps">'+appCount+' apps</div>';
                html += '</div>';
            });
            html += '</div>';
            html += '<div class="footer">Generated by Pulse</div>';
            document.getElementById('main-content').innerHTML = html;
        }

        function prevWeek() { var p=currentDate.split('-'); var d=new Date(+p[0],+p[1]-1,+p[2]); d.setDate(d.getDate()-7); return fmt(d); }
        function nextWeek() { var p=currentDate.split('-'); var d=new Date(+p[0],+p[1]-1,+p[2]); d.setDate(d.getDate()+7); return fmt(d); }

        // ---- Month View ----
        function loadMonth(year, month) {
            currentYear = year || currentYear;
            currentMonth = month || currentMonth;
            currentView = 'month';
            var main = document.getElementById('main-content');
            main.innerHTML = '<div class="loading-spinner"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg>&nbsp; Loading month...</div>';

            apiCall('/api/report/month?year='+currentYear+'&month='+currentMonth).then(function(res) {
                renderMonthView(res);
            }).catch(function() {
                main.innerHTML = '<div class="loading-spinner" style="color:#ef4444">Cannot load month data.</div>';
            });
        }

        function renderMonthView(res) {
            var days = res.days || [];
            var totalSec = res.totalSeconds || 0;
            var year = res.year || currentYear;
            var month = res.month || currentMonth;
            var maxSec = Math.max.apply(null, days.map(function(d){return d.totalSeconds||0;}).concat([1]));

            // Build day map
            var dayMap = {};
            days.forEach(function(d){ dayMap[d.date] = d; });

            var html = '';
            // Header
            html += '<div class="header" id="overview"><div class="header-label">Month Report</div>';
            html += '<div class="header-date">';
            html += '<button class="nav-arrow" onclick="loadMonth('+(month===1?year-1:year)+','+(month===1?12:month-1)+')" title="Previous month">&#9664;</button>';
            html += '<span>'+MONTH_NAMES[month-1]+' '+year+'</span>';
            html += '<button class="nav-arrow" onclick="loadMonth('+(month===12?year+1:year)+','+(month===12?1:month+1)+')" title="Next month">&#9654;</button>';
            html += '</div>';
            html += '<div class="header-total">Total: <strong>'+dur(totalSec)+'</strong></div></div>';

            // View Tabs
            html += '<div class="view-tabs">';
            html += '<button class="view-tab" onclick="switchView(\\x27day\\x27)">Day</button>';
            html += '<button class="view-tab" onclick="switchView(\\x27week\\x27)">Week</button>';
            html += '<button class="view-tab active" onclick="switchView(\\x27month\\x27)">Month</button>';
            html += '</div>';

            // Calendar heatmap
            html += '<div class="week-chart">';
            html += '<div class="month-grid">';
            // Header row
            ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].forEach(function(d){
                html += '<div class="month-grid-header">'+d+'</div>';
            });

            // Calculate first day of month (Monday=0)
            var firstDay = new Date(year, month-1, 1);
            var dow = firstDay.getDay(); // 0=Sun
            var startOffset = dow === 0 ? 6 : dow - 1; // Convert to Mon=0
            var daysInMonth = new Date(year, month, 0).getDate();

            // Empty cells
            for (var i = 0; i < startOffset; i++) {
                html += '<div class="month-cell empty"></div>';
            }

            // Day cells
            for (var d = 1; d <= daysInMonth; d++) {
                var dateStr = year + '-' + String(month).padStart(2,'0') + '-' + String(d).padStart(2,'0');
                var dayData = dayMap[dateStr];
                var sec = dayData ? dayData.totalSeconds || 0 : 0;
                var intensity = maxSec > 0 ? sec / maxSec : 0;
                var bg, color;
                if (sec === 0) {
                    bg = '#f0f0f5'; color = '#a0a0b0';
                } else if (intensity < 0.25) {
                    bg = '#e0e7ff'; color = '#4338ca';
                } else if (intensity < 0.5) {
                    bg = '#c7d2fe'; color = '#4338ca';
                } else if (intensity < 0.75) {
                    bg = '#a5b4fc'; color = '#fff';
                } else {
                    bg = '#6366f1'; color = '#fff';
                }
                html += '<div class="month-cell" style="background:'+bg+';color:'+color+'" onclick="loadDay(\\x27'+dateStr+'\\x27)" title="'+dateStr+': '+dur(sec)+'">'+d+'</div>';
            }
            html += '</div></div>';

            // Day breakdown bar chart
            if (days.length > 0) {
                html += '<div class="week-chart"><div class="week-bars" style="height:120px">';
                days.forEach(function(d){
                    var pct = maxSec > 0 ? (d.totalSeconds||0)/maxSec*100 : 0;
                    var dd = d.date.split('-')[2];
                    html += '<div class="week-bar-col" style="min-width:0">';
                    html += '<div class="week-bar" style="height:'+Math.max(pct,2)+'%" onclick="loadDay(\\x27'+d.date+'\\x27)" title="'+d.date+': '+dur(d.totalSeconds||0)+'"></div>';
                    html += '<div class="week-bar-label" style="font-size:9px">'+parseInt(dd)+'</div>';
                    html += '</div>';
                });
                html += '</div></div>';
            }

            // Daily detail list
            if (days.length > 0) {
                html += '<div class="section-title">Daily Breakdown</div>';
                days.sort(function(a,b){ return b.date.localeCompare(a.date); }).forEach(function(d){
                    var appCount = (d.apps||[]).length;
                    var wallTime = d.wallClockSeconds ? dur(d.wallClockSeconds) : '';
                    var timeRange = '';
                    if (d.firstActivity && d.lastActivity) timeRange = d.firstActivity + ' – ' + d.lastActivity;
                    var dateLabel = formatDateShort(d.date);

                    html += '<div class="app-card" style="cursor:pointer" onclick="loadDay(\\x27'+d.date+'\\x27)">';
                    html += '<div class="app-header"><div class="app-name-row">';
                    html += '<span class="app-name">'+dateLabel+'</span></div>';
                    html += '<div class="app-meta"><span class="app-time">'+dur(d.totalSeconds||0)+'</span></div></div>';
                    html += '<div style="display:flex;gap:16px;font-size:12px;color:#8e8ea0;flex-wrap:wrap">';
                    if (wallTime) html += '<span>Wall: '+wallTime+'</span>';
                    if (timeRange) html += '<span>'+timeRange+'</span>';
                    if (appCount) html += '<span>'+appCount+' apps</span>';
                    html += '</div>';

                    // Top apps mini bar
                    var topApps = (d.apps||[]).slice(0,5);
                    if (topApps.length > 0) {
                        html += '<div style="display:flex;gap:8px;margin-top:8px;flex-wrap:wrap">';
                        topApps.forEach(function(a,idx){
                            var c = APP_COLORS[idx%APP_COLORS.length];
                            var p = d.totalSeconds>0 ? (a.totalSeconds/d.totalSeconds*100).toFixed(0)+'%' : '';
                            html += '<span style="font-size:11px;color:#6b6b80;display:flex;align-items:center;gap:4px">';
                            html += '<span style="width:6px;height:6px;border-radius:50%;background:'+c+'"></span>';
                            html += esc(a.appName)+' '+dur(a.totalSeconds)+' <span style="color:#a0a0b0">'+p+'</span></span>';
                        });
                        html += '</div>';
                    }
                    html += '</div>';
                });
            }

            html += '<div class="footer">Generated by Pulse</div>';
            document.getElementById('main-content').innerHTML = html;
        }

        function formatDateShort(dateStr) {
            var d = new Date(dateStr+'T12:00:00');
            var days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
            return days[d.getDay()] + ', ' + d.getDate() + ' ' + MONTH_NAMES[d.getMonth()];
        }

        // ---- Manage Clients View ----
        function loadManageView() {
            currentView = 'manage';
            var main = document.getElementById('main-content');
            main.innerHTML = '<div class="loading-spinner"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg>&nbsp; Loading...</div>';
            document.getElementById('right-panel').innerHTML = '';

            apiCall('/api/projects').then(function(res) {
                renderManageView(res.brands || [], res.projects || []);
            }).catch(function() {
                main.innerHTML = '<div class="loading-spinner" style="color:#ef4444">Cannot load data.</div>';
            });
        }

        function mgmtToast(msg) {
            var t = document.getElementById('mgmt-toast');
            if (!t) { t = document.createElement('div'); t.id='mgmt-toast'; t.className='mgmt-toast'; document.body.appendChild(t); }
            t.textContent = msg; t.classList.add('show');
            setTimeout(function(){ t.classList.remove('show'); }, 2000);
        }

        function renderManageView(brands, projectList) {
            // Group projects by brand
            var brandProjects = {};
            (projectList||[]).forEach(function(p){
                if (!brandProjects[p.brandId]) brandProjects[p.brandId] = [];
                brandProjects[p.brandId].push(p);
            });

            var html = '';
            html += '<div class="header" id="overview"><div class="header-label">Settings</div>';
            html += '<div class="header-date" style="display:flex;align-items:center;gap:12px">';
            html += '<button class="nav-arrow" onclick="loadDay(currentDate)" title="Back to report">&#9664;</button>';
            html += '<span>Manage Clients &amp; Projects</span></div>';
            html += '<div class="header-total">Add, rename, or remove clients and their projects</div></div>';

            // Add new brand
            html += '<div class="mgmt-card"><div class="mgmt-card-header"><div class="mgmt-card-title">Add New Client</div></div>';
            html += '<div class="mgmt-add-row">';
            html += '<input class="mgmt-input" id="new-brand-name" placeholder="Client name..." onkeydown="if(event.key===\\x27Enter\\x27)addBrand()">';
            html += '<input type="color" class="mgmt-color-input" id="new-brand-color" value="#6366f1">';
            html += '<button class="mgmt-btn mgmt-btn-primary" onclick="addBrand()">Add Client</button>';
            html += '</div></div>';

            // Brand cards
            if (brands.length === 0) {
                html += '<div class="mgmt-card"><div class="mgmt-empty">No clients yet. Create your first client above.</div></div>';
            }

            brands.forEach(function(brand) {
                var bProjects = brandProjects[brand.id] || [];
                html += '<div class="mgmt-card" id="brand-card-'+brand.id+'" data-name="'+escA(brand.name)+'" data-color="'+escA(brand.color)+'">';
                html += '<div class="mgmt-card-header">';
                html += '<div class="mgmt-card-title"><span class="mgmt-color" style="background:'+esc(brand.color)+'" onclick="editBrandColor('+brand.id+')" title="Change color"></span>';
                html += '<span id="brand-name-'+brand.id+'">'+esc(brand.name)+'</span>';
                html += '<span class="mgmt-badge">'+bProjects.length+' project'+(bProjects.length!==1?'s':'')+'</span></div>';
                html += '<div style="display:flex;gap:6px;align-items:center">';
                // Merge dropdown - only if more than 1 brand
                if (brands.length > 1) {
                    var mergeOpts = '<option value="">Merge into...</option>';
                    brands.forEach(function(b2){ if(b2.id!==brand.id) mergeOpts += '<option value="'+b2.id+'">'+esc(b2.name)+'</option>'; });
                    html += '<select class="mgmt-btn mgmt-btn-ghost" style="font-size:11px;padding:4px 6px;border:1px solid #e0e0e8;border-radius:6px;background:#fff;color:#8e8ea0;cursor:pointer" onchange="mergeBrand('+brand.id+',this)" title="Merge all projects into another client">'+mergeOpts+'</select>';
                }
                html += '<button class="mgmt-btn mgmt-btn-ghost" onclick="startRenameBrand('+brand.id+')" title="Rename">&#9998;</button>';
                html += '<button class="mgmt-btn mgmt-btn-danger" onclick="deleteBrand('+brand.id+')" title="Delete">&#10005;</button>';
                html += '</div></div>';

                // Projects list
                if (bProjects.length > 0) {
                    bProjects.forEach(function(p){
                        html += '<div class="mgmt-row" id="proj-row-'+p.id+'" data-name="'+escA(p.name)+'">';
                        html += '<span class="mgmt-color" style="background:'+esc(brand.color)+';width:14px;height:14px;opacity:0.5"></span>';
                        html += '<span class="mgmt-name" id="proj-name-'+p.id+'">'+esc(p.name)+'</span>';
                        // Move to another client dropdown
                        if (brands.length > 1) {
                            var moveOpts = '<option value="">Move to...</option>';
                            brands.forEach(function(b2){ if(b2.id!==brand.id) moveOpts += '<option value="'+b2.id+'">'+esc(b2.name)+'</option>'; });
                            html += '<select class="mgmt-btn mgmt-btn-ghost" style="font-size:11px;padding:3px 5px;border:1px solid #e0e0e8;border-radius:5px;background:#fff;color:#8e8ea0;cursor:pointer;max-width:120px" onchange="moveProject('+p.id+',this)" title="Move to another client">'+moveOpts+'</select>';
                        }
                        html += '<button class="mgmt-btn mgmt-btn-ghost" onclick="startRenameProject('+p.id+')" title="Rename">&#9998;</button>';
                        html += '<button class="mgmt-btn mgmt-btn-danger" onclick="deleteProject('+p.id+')" title="Delete">&#10005;</button>';
                        html += '</div>';
                    });
                } else {
                    html += '<div style="padding:8px 0;color:#a0a0b0;font-size:12px">No projects yet</div>';
                }

                // Add project row
                html += '<div class="mgmt-add-row" style="margin-top:8px">';
                html += '<input class="mgmt-input" id="new-proj-'+brand.id+'" placeholder="New project name..." onkeydown="if(event.key===\\x27Enter\\x27)addProject('+brand.id+')">';
                html += '<button class="mgmt-btn mgmt-btn-primary" onclick="addProject('+brand.id+')">Add</button>';
                html += '</div>';
                html += '</div>';
            });

            html += '<div class="footer">Generated by Pulse</div>';
            document.getElementById('main-content').innerHTML = html;
        }

        function addBrand() {
            var nameEl = document.getElementById('new-brand-name');
            var colorEl = document.getElementById('new-brand-color');
            var name = nameEl.value.trim();
            if (!name) { nameEl.focus(); return; }
            apiCall('/api/brand', {name:name, color:colorEl.value}).then(function(res){
                if (res.error) { mgmtToast('Error: '+res.error); return; }
                mgmtToast('Client "'+name+'" created');
                nameEl.value = '';
                loadSidebarBrands();
                loadManageView();
            }).catch(function(){ mgmtToast('Connection error'); });
        }

        function addProject(brandId) {
            var nameEl = document.getElementById('new-proj-'+brandId);
            var name = nameEl.value.trim();
            if (!name) { nameEl.focus(); return; }
            var brandCard = document.getElementById('brand-card-'+brandId);
            var brandColor = brandCard ? brandCard.dataset.color || '#6366f1' : '#6366f1';
            apiCall('/api/project', {brandId:brandId, name:name, color:brandColor}).then(function(res){
                if (res.error) { mgmtToast('Error: '+res.error); return; }
                mgmtToast('Project "'+name+'" created');
                nameEl.value = '';
                loadManageView();
            }).catch(function(){ mgmtToast('Connection error'); });
        }

        function moveProject(projId, selectEl) {
            var targetBrandId = parseInt(selectEl.value);
            if (!targetBrandId) return;
            var targetName = selectEl.options[selectEl.selectedIndex].text;
            var projName = (document.getElementById('proj-name-'+projId)||{}).textContent || 'Project';
            if (!confirm('Move "'+projName+'" to "'+targetName+'"?')) { selectEl.value=''; return; }
            apiCall('/api/project/update', {id:projId, brandId:targetBrandId}).then(function(res){
                if (res.error) { mgmtToast('Error: '+res.error); return; }
                mgmtToast('"'+projName+'" moved to "'+targetName+'"');
                loadSidebarBrands();
                loadManageView();
            }).catch(function(){ mgmtToast('Connection error'); });
        }

        function startRenameBrand(id) {
            var card = document.getElementById('brand-card-'+id);
            var currentName = card ? card.getAttribute('data-name') || '' : '';
            var el = document.getElementById('brand-name-'+id);
            if (!el) return;
            var inp = document.createElement('input');
            inp.className='mgmt-input'; inp.id='rename-brand-'+id; inp.value=currentName; inp.style.width='200px';
            inp.onkeydown=function(e){if(e.key==='Enter')saveBrandName(id);};
            var btn = document.createElement('button');
            btn.className='mgmt-btn mgmt-btn-primary'; btn.textContent='Save';
            btn.onclick=function(){saveBrandName(id);};
            el.textContent=''; el.appendChild(inp); el.appendChild(document.createTextNode(' ')); el.appendChild(btn);
            inp.focus(); inp.select();
        }

        function saveBrandName(id) {
            var inp = document.getElementById('rename-brand-'+id);
            if (!inp) return;
            var name = inp.value.trim();
            if (!name) return;
            apiCall('/api/brand/update', {id:id, name:name}).then(function(res){
                if (res.error) { mgmtToast('Error: '+res.error); return; }
                mgmtToast('Renamed');
                loadSidebarBrands();
                loadManageView();
            }).catch(function(){ mgmtToast('Connection error'); });
        }

        function startRenameProject(id) {
            var row = document.getElementById('proj-row-'+id);
            var currentName = row ? row.getAttribute('data-name') || '' : '';
            var el = document.getElementById('proj-name-'+id);
            if (!el) return;
            var inp = document.createElement('input');
            inp.className='mgmt-input'; inp.id='rename-proj-'+id; inp.value=currentName; inp.style.width='180px';
            inp.onkeydown=function(e){if(e.key==='Enter')saveProjectName(id);};
            var btn = document.createElement('button');
            btn.className='mgmt-btn mgmt-btn-primary'; btn.textContent='Save';
            btn.onclick=function(){saveProjectName(id);};
            el.textContent=''; el.appendChild(inp); el.appendChild(document.createTextNode(' ')); el.appendChild(btn);
            inp.focus(); inp.select();
        }

        function saveProjectName(id) {
            var inp = document.getElementById('rename-proj-'+id);
            if (!inp) return;
            var name = inp.value.trim();
            if (!name) return;
            apiCall('/api/project/update', {id:id, name:name}).then(function(res){
                if (res.error) { mgmtToast('Error: '+res.error); return; }
                mgmtToast('Renamed');
                loadManageView();
            }).catch(function(){ mgmtToast('Connection error'); });
        }

        var BRAND_COLORS = [
            '#6366f1','#8b5cf6','#a855f7','#d946ef','#ec4899',
            '#f43f5e','#ef4444','#f97316','#f59e0b','#eab308',
            '#84cc16','#22c55e','#10b981','#14b8a6','#06b6d4',
            '#0ea5e9','#3b82f6','#6366f1','#64748b','#78716c'
        ];

        function editBrandColor(id) {
            document.querySelectorAll('.color-palette-popup').forEach(function(p){p.remove();});
            var card = document.getElementById('brand-card-'+id);
            var dot = card ? card.querySelector('.mgmt-color') : null;
            if (!dot) return;

            var popup = document.createElement('div');
            popup.className='color-palette-popup';
            popup.style.cssText='position:absolute;z-index:999;background:#fff;border-radius:10px;padding:10px;box-shadow:0 4px 20px rgba(0,0,0,.15);display:flex;flex-wrap:wrap;gap:6px;width:180px';
            BRAND_COLORS.forEach(function(c){
                var swatch = document.createElement('div');
                swatch.style.cssText='width:28px;height:28px;border-radius:6px;cursor:pointer;background:'+c+';border:2px solid transparent;transition:border-color .1s';
                swatch.addEventListener('mouseenter',function(){swatch.style.borderColor='#1a1a2e';});
                swatch.addEventListener('mouseleave',function(){swatch.style.borderColor='transparent';});
                swatch.addEventListener('click',function(){
                    apiCall('/api/brand/update',{id:id,color:c}).then(function(res){
                        if(!res.error){mgmtToast('Color updated');loadSidebarBrands();loadManageView();}
                    });
                    popup.remove();
                });
                popup.appendChild(swatch);
            });

            var rect = dot.getBoundingClientRect();
            popup.style.position='fixed';
            popup.style.left=(rect.left)+'px';
            popup.style.top=(rect.bottom+6)+'px';
            document.body.appendChild(popup);

            var dismiss = function(e){if(!popup.contains(e.target)&&e.target!==dot){popup.remove();document.removeEventListener('click',dismiss);}};
            setTimeout(function(){document.addEventListener('click',dismiss);},10);
        }

        function editProjectColor(id) {
            var picker = document.createElement('input');
            picker.type='color'; picker.style.cssText='position:absolute;opacity:0';
            document.body.appendChild(picker);
            picker.addEventListener('input', function(){
                apiCall('/api/project/update', {id:id, color:picker.value}).then(function(res){
                    if (!res.error) { mgmtToast('Color updated'); loadManageView(); }
                });
            });
            picker.addEventListener('change', function(){ setTimeout(function(){try{document.body.removeChild(picker);}catch(e){}},100); });
            picker.click();
        }

        function deleteBrand(id) {
            var card = document.getElementById('brand-card-'+id);
            var name = card ? card.getAttribute('data-name') || '' : '';
            if (!confirm('Delete client "'+name+'" and all its projects?')) return;
            fetch(API_BASE + '/api/brand/delete', {
                method: 'POST',
                headers: {'Content-Type':'application/json'},
                body: JSON.stringify({id:id})
            }).then(function(r){ return r.text(); }).then(function(txt) {
                var res; try { res = JSON.parse(txt); } catch(e) { mgmtToast('Parse error: '+txt.substring(0,100)); return; }
                if (res.error) { mgmtToast('Error: '+res.error); return; }
                mgmtToast('Deleted');
                loadSidebarBrands();
                loadManageView();
            }).catch(function(e){ mgmtToast('Connection error: '+e.message); });
        }

        function deleteProject(id) {
            var row = document.getElementById('proj-row-'+id);
            var name = row ? row.getAttribute('data-name') || '' : '';
            if (!confirm('Delete project "'+name+'"?')) return;
            fetch(API_BASE + '/api/project/delete', {
                method: 'POST',
                headers: {'Content-Type':'application/json'},
                body: JSON.stringify({id:id})
            }).then(function(r){ return r.text(); }).then(function(txt) {
                var res; try { res = JSON.parse(txt); } catch(e) { mgmtToast('Parse error: '+txt.substring(0,100)); return; }
                if (res.error) { mgmtToast('Error: '+res.error); return; }
                mgmtToast('Deleted');
                loadManageView();
            }).catch(function(e){ mgmtToast('Connection error: '+e.message); });
        }

        function mergeBrand(sourceId, selectEl) {
            var targetId = parseInt(selectEl.value);
            if (!targetId || isNaN(targetId)) return;
            var sourceCard = document.getElementById('brand-card-'+sourceId);
            var sourceName = sourceCard ? sourceCard.getAttribute('data-name') || '' : '';
            var targetName = selectEl.options[selectEl.selectedIndex].textContent;
            if (!confirm('Merge "'+sourceName+'" into "'+targetName+'"?\\nAll projects will be moved. "'+sourceName+'" will be deleted.')) {
                selectEl.value = ''; return;
            }
            fetch(API_BASE + '/api/brand/merge', {
                method: 'POST',
                headers: {'Content-Type':'application/json'},
                body: JSON.stringify({sourceId:sourceId, targetId:targetId})
            }).then(function(r){ return r.text(); }).then(function(txt){
                var res; try { res = JSON.parse(txt); } catch(e) { mgmtToast('Parse error: '+txt.substring(0,100)); selectEl.value=''; return; }
                if (res.error) { mgmtToast('Error: '+res.error); selectEl.value=''; return; }
                mgmtToast('Merged into "'+targetName+'"');
                loadSidebarBrands();
                loadManageView();
            }).catch(function(e){ mgmtToast('Connection error: '+e.message); selectEl.value=''; });
        }

        // ---- View Switching ----
        function switchView(view) {
            if (view === 'day') loadDay(currentDate);
            else if (view === 'week') loadWeek(currentDate);
            else if (view === 'month') {
                var p = currentDate.split('-');
                loadMonth(parseInt(p[0]), parseInt(p[1]));
            }
        }

        // ---- Download JSON ----
        function downloadJSON() {
            var data = JSON.stringify(__reportData, null, 2);
            var blob = new Blob([data], {type:'application/json'});
            var url = URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url; a.download = 'report-'+currentDate+'.json';
            a.click(); URL.revokeObjectURL(url);
        }

        // ---- Classify Row ----
        function classifyRow(btn) {
            var row = btn.closest('.unassigned-row');
            var actId = parseInt(row.dataset.activityId);
            var sel = row.querySelector('.unassigned-select');
            var selVal = sel.value;
            if (!selVal) return;

            btn.disabled = true; btn.textContent = '...';
            resolveProjectId(selVal).then(function(pid) {
                var createRule = row.querySelector('.rule-check') ? row.querySelector('.rule-check').checked : false;
                var body = { activityIds: [actId], projectId: pid };

                if (createRule) {
                    var detail = row.querySelector('.unassigned-detail');
                    var text = detail ? detail.textContent.trim() : '';
                    if (text.indexOf('http') === 0 || text.indexOf('www.') === 0) {
                        try { var u = new URL(text.indexOf('http')!==0?'https://'+text:text); body.createRule=true; body.ruleType='urlDomain'; body.rulePattern=u.hostname; } catch(e){}
                    } else if (text.indexOf('/')!==-1||text.indexOf('~')===0) {
                        body.createRule=true; body.ruleType='terminalFolder'; body.rulePattern=text.split('/').pop()||text;
                    }
                }

                return apiCall('/api/classify', body);
            }).then(function(res) {
                if (res.error) { showApiError(res.error); btn.disabled=false; btn.textContent='Save'; return; }
                row.style.opacity='0.4'; row.style.pointerEvents='none'; btn.textContent='Done';
            }).catch(function() { showApiError('Cannot connect to Pulse.'); btn.disabled=false; btn.textContent='Save'; });
        }

        function classifyAll() {
            var rows = document.querySelectorAll('.unassigned-row');
            var promises = [];
            rows.forEach(function(row) {
                if (row.style.opacity==='0.4') return;
                var sel = row.querySelector('.unassigned-select');
                var selVal = sel.value;
                if (!selVal) return;
                var actId = parseInt(row.dataset.activityId);
                row.style.opacity='0.4'; row.style.pointerEvents='none';
                promises.push(resolveProjectId(selVal).then(function(pid) {
                    return apiCall('/api/classify',{activityIds:[actId],projectId:pid});
                }));
            });
            if (!promises.length) return;
            Promise.all(promises).then(function() {
                var btn = document.getElementById('save-all-btn');
                if (btn) { btn.textContent='All Saved'; btn.disabled=true; }
            }).catch(function() { showApiError('Cannot connect to Pulse.'); });
        }

        function showApiError(msg) {
            var el = document.getElementById('api-error');
            if (el) { el.textContent=msg; el.style.display='block'; }
        }

        // ---- Create Brand/Project ----
        var CREATE_COLORS = [
            {name:'Indigo',hex:'#6366f1'},{name:'Amber',hex:'#f59e0b'},{name:'Emerald',hex:'#10b981'},
            {name:'Red',hex:'#ef4444'},{name:'Purple',hex:'#8b5cf6'},{name:'Pink',hex:'#ec4899'},
            {name:'Teal',hex:'#14b8a6'},{name:'Orange',hex:'#f97316'},{name:'Cyan',hex:'#06b6d4'},
            {name:'Lime',hex:'#84cc16'}
        ];

        function buildColorPicker(selectedHex) {
            return CREATE_COLORS.map(function(c) {
                var sel = c.hex===selectedHex?' selected':'';
                return '<span class="color-swatch'+sel+'" data-color="'+c.hex+'" style="background:'+c.hex+'" title="'+c.name+'" onclick="pickColor(this)"></span>';
            }).join('');
        }
        function pickColor(el) { el.closest('.color-picker').querySelectorAll('.color-swatch').forEach(function(s){s.classList.remove('selected');}); el.classList.add('selected'); }
        function closeModal() { var o=document.querySelector('.create-modal-overlay'); if(o) o.remove(); }

        function showCreateBrand() {
            var html = '<div class="create-modal-overlay" onclick="if(event.target===this)closeModal()"><div class="create-modal"><h3>Create Brand</h3><div class="create-form">' +
                '<div><label>Brand Name</label><input type="text" id="create-brand-name" placeholder="e.g. Acme Corp" autofocus></div>' +
                '<div><label>Color</label><div class="color-picker">'+buildColorPicker('#6366f1')+'</div></div>' +
                '<div class="create-form-error" id="create-brand-error"></div>' +
                '<div class="create-form-actions"><button class="btn-cancel" onclick="closeModal()">Cancel</button><button class="btn-create" id="create-brand-btn" onclick="doCreateBrand()">Create</button></div>' +
                '</div></div></div>';
            document.body.insertAdjacentHTML('beforeend',html);
            document.getElementById('create-brand-name').focus();
        }

        function showCreateProject() {
            var brands = (__projectData&&__projectData.brands)||[];
            var opts = brands.map(function(b){return '<option value="'+b.id+'">'+esc(b.name)+'</option>';}).join('');
            if (!opts) opts='<option value="">No brands yet</option>';
            var html = '<div class="create-modal-overlay" onclick="if(event.target===this)closeModal()"><div class="create-modal"><h3>Create Project</h3><div class="create-form">' +
                '<div><label>Brand</label><select id="create-proj-brand">'+opts+'</select></div>' +
                '<div><label>Project Name</label><input type="text" id="create-proj-name" placeholder="e.g. Website Redesign"></div>' +
                '<div><label>Color</label><div class="color-picker">'+buildColorPicker('#10b981')+'</div></div>' +
                '<div class="create-form-error" id="create-proj-error"></div>' +
                '<div class="create-form-actions"><button class="btn-cancel" onclick="closeModal()">Cancel</button><button class="btn-create" id="create-proj-btn" onclick="doCreateProject()">Create</button></div>' +
                '</div></div></div>';
            document.body.insertAdjacentHTML('beforeend',html);
            document.getElementById('create-proj-name').focus();
        }

        function doCreateBrand() {
            var name=document.getElementById('create-brand-name').value.trim();
            var errEl=document.getElementById('create-brand-error');
            if(!name){errEl.textContent='Brand name is required';errEl.style.display='block';return;}
            var colorEl=document.querySelector('.create-modal .color-swatch.selected');
            var color=colorEl?colorEl.dataset.color:'#6366f1';
            var btn=document.getElementById('create-brand-btn'); btn.disabled=true; btn.textContent='Creating...';
            apiCall('/api/brand',{name:name,color:color}).then(function(res){
                if(res.error){errEl.textContent=res.error;errEl.style.display='block';btn.disabled=false;btn.textContent='Create';return;}
                closeModal(); refreshProjectDropdowns();
            }).catch(function(){errEl.textContent='Cannot connect to Pulse.';errEl.style.display='block';btn.disabled=false;btn.textContent='Create';});
        }

        function doCreateProject() {
            var brandId=parseInt(document.getElementById('create-proj-brand').value);
            var name=document.getElementById('create-proj-name').value.trim();
            var errEl=document.getElementById('create-proj-error');
            if(!brandId){errEl.textContent='Please select a brand';errEl.style.display='block';return;}
            if(!name){errEl.textContent='Project name is required';errEl.style.display='block';return;}
            var colorEl=document.querySelector('.create-modal .color-swatch.selected');
            var color=colorEl?colorEl.dataset.color:'#10b981';
            var btn=document.getElementById('create-proj-btn'); btn.disabled=true; btn.textContent='Creating...';
            apiCall('/api/project',{brandId:brandId,name:name,color:color}).then(function(res){
                if(res.error){errEl.textContent=res.error;errEl.style.display='block';btn.disabled=false;btn.textContent='Create';return;}
                closeModal(); refreshProjectDropdowns();
            }).catch(function(){errEl.textContent='Cannot connect to Pulse.';errEl.style.display='block';btn.disabled=false;btn.textContent='Create';});
        }

        function refreshProjectDropdowns() {
            apiCall('/api/projects').then(function(res) {
                if(res.error) return;
                if(res.brands) __projectData.brands=res.brands;
                if(res.projects) __projectData.projects=res.projects;
                var optHTML = buildProjectOptions(res.brands, res.projects);
                document.querySelectorAll('.unassigned-select').forEach(function(sel){ var prev=sel.value; sel.innerHTML=optHTML; if(prev) sel.value=prev; });
            }).catch(function(){});
        }

        function refreshBulkBarDropdown() {
            var sel = document.getElementById('bulk-project-select');
            if (!sel) return;
            apiCall('/api/projects').then(function(res) {
                sel.innerHTML = buildProjectOptions(res.brands, res.projects);
            }).catch(function(){});
        }

        // ---- Window Assign ----
        function showWindowAssign(btn) {
            document.querySelectorAll('.window-assign-popup').forEach(function(p){p.remove();});
            var row = btn.closest('.window-row');
            var ids = JSON.parse(row.dataset.ids||'[]');
            if(!ids.length) return;

            var popup = document.createElement('div');
            popup.className='window-assign-popup';
            popup.innerHTML='<span style="color:#8e8ea0;font-size:12px">Loading...</span>';
            row.after(popup);

            apiCall('/api/projects').then(function(res){
                var optHTML = buildProjectOptions(res.brands, res.projects);
                if(res.brands) __projectData.brands=res.brands;
                if(res.projects) __projectData.projects=res.projects;
                popup.innerHTML='<select class="wa-select">'+optHTML+'</select>'+
                    '<label class="wa-rule"><input type="checkbox" class="wa-rule-check" checked>Rule</label>'+
                    '<button class="wa-save" onclick="saveWindowAssign(this)">Save</button>'+
                    '<button class="wa-cancel" onclick="this.closest(\\x27.window-assign-popup\\x27).remove()">Cancel</button>';
            }).catch(function(){
                popup.innerHTML='<span style="color:#ef4444;font-size:12px">Cannot connect</span>'+
                    '<button class="wa-cancel" onclick="this.closest(\\x27.window-assign-popup\\x27).remove()">Close</button>';
            });
        }

        function saveWindowAssign(btn) {
            var popup = btn.closest('.window-assign-popup');
            var row = popup.previousElementSibling;
            var ids = JSON.parse(row.dataset.ids||'[]');
            var sel = popup.querySelector('.wa-select');
            var selVal = sel.value;
            if(!selVal||!ids.length) return;

            btn.disabled=true; btn.textContent='...';
            resolveProjectId(selVal).then(function(pid) {
                var body = {activityIds:ids, projectId:pid};
                var createRule = popup.querySelector('.wa-rule-check') ? popup.querySelector('.wa-rule-check').checked : false;
                if (createRule) {
                    var detail = row.querySelector('.window-detail');
                    var tag = row.querySelector('.tag');
                    var titleEl = row.querySelector('.window-title');
                    var text = detail ? detail.textContent.trim() : '';
                    if (tag) {
                        var tagText = tag.textContent.trim();
                        if (tagText.indexOf('/')!==-1||tagText.indexOf('~')===0) { body.createRule=true; body.ruleType='terminalFolder'; body.rulePattern=tagText.split('/').pop()||tagText; }
                    }
                    if (!body.createRule && text) {
                        if (text.indexOf('http')===0||text.indexOf('www.')===0) {
                            try { var u=new URL(text.indexOf('http')!==0?'https://'+text:text); body.createRule=true; body.ruleType='urlDomain'; body.rulePattern=u.hostname; } catch(e){}
                        } else if (text.indexOf('/')!==-1) { body.createRule=true; body.ruleType='terminalFolder'; body.rulePattern=text.split('/').pop()||text; }
                    }
                    if (!body.createRule && titleEl) {
                        var title=titleEl.textContent.trim();
                        if(title.length>3){body.createRule=true;body.ruleType='windowTitle';body.rulePattern=title;}
                    }
                }
                return apiCall('/api/classify',body);
            }).then(function(res){
                if(res.error){btn.disabled=false;btn.textContent='Save';return;}
                popup.remove();
                removeWindowRow(row);
            }).catch(function(){btn.disabled=false;btn.textContent='Save';});
        }

        function removeWindowRow(row) {
            row.style.transition='opacity .3s, max-height .3s, padding .3s, margin .3s';
            row.style.opacity='0';
            row.style.maxHeight=row.offsetHeight+'px';
            row.style.overflow='hidden';
            setTimeout(function(){
                row.style.maxHeight='0';
                row.style.padding='0 14px';
                row.style.margin='0';
            },50);
            setTimeout(function(){
                var card=row.closest('.app-card');
                row.remove();
                // If no more rows in this card, remove the card
                if(card && !card.querySelector('.window-row')){card.remove();}
            },350);
        }

        // ---- Suggestions ----
        function loadSuggestions() {
            var container = document.getElementById('suggestions-container');
            if (!container) return;
            var cardRulesMap = {};

            apiCall('/api/suggestions').then(function(res) {
                if (!res.suggestions || !res.suggestions.length) return;
                var brands = res.suggestions;

                var html = '<div class="suggestions-header"><span class="suggestions-title">Suggested Projects</span><span class="suggestions-badge">Auto-detected</span></div>';
                brands.forEach(function(brand, bi) {
                    (brand.projects||[]).forEach(function(proj, pi) {
                        var cardId = 'sug-'+bi+'-'+pi;
                        var appsStr = (proj.apps||[]).join(', ');
                        cardRulesMap[cardId] = proj.suggestedRules||[];

                        var rulesHTML = (proj.suggestedRules||[]).map(function(r){ return '<span class="suggestion-rule-tag">'+esc(r.ruleType)+': '+esc(r.pattern)+'</span>'; }).join('');

                        html += '<div class="suggestion-card" id="'+cardId+'" data-brand="'+escA(brand.suggestedName)+'" data-project="'+escA(proj.suggestedName)+'" data-token="'+escA(proj.fullToken)+'">';
                        html += '<div class="suggestion-card-header"><span class="suggestion-card-name">'+esc(brand.suggestedName)+' \\u203A '+esc(proj.suggestedName)+'</span>';
                        html += '<span class="suggestion-card-meta">'+proj.activityCount+' activities</span></div>';
                        html += '<div class="suggestion-card-apps">Apps: '+esc(appsStr)+'</div>';
                        html += '<div class="suggestion-card-rules">'+rulesHTML+'</div>';
                        html += '<div class="suggestion-card-actions"></div>';
                        html += '<div class="suggestion-card-form" style="display:none"></div>';
                        html += '</div>';
                    });
                });
                container.innerHTML = html;

                // Attach listeners
                container.querySelectorAll('.suggestion-card').forEach(function(card) {
                    var actions = card.querySelector('.suggestion-card-actions');
                    actions.innerHTML = '<button class="suggestion-btn-create sug-create-btn">Create</button>'+
                        '<button class="suggestion-btn-assign sug-assign-btn">Assign to...</button>'+
                        '<button class="suggestion-btn-dismiss sug-dismiss-btn">Dismiss</button>';

                    actions.querySelector('.sug-create-btn').addEventListener('click', function() { showSugCreateForm(card, cardRulesMap); });
                    actions.querySelector('.sug-assign-btn').addEventListener('click', function() { showSugAssignForm(card, cardRulesMap); });
                    actions.querySelector('.sug-dismiss-btn').addEventListener('click', function() {
                        var token = card.dataset.token;
                        if (token) apiCall('/api/suggestion/dismiss',{token:token}).catch(function(){});
                        card.classList.add('dismissed');
                    });
                });
            }).catch(function(){});
        }

        function getSugRules(card, rulesMap) {
            var data = rulesMap[card.id];
            if (data) return data.map(function(r){ return {ruleType:r.ruleType, pattern:r.pattern, isRegex:r.isRegex||false}; });
            return [];
        }

        function clearSugForm(card) { var f=card.querySelector('.suggestion-card-form'); f.style.display='none'; f.innerHTML=''; }

        function showSugCreateForm(card, rulesMap) {
            clearSugForm(card);
            var form = card.querySelector('.suggestion-card-form');
            var brandName = card.dataset.brand;
            var projName = card.dataset.project;
            form.style.display = 'block';
            form.innerHTML =
                '<div class="suggestion-assign-row" style="flex-wrap:wrap;gap:8px">'+
                '<div style="display:flex;flex-direction:column;gap:4px;flex:1;min-width:140px">'+
                '<label style="font-size:11px;color:#8e8ea0;font-weight:600">Brand Name</label>'+
                '<input type="text" class="sug-brand-input" value="'+escA(brandName)+'" style="padding:6px 10px;border:1px solid #e0e0e8;border-radius:6px;font-size:13px;color:#1a1a2e;outline:none"></div>'+
                '<div style="display:flex;flex-direction:column;gap:4px;flex:1;min-width:140px">'+
                '<label style="font-size:11px;color:#8e8ea0;font-weight:600">Project Name</label>'+
                '<input type="text" class="sug-proj-input" value="'+escA(projName)+'" style="padding:6px 10px;border:1px solid #e0e0e8;border-radius:6px;font-size:13px;color:#1a1a2e;outline:none"></div>'+
                '<div style="display:flex;align-items:flex-end;gap:6px;padding-bottom:1px">'+
                '<button class="suggestion-btn-create sug-confirm-btn" style="padding:7px 16px">Save</button>'+
                '<button class="suggestion-btn-dismiss sug-cancel-btn" style="padding:7px 10px">Cancel</button></div></div>';

            form.querySelector('.sug-confirm-btn').addEventListener('click', function() {
                var bName = form.querySelector('.sug-brand-input').value.trim();
                var pName = form.querySelector('.sug-proj-input').value.trim();
                if (!bName) { form.querySelector('.sug-brand-input').style.borderColor='#ef4444'; return; }
                if (!pName) pName = bName;
                var rules = getSugRules(card, rulesMap);
                var btn = form.querySelector('.sug-confirm-btn');
                btn.disabled=true; btn.textContent='Creating...';
                apiCall('/api/suggestion/accept',{brandName:bName,projectName:pName,rules:rules}).then(function(res){
                    if(res.error){btn.disabled=false;btn.textContent='Save';showApiError(res.error);return;}
                    card.innerHTML='<div style="padding:12px 0;color:#10b981;font-weight:600;font-size:13px">Created '+esc(bName)+' \\u203A '+esc(pName)+' ('+(res.assigned||0)+' activities auto-assigned)</div>';
                    setTimeout(function(){card.classList.add('dismissed');},3000);
                    refreshProjectDropdowns();
                }).catch(function(){btn.disabled=false;btn.textContent='Save';showApiError('Cannot connect to Pulse.');});
            });
            form.querySelector('.sug-cancel-btn').addEventListener('click', function() { clearSugForm(card); });
            form.querySelector('.sug-brand-input').focus();
            form.querySelector('.sug-brand-input').select();
        }

        function showSugAssignForm(card, rulesMap) {
            clearSugForm(card);
            var form = card.querySelector('.suggestion-card-form');
            form.style.display='block';
            form.innerHTML='<div class="suggestion-assign-row">'+
                '<select class="suggestion-assign-select"><option value="">Loading...</option></select>'+
                '<button class="suggestion-btn-create sug-assign-confirm" style="font-size:11px;padding:5px 12px">Assign</button>'+
                '<button class="suggestion-btn-dismiss sug-assign-cancel" style="font-size:11px;padding:5px 10px">Cancel</button></div>';

            form.querySelector('.sug-assign-confirm').addEventListener('click', function(){
                var selVal=form.querySelector('select').value;
                if(!selVal) return;
                var rules=getSugRules(card,rulesMap);
                var btn=form.querySelector('.sug-assign-confirm');
                btn.disabled=true;btn.textContent='...';
                resolveProjectId(selVal).then(function(pid){
                    return apiCall('/api/suggestion/accept',{existingProjectId:pid,rules:rules});
                }).then(function(res){
                    if(res.error){btn.disabled=false;btn.textContent='Assign';showApiError(res.error);return;}
                    card.innerHTML='<div style="padding:12px 0;color:#10b981;font-weight:600;font-size:13px">Rules assigned ('+(res.assigned||0)+' activities matched)</div>';
                    setTimeout(function(){card.classList.add('dismissed');},3000);
                    refreshProjectDropdowns();
                }).catch(function(){btn.disabled=false;btn.textContent='Assign';});
            });
            form.querySelector('.sug-assign-cancel').addEventListener('click', function(){ clearSugForm(card); });

            apiCall('/api/projects').then(function(res){
                var optHTML = buildProjectOptions(res.brands, res.projects);
                var sel = form.querySelector('select');
                if(sel) sel.innerHTML=optHTML;
            }).catch(function(){
                var sel=form.querySelector('select');
                if(sel) sel.innerHTML='<option value="">Cannot load projects</option>';
            });
        }

        // ---- Analyze with AI ----
        function analyzeWithAI() {
            var btn = document.getElementById('analyze-btn');
            btn.disabled = true;
            btn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" style="animation:spin 1s linear infinite"><circle cx="8" cy="8" r="6"/></svg> Analyzing\\u2026';

            try {
                var data = __reportData;
                var apiKey = localStorage.getItem('activity-tracker-api-key');
                if (!apiKey) {
                    apiKey = prompt('Enter your Claude API key to analyze:');
                    if (!apiKey) { resetAnalyzeBtn(); return; }
                    localStorage.setItem('activity-tracker-api-key', apiKey);
                }

                var tl = data.timeline || [];
                var lines = tl.map(function(e) {
                    var t = e.timestamp ? new Date(e.timestamp).toTimeString().substring(0,5) : '';
                    var extra = [e.extraInfo, e.url].filter(Boolean).join(' ');
                    var suffix = extra ? ' ('+extra+')' : '';
                    return t+' '+e.appName+': '+e.windowTitle+' ['+e.durationSeconds+'s]'+suffix;
                }).join('\\n');

                var systemMsg = 'You are a timesheet grouping tool. Group app usage entries by project/client and sum durations. Identify projects by recurring keywords in window titles, URLs, file paths. Same keyword across different apps = same project. Entries with no match go under Other. Sort by total time descending. Convert seconds to Xh Ym. Output ONLY the markdown format shown. No commentary, no tips, no analysis, no headers like Productivity Analysis.';
                var userMsg = 'Group by project:\\n\\n' + lines;

                fetch('https://api.anthropic.com/v1/messages', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'x-api-key': apiKey,
                        'anthropic-version': '2023-06-01',
                        'anthropic-dangerous-direct-browser-access': 'true'
                    },
                    body: JSON.stringify({
                        model: 'claude-haiku-4-5-20251001',
                        max_tokens: 2000,
                        system: systemMsg,
                        messages: [{role:'user',content:userMsg},{role:'assistant',content:'## Projects'}]
                    })
                }).then(function(r){return r.json();}).then(function(res) {
                    if (res.error) {
                        if (res.error.message && res.error.message.includes('invalid')) localStorage.removeItem('activity-tracker-api-key');
                        alert('API Error: '+(res.error.message||JSON.stringify(res.error)));
                        resetAnalyzeBtn(); return;
                    }
                    var raw = (res.content||[]).map(function(b){return b.text||'';}).join('\\n');
                    var text = '## Projects' + raw;
                    showAnalysisResult(text);
                    resetAnalyzeBtn();
                    btn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg> Re-analyze';
                }).catch(function(e) { alert('Network error: '+e.message); resetAnalyzeBtn(); });
            } catch(e) { alert('Error: '+e.message); resetAnalyzeBtn(); }
        }

        function resetAnalyzeBtn() {
            var btn = document.getElementById('analyze-btn');
            if (!btn) return;
            btn.disabled = false;
            btn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg> Analyze with AI';
        }

        function showAnalysisResult(text) {
            var existing = document.getElementById('analysis');
            if (existing) existing.remove();
            var div = document.createElement('div');
            div.id = 'analysis';
            div.className = 'analysis-section';
            div.innerHTML = '<div class="analysis-header">'+
                '<div class="analysis-icon"><svg viewBox="0 0 16 16" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1"/></svg></div>'+
                '<span class="analysis-title">Project Analysis</span>'+
                '<span class="analysis-badge">AI</span></div>'+
                '<div class="analysis-body">'+mdToHtml(text)+'</div>';
            var overview = document.querySelector('.overview');
            if (overview) overview.parentNode.insertBefore(div, overview);
            div.scrollIntoView({behavior:'smooth',block:'start'});
        }

        function mdToHtml(text) {
            var lines = text.split('\\n');
            var html = '';
            var inList = false;
            for (var i=0;i<lines.length;i++) {
                var line = lines[i].trim();
                if (!line) { if(inList){html+='</ul>';inList=false;} continue; }
                if (line.indexOf('## ')===0 && line.indexOf('### ')!==0) {
                    if(inList){html+='</ul>';inList=false;}
                    html += '<h2>'+esc(line.substring(3))+'</h2>';
                } else if (line.indexOf('### ')===0) {
                    if(inList){html+='</ul>';inList=false;}
                    html += '<h3>'+esc(line.substring(4))+'</h3>';
                } else if (line.indexOf('Total:')===0||line.indexOf('**Total')===0) {
                    html += '<div class="project-total">'+esc(line.replace(/\\*\\*/g,''))+'</div>';
                } else if (line.indexOf('- ')===0) {
                    if(!inList){html+='<ul>';inList=true;}
                    html += '<li>'+esc(line.substring(2))+'</li>';
                } else {
                    if(inList){html+='</ul>';inList=false;}
                    html += '<p>'+esc(line)+'</p>';
                }
            }
            if(inList) html+='</ul>';
            return html;
        }

        // ---- Bulk Selection ----
        function toggleBulkCheck(cb) {
            var row = cb.closest('.window-row');
            if(cb.checked){row.classList.add('selected');}else{row.classList.remove('selected');}
            var card = row.closest('.app-card');
            if(card){
                var all=card.querySelectorAll('.bulk-check');
                var checked=card.querySelectorAll('.bulk-check:checked');
                var sa=card.querySelector('.select-all-check');
                if(sa){sa.checked=checked.length===all.length;sa.indeterminate=checked.length>0&&checked.length<all.length;}
            }
            updateBulkBar();
        }

        function toggleSelectAll(sa) {
            var card=sa.closest('.app-card');
            if(!card) return;
            card.querySelectorAll('.bulk-check').forEach(function(cb){
                cb.checked=sa.checked;
                var row=cb.closest('.window-row');
                if(sa.checked){row.classList.add('selected');}else{row.classList.remove('selected');}
            });
            updateBulkBar();
        }

        function updateBulkBar() {
            var selected=document.querySelectorAll('.bulk-check:checked');
            var bar=document.getElementById('bulk-bar');
            if(selected.length>0){
                bar.classList.add('visible');
                document.getElementById('bulk-count').textContent=selected.length+' item'+(selected.length>1?'s':'')+' selected';
            } else {
                bar.classList.remove('visible');
            }
        }

        function clearBulkSelection() {
            document.querySelectorAll('.bulk-check:checked').forEach(function(cb){cb.checked=false;cb.closest('.window-row').classList.remove('selected');});
            document.querySelectorAll('.select-all-check').forEach(function(sa){sa.checked=false;sa.indeterminate=false;});
            updateBulkBar();
        }

        function bulkAssign() {
            var sel=document.getElementById('bulk-project-select');
            if(!sel) return;
            var selVal=sel.value;
            if(!selVal) return;
            var checked=document.querySelectorAll('.bulk-check:checked');
            if(!checked.length) return;
            var allIds=[];
            checked.forEach(function(cb){
                var row=cb.closest('.window-row');
                if(!row) return;
                var idsStr=row.getAttribute('data-ids')||'[]';
                try{var ids=JSON.parse(idsStr);allIds=allIds.concat(ids);}catch(e){}
            });
            if(!allIds.length) return;

            var btn=document.getElementById('bulk-assign-btn');
            btn.disabled=true;btn.textContent='Assigning...';
            resolveProjectId(selVal).then(function(pid) {
                return apiCall('/api/classify',{activityIds:allIds,projectId:pid});
            }).then(function(res){
                if(res.error){btn.disabled=false;btn.textContent='Assign All';showApiError(res.error);return;}
                checked.forEach(function(cb){
                    var row=cb.closest('.window-row');
                    cb.checked=false;
                    row.classList.remove('selected');
                    removeWindowRow(row);
                });
                document.querySelectorAll('.select-all-check').forEach(function(sa){sa.checked=false;sa.indeterminate=false;});
                btn.textContent='Done!';
                setTimeout(function(){btn.disabled=false;btn.textContent='Assign All';updateBulkBar();},1500);
            }).catch(function(){btn.disabled=false;btn.textContent='Assign All';});
        }
        </script>
        </body>
        </html>
        """
    }
}
