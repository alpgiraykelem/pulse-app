import Foundation

enum DashboardGenerator {
    private static var reportsDir: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ActivityTracker/reports")

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    struct DashboardData: Codable {
        let generatedAt: String
        let today: DaySummary
        let weekDays: [DaySummary]
        let monthDays: [DaySummary]
        let monthLabel: String
    }

    static func generate(store: ActivityStore) -> URL {
        let fileURL = reportsDir.appendingPathComponent("dashboard.html")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        // Today
        let todaySummary = (try? store.queryDay(date: todayStr)) ?? DaySummary(
            date: todayStr, totalSeconds: 0, apps: [],
            wallClockSeconds: 0, activeTrackingSeconds: 0,
            firstActivity: nil, lastActivity: nil
        )

        // Week (last 7 days)
        let weekDays = (try? store.queryWeek()) ?? []

        // Month
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let monthDays = (try? store.queryMonth(year: year, month: month)) ?? []

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let monthLabel = monthFormatter.string(from: now)

        let data = DashboardData(
            generatedAt: todayStr,
            today: todaySummary,
            weekDays: weekDays,
            monthDays: monthDays,
            monthLabel: monthLabel
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonStr = (try? encoder.encode(data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let html = buildDashboardHTML(data: data, json: jsonStr)
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - HTML

    private static func buildDashboardHTML(data: DashboardData, json: String) -> String {
        let todayDate = formatDateDisplay(data.today.date)
        let todayTotal = dur(data.today.totalSeconds)
        let weekTotal = dur(data.weekDays.reduce(0) { $0 + $1.totalSeconds })
        let monthTotal = dur(data.monthDays.reduce(0) { $0 + $1.totalSeconds })
        let weekDayCount = data.weekDays.count
        let monthDayCount = data.monthDays.count

        // Build week bar chart data
        let weekBarsHTML = buildWeekBars(days: data.weekDays)

        // Build month trend data
        let monthTrendHTML = buildMonthTrend(days: data.monthDays)

        // Build today's app breakdown
        let todayAppsHTML = buildAppBreakdown(summary: data.today)

        // Build week app totals
        let weekAppsHTML = buildWeekAppTotals(days: data.weekDays)

        // Build month app totals
        let monthAppsHTML = buildMonthAppTotals(days: data.monthDays)

        // Build today donut
        let todayDonut = buildDonutSegments(apps: data.today.apps)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Pulse Dashboard</title>
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif;
            background: #f8f9fb; color: #1a1a2e; min-height:100vh;
            -webkit-font-smoothing: antialiased;
        }
        .container { max-width:960px; margin:0 auto; padding:40px 24px 80px; }

        .header { margin-bottom:32px; }
        .header-label { font-size:12px; color:#8e8ea0; text-transform:uppercase; letter-spacing:2px; font-weight:600; margin-bottom:6px; }
        .header-title { font-size:28px; font-weight:700; color:#1a1a2e; margin-bottom:4px; }
        .header-sub { font-size:14px; color:#6b6b80; }

        /* Tabs */
        .tabs { display:flex; gap:4px; margin-bottom:24px; background:#eef0f5; padding:4px; border-radius:10px; width:fit-content; }
        .tab {
            padding:8px 20px; border-radius:8px; font-size:13px; font-weight:600;
            color:#6b6b80; cursor:pointer; border:none; background:transparent;
            transition: background .15s, color .15s, box-shadow .15s;
        }
        .tab:hover { color:#1a1a2e; }
        .tab.active { background:#fff; color:#6366f1; box-shadow:0 1px 3px rgba(0,0,0,0.08); }

        .tab-content { display:none; }
        .tab-content.active { display:block; }

        /* Summary cards */
        .summary-row { display:grid; grid-template-columns:repeat(3,1fr); gap:12px; margin-bottom:28px; }
        .summary-card {
            background:#fff; border-radius:12px; padding:18px 22px;
            box-shadow:0 1px 3px rgba(0,0,0,0.06);
        }
        .summary-label { font-size:11px; color:#8e8ea0; text-transform:uppercase; letter-spacing:1px; font-weight:600; margin-bottom:6px; }
        .summary-value { font-size:24px; font-weight:700; color:#1a1a2e; }
        .summary-sub { font-size:12px; color:#a0a0b0; margin-top:2px; }

        /* Chart card */
        .chart-card {
            background:#fff; border-radius:14px; padding:24px; margin-bottom:20px;
            box-shadow:0 1px 3px rgba(0,0,0,0.06);
        }
        .chart-title { font-size:14px; font-weight:700; color:#1a1a2e; margin-bottom:16px; }

        /* Bar chart */
        .bar-chart { display:flex; align-items:flex-end; gap:8px; height:180px; padding-bottom:28px; position:relative; }
        .bar-col { flex:1; display:flex; flex-direction:column; align-items:center; gap:4px; height:100%; justify-content:flex-end; }
        .bar-fill { width:100%; max-width:48px; border-radius:6px 6px 0 0; background:linear-gradient(180deg,#6366f1,#818cf8); transition:height .3s; min-height:2px; }
        .bar-label { font-size:10px; color:#8e8ea0; font-weight:600; position:absolute; bottom:0; white-space:nowrap; }
        .bar-value { font-size:10px; color:#6b6b80; font-weight:600; }
        .bar-col-inner { display:flex; flex-direction:column; align-items:center; gap:4px; width:100%; }

        /* Line chart (SVG) */
        .line-chart-container { position:relative; height:200px; }
        .line-chart-svg { width:100%; height:100%; }
        .line-chart-path { fill:none; stroke:#6366f1; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
        .line-chart-area { fill:url(#areaGrad); }
        .line-chart-dot { fill:#6366f1; stroke:#fff; stroke-width:2; }
        .line-chart-labels { display:flex; justify-content:space-between; margin-top:8px; }
        .line-chart-label { font-size:10px; color:#8e8ea0; }

        /* Donut */
        .donut-section { display:grid; grid-template-columns:180px 1fr; gap:24px; align-items:center; }
        .donut-container { position:relative; width:160px; height:160px; margin:0 auto; }
        .donut-center { position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); text-align:center; }
        .donut-total { font-size:20px; font-weight:700; color:#1a1a2e; }
        .donut-label { font-size:11px; color:#a0a0b0; }

        /* App list */
        .app-list { display:flex; flex-direction:column; gap:8px; }
        .app-row { display:flex; align-items:center; gap:10px; }
        .app-dot { width:10px; height:10px; border-radius:50%; flex-shrink:0; }
        .app-name { flex:1; font-size:13px; color:#4a4a5a; }
        .app-time { font-size:13px; font-weight:600; color:#1a1a2e; min-width:60px; text-align:right; }
        .app-pct { font-size:11px; color:#a0a0b0; width:40px; text-align:right; }
        .app-bar-track { width:80px; height:4px; background:#f0f0f5; border-radius:2px; flex-shrink:0; }
        .app-bar-fill { height:100%; border-radius:2px; }

        .empty-state { text-align:center; padding:48px; color:#a0a0b0; font-size:14px; }

        .section-title { font-size:12px; color:#8e8ea0; text-transform:uppercase; letter-spacing:2px; font-weight:600; margin-bottom:16px; }

        .footer { margin-top:48px; text-align:center; font-size:12px; color:#c0c0c8; }

        @media (max-width:640px) {
            .summary-row { grid-template-columns:1fr; }
            .donut-section { grid-template-columns:1fr; }
            .container { padding:24px 16px 60px; }
        }
        </style>
        </head>
        <body>
        <div class="container">
            <div class="header">
                <div class="header-label">Pulse</div>
                <div class="header-title">Dashboard</div>
                <div class="header-sub">Generated \(todayDate)</div>
            </div>

            <div class="tabs">
                <button class="tab active" onclick="switchTab('daily')">Daily</button>
                <button class="tab" onclick="switchTab('weekly')">Weekly</button>
                <button class="tab" onclick="switchTab('monthly')">Monthly</button>
            </div>

            <!-- DAILY TAB -->
            <div class="tab-content active" id="tab-daily">
                <div class="summary-row">
                    <div class="summary-card">
                        <div class="summary-label">Total Time</div>
                        <div class="summary-value">\(todayTotal)</div>
                        <div class="summary-sub">\(todayDate)</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Wall Clock</div>
                        <div class="summary-value">\(dur(data.today.wallClockSeconds))</div>
                        <div class="summary-sub">\(data.today.firstActivity ?? "–") – \(data.today.lastActivity ?? "–")</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Apps Used</div>
                        <div class="summary-value">\(data.today.apps.count)</div>
                        <div class="summary-sub">applications</div>
                    </div>
                </div>

                \(data.today.totalSeconds > 0 ? """
                <div class="chart-card">
                    <div class="chart-title">App Distribution</div>
                    <div class="donut-section">
                        <div class="donut-container">
                            <svg viewBox="0 0 36 36" width="160" height="160">
                                \(todayDonut)
                            </svg>
                            <div class="donut-center">
                                <div class="donut-total">\(todayTotal)</div>
                                <div class="donut-label">total</div>
                            </div>
                        </div>
                        <div class="app-list">
                            \(todayAppsHTML)
                        </div>
                    </div>
                </div>
                """ : "<div class=\"empty-state\">No activity tracked today yet.</div>")
            </div>

            <!-- WEEKLY TAB -->
            <div class="tab-content" id="tab-weekly">
                <div class="summary-row">
                    <div class="summary-card">
                        <div class="summary-label">Week Total</div>
                        <div class="summary-value">\(weekTotal)</div>
                        <div class="summary-sub">last 7 days</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Active Days</div>
                        <div class="summary-value">\(weekDayCount)</div>
                        <div class="summary-sub">of 7 days</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Daily Average</div>
                        <div class="summary-value">\(weekDayCount > 0 ? dur(data.weekDays.reduce(0) { $0 + $1.totalSeconds } / weekDayCount) : "–")</div>
                        <div class="summary-sub">per active day</div>
                    </div>
                </div>

                \(data.weekDays.isEmpty ? "<div class=\"empty-state\">No activity data for the past week.</div>" : """
                <div class="chart-card">
                    <div class="chart-title">Daily Breakdown</div>
                    \(weekBarsHTML)
                </div>

                <div class="chart-card">
                    <div class="chart-title">App Totals (7 Days)</div>
                    <div class="app-list">
                        \(weekAppsHTML)
                    </div>
                </div>
                """)
            </div>

            <!-- MONTHLY TAB -->
            <div class="tab-content" id="tab-monthly">
                <div class="summary-row">
                    <div class="summary-card">
                        <div class="summary-label">Month Total</div>
                        <div class="summary-value">\(monthTotal)</div>
                        <div class="summary-sub">\(esc(data.monthLabel))</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Active Days</div>
                        <div class="summary-value">\(monthDayCount)</div>
                        <div class="summary-sub">this month</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Daily Average</div>
                        <div class="summary-value">\(monthDayCount > 0 ? dur(data.monthDays.reduce(0) { $0 + $1.totalSeconds } / monthDayCount) : "–")</div>
                        <div class="summary-sub">per active day</div>
                    </div>
                </div>

                \(data.monthDays.isEmpty ? "<div class=\"empty-state\">No activity data for this month.</div>" : """
                <div class="chart-card">
                    <div class="chart-title">Daily Trend – \(esc(data.monthLabel))</div>
                    \(monthTrendHTML)
                </div>

                <div class="chart-card">
                    <div class="chart-title">App Totals – \(esc(data.monthLabel))</div>
                    <div class="app-list">
                        \(monthAppsHTML)
                    </div>
                </div>
                """)
            </div>

            <div class="footer">Generated by Pulse</div>
        </div>
        <script>var __dashboardData = \(json);</script>
        <script>
        function switchTab(name) {
            document.querySelectorAll('.tab').forEach(function(t) { t.classList.remove('active'); });
            document.querySelectorAll('.tab-content').forEach(function(c) { c.classList.remove('active'); });
            document.getElementById('tab-' + name).classList.add('active');
            // Activate matching tab button
            document.querySelectorAll('.tab').forEach(function(t) {
                if (t.textContent.trim().toLowerCase() === name) t.classList.add('active');
            });
        }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Week Bar Chart

    private static func buildWeekBars(days: [DaySummary]) -> String {
        guard !days.isEmpty else { return "" }
        let maxSeconds = days.map(\.totalSeconds).max() ?? 1

        // Build all 7 days (fill gaps)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayNameFormatter = DateFormatter()
        dayNameFormatter.dateFormat = "EEE"
        let dayNumFormatter = DateFormatter()
        dayNumFormatter.dateFormat = "d"

        let calendar = Calendar.current
        let today = Date()
        var dayMap: [String: DaySummary] = [:]
        for d in days { dayMap[d.date] = d }

        var barsHTML = "<div class=\"bar-chart\">\n"
        for offset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = formatter.string(from: date)
            let dayName = dayNameFormatter.string(from: date)
            let seconds = dayMap[dateStr]?.totalSeconds ?? 0
            let heightPct = maxSeconds > 0 ? Double(seconds) / Double(maxSeconds) * 100 : 0
            let valueStr = seconds > 0 ? dur(seconds) : ""

            barsHTML += """
            <div class="bar-col">
                <div class="bar-col-inner">
                    <span class="bar-value">\(valueStr)</span>
                    <div class="bar-fill" style="height:\(String(format:"%.1f", max(heightPct, 1)))%"></div>
                </div>
                <span class="bar-label">\(dayName)</span>
            </div>
            """
        }
        barsHTML += "</div>\n"
        return barsHTML
    }

    // MARK: - Month Trend (SVG Line Chart)

    private static func buildMonthTrend(days: [DaySummary]) -> String {
        guard !days.isEmpty else { return "" }

        // Build full month day list
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let currentDay = calendar.component(.day, from: now)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var dayMap: [String: Int] = [:]
        for d in days { dayMap[d.date] = d.totalSeconds }

        // Only include days up to today
        var points: [(day: Int, seconds: Int)] = []
        for day in 1...currentDay {
            let dateStr = String(format: "%04d-%02d-%02d", year, month, day)
            points.append((day: day, seconds: dayMap[dateStr] ?? 0))
        }

        guard points.count > 1 else {
            if let p = points.first, p.seconds > 0 {
                return "<div class=\"empty-state\">Only 1 day of data: \(dur(p.seconds))</div>"
            }
            return ""
        }

        let maxSeconds = max(points.map(\.seconds).max() ?? 1, 1)
        let width: Double = 900
        let height: Double = 180
        let padX: Double = 10
        let padY: Double = 10
        let chartW = width - padX * 2
        let chartH = height - padY * 2

        let xStep = chartW / Double(points.count - 1)

        var pathParts: [String] = []
        var areaParts: [String] = []
        var dots: [String] = []

        for (i, p) in points.enumerated() {
            let x = padX + Double(i) * xStep
            let y = padY + chartH - (Double(p.seconds) / Double(maxSeconds) * chartH)
            let cmd = i == 0 ? "M" : "L"
            pathParts.append("\(cmd)\(String(format:"%.1f",x)),\(String(format:"%.1f",y))")
            areaParts.append("\(cmd)\(String(format:"%.1f",x)),\(String(format:"%.1f",y))")
            if p.seconds > 0 {
                dots.append("<circle class=\"line-chart-dot\" cx=\"\(String(format:"%.1f",x))\" cy=\"\(String(format:"%.1f",y))\" r=\"3\"/>")
            }
        }

        // Close area path
        let lastX = padX + Double(points.count - 1) * xStep
        areaParts.append("L\(String(format:"%.1f",lastX)),\(String(format:"%.1f",padY + chartH))")
        areaParts.append("L\(String(format:"%.1f",padX)),\(String(format:"%.1f",padY + chartH))Z")

        // Labels (show every ~5 days)
        var labels: [String] = []
        let step = max(1, points.count / 6)
        for i in stride(from: 0, to: points.count, by: step) {
            labels.append("<span class=\"line-chart-label\">\(points[i].day)</span>")
        }
        if points.count - 1 > (points.count / step) * step {
            labels.append("<span class=\"line-chart-label\">\(points.last!.day)</span>")
        }

        return """
        <div class="line-chart-container">
            <svg class="line-chart-svg" viewBox="0 0 \(String(format:"%.0f",width)) \(String(format:"%.0f",height))" preserveAspectRatio="none">
                <defs>
                    <linearGradient id="areaGrad" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stop-color="#6366f1" stop-opacity="0.2"/>
                        <stop offset="100%" stop-color="#6366f1" stop-opacity="0.02"/>
                    </linearGradient>
                </defs>
                <path class="line-chart-area" d="\(areaParts.joined())"/>
                <path class="line-chart-path" d="\(pathParts.joined())"/>
                \(dots.joined(separator:"\n"))
            </svg>
        </div>
        <div class="line-chart-labels">\(labels.joined())</div>
        """
    }

    // MARK: - App Breakdown

    private static func buildAppBreakdown(summary: DaySummary) -> String {
        let colors = appColors()
        return summary.apps.prefix(10).enumerated().map { i, app -> String in
            let color = colors[i % colors.count]
            let pct = summary.totalSeconds > 0 ? Double(app.totalSeconds) / Double(summary.totalSeconds) * 100 : 0
            return """
            <div class="app-row">
                <span class="app-dot" style="background:\(color)"></span>
                <span class="app-name">\(esc(app.appName))</span>
                <span class="app-time">\(dur(app.totalSeconds))</span>
                <span class="app-pct">\(String(format:"%.0f", pct))%</span>
            </div>
            """
        }.joined(separator:"\n")
    }

    private static func buildWeekAppTotals(days: [DaySummary]) -> String {
        buildAggregatedApps(days: days)
    }

    private static func buildMonthAppTotals(days: [DaySummary]) -> String {
        buildAggregatedApps(days: days)
    }

    private static func buildAggregatedApps(days: [DaySummary]) -> String {
        var appMap: [String: Int] = [:]
        for day in days {
            for app in day.apps {
                appMap[app.appName, default: 0] += app.totalSeconds
            }
        }
        let sorted = appMap.sorted { $0.value > $1.value }
        let totalSeconds = sorted.reduce(0) { $0 + $1.value }
        let maxSeconds = sorted.first?.value ?? 1
        let colors = appColors()

        return sorted.prefix(15).enumerated().map { i, entry -> String in
            let color = colors[i % colors.count]
            let pct = totalSeconds > 0 ? Double(entry.value) / Double(totalSeconds) * 100 : 0
            let barW = Double(entry.value) / Double(maxSeconds) * 100
            return """
            <div class="app-row">
                <span class="app-dot" style="background:\(color)"></span>
                <span class="app-name">\(esc(entry.key))</span>
                <div class="app-bar-track"><div class="app-bar-fill" style="width:\(String(format:"%.1f",barW))%;background:\(color)"></div></div>
                <span class="app-time">\(dur(entry.value))</span>
                <span class="app-pct">\(String(format:"%.0f", pct))%</span>
            </div>
            """
        }.joined(separator:"\n")
    }

    // MARK: - Donut

    private static func buildDonutSegments(apps: [ActivitySummary]) -> String {
        guard !apps.isEmpty else { return "" }
        let total = apps.reduce(0) { $0 + $1.totalSeconds }
        guard total > 0 else { return "" }

        let radius: Double = 15.9155
        let circumference = 2 * Double.pi * radius
        var offset: Double = 25
        let colors = appColors()

        return apps.prefix(10).enumerated().map { i, app -> String in
            let fraction = Double(app.totalSeconds) / Double(total)
            let dashLen = fraction * circumference
            let gap = circumference - dashLen
            let color = colors[i % colors.count]

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

    // MARK: - Helpers

    private static func appColors() -> [String] {
        ["#6366f1", "#f59e0b", "#10b981", "#ef4444", "#8b5cf6",
         "#ec4899", "#14b8a6", "#f97316", "#06b6d4", "#84cc16"]
    }

    private static func dur(_ seconds: Int) -> String {
        HTMLReportGenerator.dur(seconds)
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
}
