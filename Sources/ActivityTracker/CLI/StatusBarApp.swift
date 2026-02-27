import Cocoa

private let colorOptions: [(name: String, hex: String)] = [
    ("Indigo", "#6366f1"), ("Amber", "#f59e0b"), ("Emerald", "#10b981"),
    ("Red", "#ef4444"), ("Purple", "#8b5cf6"), ("Pink", "#ec4899"),
    ("Teal", "#14b8a6"), ("Orange", "#f97316"), ("Cyan", "#06b6d4"),
    ("Lime", "#84cc16")
]

final class StatusBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: WindowMonitor?
    private var store: ActivityStore!
    private var merger: HeartbeatMerger?
    private var displayTimer: Timer?
    private var signalHandler: SignalHandler?
    private var isAnalyzing = false
    private(set) var isTracking = false
    private var projectMatcher: ProjectMatcher?
    private var apiServer: LocalAPIServer?

    private let pollingInterval: TimeInterval

    init(interval: TimeInterval) {
        self.pollingInterval = interval
        super.init()
    }

    func run() throws {
        if PIDFile.isRunning() {
            print("\(Color.yellow)Pulse is already running.\(Color.reset)")
            print("Use 'activity-tracker stop' first, or check the menu bar icon.")
            return
        }

        PermissionChecker.checkAll()

        store = try ActivityStore()

        PIDFile.write()

        signalHandler = SignalHandler {
            self.stopTracking()
            PIDFile.remove()
        }
        signalHandler?.setup()

        let app = NSApplication.shared
        app.delegate = self
        app.setActivationPolicy(.accessory) // No dock icon
        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Initialize project matching & API server
        projectMatcher = ProjectMatcher(store: store)
        apiServer = LocalAPIServer(store: store, projectMatcher: projectMatcher!)
        apiServer?.start()

        startTracking()
        startDisplayTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsWindowController.dismiss()
        apiServer?.stop()
        stopTracking()
        PIDFile.remove()
    }

    // MARK: - Tracking Control

    private func startTracking() {
        guard !isTracking else { return }
        merger = HeartbeatMerger(store: store, projectMatcher: projectMatcher)
        let mon = WindowMonitor(
            interval: pollingInterval,
            merger: merger!,
            store: store,
            idleThreshold: 600
        )
        mon.onStateChanged = { [weak self] in
            DispatchQueue.main.async { self?.updateDisplay() }
        }
        mon.onDayChanged = { [weak self] previousDate in
            DispatchQueue.main.async {
                self?.handleDayChanged(previousDate: previousDate)
            }
        }
        mon.start()
        monitor = mon
        isTracking = true
        updateDisplay()
    }

    private func stopTracking() {
        monitor?.stop()
        monitor = nil
        merger = nil
        isTracking = false
        updateDisplay()
        generateAndOpenReport()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateDisplay()
    }

    private func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    private func updateDisplay() {
        guard let button = statusItem.button else { return }

        if isAnalyzing {
            button.title = " Analyzing…"
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Analyzing")
        } else if !isTracking {
            button.title = ""
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Activity Tracker")
        } else if let monitor, monitor.isPaused {
            let timeStr = formatShortDuration(monitor.activeSeconds)
            button.title = " \(timeStr)"
            button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
        } else {
            let timeStr = formatShortDuration(monitor?.activeSeconds ?? 0)
            button.title = " \(timeStr)"
            button.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Tracking")
        }
        button.imagePosition = .imageLeading

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Status header
        if !isTracking {
            let todayTotal = (try? store.queryTodayTotalSeconds()) ?? 0
            let item = NSMenuItem(title: "Stopped – \(formatShortDuration(todayTotal)) today", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let monitor, monitor.isPaused {
            let timeStr = formatShortDuration(monitor.activeSeconds)
            let item = NSMenuItem(title: "Paused – \(timeStr) today", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let timeStr = formatShortDuration(monitor?.activeSeconds ?? 0)
            let item = NSMenuItem(title: "Tracking – \(timeStr) today", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Start / Stop
        if isTracking {
            menu.addItem(NSMenuItem(title: "Stop Tracking", action: #selector(handleStopTracking), keyEquivalent: "s"))
        } else {
            menu.addItem(NSMenuItem(title: "Start Tracking", action: #selector(handleStartTracking), keyEquivalent: "s"))
        }

        // Pause / Resume (only when tracking)
        if isTracking {
            if monitor?.isPaused == true {
                menu.addItem(NSMenuItem(title: "Resume", action: #selector(togglePause), keyEquivalent: "r"))
            } else {
                menu.addItem(NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p"))
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Recent apps (last hour, >= 1 min)
        let headerItem = NSMenuItem(title: "Recent (1 hour)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if let recentApps = try? store.queryRecentApps() {
            if recentApps.isEmpty {
                let item = NSMenuItem(title: "  No recent activity", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            } else {
                let maxSeconds = recentApps.map(\.seconds).max() ?? 1
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                for entry in recentApps {
                    let bar = miniBar(fraction: Double(entry.seconds) / Double(maxSeconds))
                    let dur = formatShortDuration(entry.seconds)
                    let item = NSMenuItem(
                        title: "  \(entry.app)  \(bar)  \(dur)",
                        action: nil,
                        keyEquivalent: ""
                    )
                    item.isEnabled = false
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Open Dashboard (single entry point — SPA report)
        let dashboardItem = NSMenuItem(title: "📊 Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        // Project management submenu
        let projectsItem = NSMenuItem(title: "📁 Projects", action: nil, keyEquivalent: "")
        let projectsMenu = NSMenu()

        let addBrandItem = NSMenuItem(title: "Add Brand…", action: #selector(addBrand), keyEquivalent: "")
        addBrandItem.target = self
        projectsMenu.addItem(addBrandItem)

        let addProjectItem = NSMenuItem(title: "Add Project…", action: #selector(addProject), keyEquivalent: "")
        addProjectItem.target = self
        projectsMenu.addItem(addProjectItem)

        let addRuleItem = NSMenuItem(title: "Add Rule…", action: #selector(addRule), keyEquivalent: "")
        addRuleItem.target = self
        projectsMenu.addItem(addRuleItem)

        let suggestItem = NSMenuItem(title: "Suggest Rules from Data…", action: #selector(suggestRules), keyEquivalent: "")
        suggestItem.target = self
        projectsMenu.addItem(suggestItem)

        projectsMenu.addItem(NSMenuItem.separator())

        let reclassifyItem = NSMenuItem(title: "Reclassify All", action: #selector(reclassifyAll), keyEquivalent: "")
        reclassifyItem.target = self
        projectsMenu.addItem(reclassifyItem)

        // List existing brands & projects
        if let brandList = try? store.allBrands(), !brandList.isEmpty {
            projectsMenu.addItem(NSMenuItem.separator())
            let allProjs = (try? store.allProjects()) ?? []
            let allRules = (try? store.loadAllProjectRules()) ?? []

            for brand in brandList {
                let brandItem = NSMenuItem(title: brand.name, action: nil, keyEquivalent: "")
                brandItem.isEnabled = false
                projectsMenu.addItem(brandItem)

                let brandProjects = allProjs.filter { $0.project.brandId == brand.id }
                for proj in brandProjects {
                    let ruleCount = allRules.filter { $0.projectId == proj.project.id }.count
                    let projItem = NSMenuItem(title: "  · \(proj.project.name) (\(ruleCount) rules)", action: nil, keyEquivalent: "")
                    projItem.isEnabled = false
                    projectsMenu.addItem(projItem)
                }
            }
        }

        projectsItem.submenu = projectsMenu
        menu.addItem(projectsItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let hasApiKey = ConfigManager.claudeApiKey != nil && !ConfigManager.claudeApiKey!.isEmpty
        let keyLabel = hasApiKey ? "Claude API Key ✓" : "Set Claude API Key…"
        menu.addItem(NSMenuItem(title: keyLabel, action: #selector(promptApiKey), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit Pulse", action: #selector(quit), keyEquivalent: "q"))

        // Set targets
        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func handleStartTracking() {
        startTracking()
    }

    @objc private func handleStopTracking() {
        stopTracking()
    }

    @objc private func togglePause() {
        monitor?.togglePause()
        updateDisplay()
    }

    @objc private func openHTMLReport() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        generateAndOpenReport(for: formatter.string(from: Date()))
    }

    @objc private func openPastReport(_ sender: NSMenuItem) {
        guard let dateStr = sender.representedObject as? String else { return }
        generateAndOpenReport(for: dateStr)
    }

    private func generateAndOpenReport(for dateStr: String? = nil, openFile: Bool = true) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let targetDate = dateStr ?? formatter.string(from: Date())

        // Run retroactive project assignment before generating report
        projectMatcher?.autoAssignUnclassified(date: targetDate)

        guard let summary = try? store.queryDay(date: targetDate),
              summary.totalSeconds > 0 else { return }

        let timeline = (try? store.queryTimeline(date: targetDate)) ?? []

        // Always generate JSON for the day
        HTMLReportGenerator.generateJSON(summary: summary, timeline: timeline)

        // Use SPA report (single report.html that fetches data from API)
        let port = apiServer?.port ?? 18492
        let fileURL = HTMLReportGenerator.generateSPA(apiPort: port)

        if openFile {
            // Open in browser so API calls work (file:// won't allow fetch to localhost)
            NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)/report?date=\(targetDate)")
                ?? fileURL)
        }
    }

    @objc private func analyzePastDate(_ sender: NSMenuItem) {
        guard let dateStr = sender.representedObject as? String else { return }
        analyzeDate(dateStr)
    }

    @objc private func analyzeToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        analyzeDate(today)
    }

    func analyzeDate(_ dateStr: String) {
        guard !isAnalyzing else { return }

        guard let summary = try? store.queryDay(date: dateStr),
              summary.totalSeconds > 60 else {
            NSSound.beep()
            return
        }

        let timeline = (try? store.queryTimeline(date: dateStr)) ?? []
        guard !timeline.isEmpty else {
            NSSound.beep()
            return
        }

        isAnalyzing = true
        updateDisplay()

        ClaudeAnalyzer.analyze(
            timeline: timeline,
            totalSeconds: summary.totalSeconds,
            wallClockSeconds: summary.wallClockSeconds,
            date: dateStr
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isAnalyzing = false
                self?.updateDisplay()

                switch result {
                case .success:
                    // Regenerate HTML with analysis embedded, then open
                    self?.projectMatcher?.autoAssignUnclassified(date: dateStr)
                    let brandSummaries = (try? self?.store.queryDayByProject(date: dateStr)) ?? []
                    let unassigned = (try? self?.store.queryUnassignedActivities(date: dateStr)) ?? []
                    let allBrands = (try? self?.store.allBrands()) ?? []
                    let allProjects = (try? self?.store.allProjects()) ?? []
                    let projectData = ProjectData(
                        brands: allBrands.map { BrandJSON(id: $0.id, name: $0.name, color: $0.color) },
                        projects: allProjects.map { ProjectJSON(id: $0.project.id, brandId: $0.project.brandId, brandName: $0.brandName, name: $0.project.name, color: $0.project.color) },
                        unassigned: unassigned,
                        apiPort: self?.apiServer?.port ?? 18492
                    )
                    let reportURL = HTMLReportGenerator.generate(
                        summary: summary,
                        timeline: timeline,
                        brandSummaries: brandSummaries,
                        projectData: projectData
                    )
                    HTMLReportGenerator.generateJSON(summary: summary, timeline: timeline)
                    NSWorkspace.shared.open(reportURL)
                case .failure(let error):
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Analysis Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func handleDayChanged(previousDate: String) {
        // Auto-generate report for the previous day
        generateAndOpenReport(for: previousDate, openFile: false)
        updateDisplay()
    }

    @objc private func openDashboard() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        projectMatcher?.autoAssignUnclassified(date: today)
        let port = apiServer?.port ?? 18492
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)/report?date=\(today)")!)
    }

    @objc private func reclassifyAll() {
        let count = projectMatcher?.autoAssignUnclassified() ?? 0
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reclassification Complete"
        alert.informativeText = "\(count) activities were assigned to projects."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func addBrand() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add Brand"
        alert.informativeText = "Enter a name and pick a color for the new brand."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        nameField.placeholderString = "Brand name"
        stack.addArrangedSubview(nameField)
        nameField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24), pullsDown: false)
        for opt in colorOptions {
            colorPopup.addItem(withTitle: "\(opt.name)")
        }
        stack.addArrangedSubview(colorPopup)
        colorPopup.widthAnchor.constraint(equalToConstant: 300).isActive = true

        alert.accessoryView = stack
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let hex = colorOptions[colorPopup.indexOfSelectedItem].hex

        do {
            _ = try store.insertBrand(name: name, color: hex)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Error"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func addProject() {
        NSApp.activate(ignoringOtherApps: true)

        guard let brandList = try? store.allBrands(), !brandList.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Brands"
            alert.informativeText = "Add a brand first."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Add Project"
        alert.informativeText = "Select a brand, enter a project name, and pick a color."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 88))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let brandPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24), pullsDown: false)
        for brand in brandList {
            brandPopup.addItem(withTitle: brand.name)
        }
        stack.addArrangedSubview(brandPopup)
        brandPopup.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        nameField.placeholderString = "Project name"
        stack.addArrangedSubview(nameField)
        nameField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24), pullsDown: false)
        for opt in colorOptions {
            colorPopup.addItem(withTitle: "\(opt.name)")
        }
        stack.addArrangedSubview(colorPopup)
        colorPopup.widthAnchor.constraint(equalToConstant: 300).isActive = true

        alert.accessoryView = stack
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let selectedBrand = brandList[brandPopup.indexOfSelectedItem]
        let hex = colorOptions[colorPopup.indexOfSelectedItem].hex

        do {
            _ = try store.insertProject(brandId: selectedBrand.id, name: name, color: hex)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Error"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func addRule() {
        NSApp.activate(ignoringOtherApps: true)

        guard let projList = try? store.allProjects(), !projList.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Projects"
            alert.informativeText = "Add a project first."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Add Rule"
        alert.informativeText = "Select a project, rule type, and enter a pattern to match."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let projPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24), pullsDown: false)
        for proj in projList {
            projPopup.addItem(withTitle: "\(proj.brandName) > \(proj.project.name)")
        }
        stack.addArrangedSubview(projPopup)
        projPopup.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let ruleTypes: [(label: String, type: RuleType)] = [
            ("Terminal Folder", .terminalFolder),
            ("URL Domain", .urlDomain),
            ("URL Path", .urlPath),
            ("Page Title", .pageTitle),
            ("Figma File", .figmaFile),
            ("Bundle ID", .bundleId),
            ("Window Title", .windowTitle)
        ]
        let typePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24), pullsDown: false)
        for rt in ruleTypes {
            typePopup.addItem(withTitle: rt.label)
        }
        stack.addArrangedSubview(typePopup)
        typePopup.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let patternField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        patternField.placeholderString = "Pattern (e.g. saasbridge.io)"
        stack.addArrangedSubview(patternField)
        patternField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let regexCheck = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
        stack.addArrangedSubview(regexCheck)

        alert.accessoryView = stack
        alert.window.initialFirstResponder = patternField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let pattern = patternField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }

        let selectedProj = projList[projPopup.indexOfSelectedItem]
        let selectedType = ruleTypes[typePopup.indexOfSelectedItem].type
        let isRegex = regexCheck.state == .on

        do {
            _ = try store.insertRule(projectId: selectedProj.project.id, ruleType: selectedType, pattern: pattern, isRegex: isRegex)
            projectMatcher?.reloadRules()
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Error"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func suggestRules() {
        NSApp.activate(ignoringOtherApps: true)

        let detector = PatternDetector(store: store)
        let detectedBrands = detector.detect()

        guard !detectedBrands.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Patterns Detected"
            alert.informativeText = "Could not detect clear patterns from unassigned activities. Make sure there are enough unassigned activities with recognizable window titles, URLs, or folder names."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        // Use helper to manage interactive state within modal alert
        let helper = SuggestRulesHelper(store: store, detectedBrands: detectedBrands)
        let result = helper.run()
        guard result.confirmed else { return }

        // Process selections
        var brandsCreated = 0
        var projectsCreated = 0
        var rulesCreated = 0

        var brandIdMap: [String: Int64] = [:]
        for existing in helper.currentBrands {
            brandIdMap[existing.name] = existing.id
        }

        for row in helper.brandRows {
            guard row.checkbox.state == .on else { continue }

            if row.isStandalone {
                let proj = row.brand.projects[0]
                let brandId: Int64

                if let popup = row.brandPopup {
                    let selectedTitle = popup.titleOfSelectedItem ?? ""

                    if selectedTitle.hasPrefix("New brand: ") {
                        let brandName = String(selectedTitle.dropFirst(11))
                        if let existingId = brandIdMap[brandName] {
                            brandId = existingId
                        } else {
                            do {
                                let newId = try store.insertBrand(name: brandName)
                                brandIdMap[brandName] = newId
                                brandsCreated += 1
                                brandId = newId
                            } catch { continue }
                        }
                    } else if selectedTitle.hasPrefix("New: ") {
                        let newBrandName = String(selectedTitle.dropFirst(5))
                        if let existingId = brandIdMap[newBrandName] {
                            brandId = existingId
                        } else {
                            do {
                                let newId = try store.insertBrand(name: newBrandName)
                                brandIdMap[newBrandName] = newId
                                brandsCreated += 1
                                brandId = newId
                            } catch { continue }
                        }
                    } else {
                        // Existing brand selected by name
                        if let existingId = brandIdMap[selectedTitle] {
                            brandId = existingId
                        } else { continue }
                    }
                } else { continue }

                do {
                    let projId = try store.insertProject(brandId: brandId, name: proj.suggestedName)
                    projectsCreated += 1
                    for rule in proj.suggestedRules {
                        do {
                            _ = try store.insertRule(projectId: projId, ruleType: rule.ruleType, pattern: rule.pattern, isRegex: rule.isRegex)
                            rulesCreated += 1
                        } catch {}
                    }
                } catch {}

            } else {
                let brandName = row.brand.suggestedName
                let brandId: Int64
                if let existingId = brandIdMap[brandName] {
                    brandId = existingId
                } else {
                    do {
                        let newId = try store.insertBrand(name: brandName)
                        brandIdMap[brandName] = newId
                        brandsCreated += 1
                        brandId = newId
                    } catch { continue }
                }

                for projRow in row.projectRows {
                    guard projRow.checkbox.state == .on else { continue }
                    let proj = projRow.project
                    do {
                        let projId = try store.insertProject(brandId: brandId, name: proj.suggestedName)
                        projectsCreated += 1
                        for rule in proj.suggestedRules {
                            do {
                                _ = try store.insertRule(projectId: projId, ruleType: rule.ruleType, pattern: rule.pattern, isRegex: rule.isRegex)
                                rulesCreated += 1
                            } catch {}
                        }
                    } catch {}
                }
            }
        }

        if rulesCreated > 0 {
            projectMatcher?.reloadRules()
        }
        let reclassified = projectMatcher?.autoAssignUnclassified() ?? 0

        let doneAlert = NSAlert()
        doneAlert.messageText = "Patterns Applied"
        doneAlert.informativeText = "\(brandsCreated) brands, \(projectsCreated) projects, \(rulesCreated) rules created.\n\(reclassified) activities reclassified."
        doneAlert.alertStyle = .informational
        doneAlert.runModal()
    }

    @objc private func openSettings() {
        SettingsWindowController.show(apiPort: apiServer?.port ?? 18492)
    }

    @objc private func promptApiKey() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Claude API Key"
        alert.informativeText = "Enter your Anthropic API key for AI-powered analysis.\nGet one at console.anthropic.com"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        input.placeholderString = "sk-ant-..."
        if let existing = ConfigManager.claudeApiKey {
            input.stringValue = existing
        }
        alert.accessoryView = input

        // Add a "Remove Key" button if key exists
        if ConfigManager.claudeApiKey != nil && !ConfigManager.claudeApiKey!.isEmpty {
            alert.addButton(withTitle: "Remove Key")
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                ConfigManager.claudeApiKey = key
            }
        } else if response == .alertThirdButtonReturn {
            ConfigManager.claudeApiKey = nil
        }
    }

    @objc private func quit() {
        stopTracking()
        PIDFile.remove()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Formatting

    private func formatShortDuration(_ seconds: Int) -> String {
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

    private func miniBar(fraction: Double) -> String {
        let width = 8
        let filled = Int(fraction * Double(width))
        let empty = width - filled
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: empty)
    }
}

// MARK: - SuggestRulesHelper

final class SuggestRulesHelper {

    struct ProjectRow {
        let project: DetectedProject
        let checkbox: NSButton
    }

    struct BrandRow {
        let brand: DetectedBrand
        let checkbox: NSButton
        let isStandalone: Bool          // single-project brand (needs brand popup)
        var brandPopup: NSPopUpButton?  // only for standalone projects
        var projectRows: [ProjectRow]   // empty for standalone
    }

    private let store: ActivityStore
    private let detectedBrands: [DetectedBrand]

    var brandRows: [BrandRow] = []
    var currentBrands: [Brand] = []

    private var allCheckboxes: [NSButton] = []

    init(store: ActivityStore, detectedBrands: [DetectedBrand]) {
        self.store = store
        self.detectedBrands = detectedBrands
        self.currentBrands = (try? store.allBrands()) ?? []
    }

    struct RunResult {
        let confirmed: Bool
    }

    func run() -> RunResult {
        let alert = NSAlert()
        alert.messageText = "Detected Patterns"
        alert.informativeText = "Select brands/projects to create rules for:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply Selected")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))

        // Toolbar: Select All / Deselect All / + Brand
        let toolbar = NSView(frame: NSRect(x: 0, y: 330, width: 480, height: 28))

        let selectAllBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        selectAllBtn.title = "Select All"
        selectAllBtn.bezelStyle = .rounded
        selectAllBtn.setButtonType(.momentaryPushIn)
        selectAllBtn.target = self
        selectAllBtn.action = #selector(selectAll)
        selectAllBtn.font = NSFont.systemFont(ofSize: 11)
        toolbar.addSubview(selectAllBtn)

        let deselectAllBtn = NSButton(frame: NSRect(x: 86, y: 0, width: 90, height: 24))
        deselectAllBtn.title = "Deselect All"
        deselectAllBtn.bezelStyle = .rounded
        deselectAllBtn.setButtonType(.momentaryPushIn)
        deselectAllBtn.target = self
        deselectAllBtn.action = #selector(deselectAll)
        deselectAllBtn.font = NSFont.systemFont(ofSize: 11)
        toolbar.addSubview(deselectAllBtn)

        let addBrandBtn = NSButton(frame: NSRect(x: 182, y: 0, width: 80, height: 24))
        addBrandBtn.title = "+ Brand"
        addBrandBtn.bezelStyle = .rounded
        addBrandBtn.setButtonType(.momentaryPushIn)
        addBrandBtn.target = self
        addBrandBtn.action = #selector(addBrandInline)
        addBrandBtn.font = NSFont.systemFont(ofSize: 11)
        toolbar.addSubview(addBrandBtn)

        container.addSubview(toolbar)

        // Scroll view for brand/project list
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 326))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let contentView = NSView()
        var y: CGFloat = 0

        brandRows = []
        allCheckboxes = []

        for brand in detectedBrands {
            let isStandalone = brand.projects.count == 1

            if isStandalone {
                let proj = brand.projects[0]
                let rowHeight: CGFloat = 50

                let rowView = NSView(frame: NSRect(x: 0, y: y, width: 460, height: rowHeight))

                // Checkbox
                let cb = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                cb.state = .on
                cb.frame = NSRect(x: 4, y: rowHeight / 2 - 8, width: 18, height: 16)
                rowView.addSubview(cb)
                allCheckboxes.append(cb)

                // Project label
                let label = NSTextField(labelWithString: "\(proj.suggestedName) (\(proj.activityCount) activities)")
                label.frame = NSRect(x: 26, y: rowHeight - 22, width: 260, height: 16)
                label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
                rowView.addSubview(label)

                // Rules info
                let rulesText = proj.suggestedRules.map { "\($0.ruleType.rawValue): \($0.pattern)" }.joined(separator: ", ")
                let rulesLabel = NSTextField(labelWithString: rulesText)
                rulesLabel.frame = NSRect(x: 26, y: 4, width: 260, height: 14)
                rulesLabel.font = NSFont.systemFont(ofSize: 10)
                rulesLabel.textColor = .secondaryLabelColor
                rulesLabel.lineBreakMode = .byTruncatingTail
                rowView.addSubview(rulesLabel)

                // Brand popup
                let popup = NSPopUpButton(frame: NSRect(x: 300, y: rowHeight / 2 - 12, width: 155, height: 24))
                popup.font = NSFont.systemFont(ofSize: 11)
                rebuildBrandPopup(popup, suggestedBrand: brand.suggestedName)
                rowView.addSubview(popup)

                contentView.addSubview(rowView)
                y += rowHeight

                brandRows.append(BrandRow(
                    brand: brand,
                    checkbox: cb,
                    isStandalone: true,
                    brandPopup: popup,
                    projectRows: []
                ))

            } else {
                // Multi-project brand header
                let headerHeight: CGFloat = 24

                let headerView = NSView(frame: NSRect(x: 0, y: y, width: 460, height: headerHeight))
                let cb = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                cb.state = .on
                cb.frame = NSRect(x: 4, y: 4, width: 18, height: 16)
                headerView.addSubview(cb)
                allCheckboxes.append(cb)

                let brandLabel = NSTextField(labelWithString: "🏷 \(brand.suggestedName) (\(brand.totalActivities) activities)")
                brandLabel.frame = NSRect(x: 26, y: 2, width: 400, height: 18)
                brandLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
                headerView.addSubview(brandLabel)

                contentView.addSubview(headerView)
                y += headerHeight

                var projRows: [ProjectRow] = []
                for proj in brand.projects {
                    let projHeight: CGFloat = 40

                    let projView = NSView(frame: NSRect(x: 0, y: y, width: 460, height: projHeight))

                    let pcb = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                    pcb.state = .on
                    pcb.frame = NSRect(x: 30, y: projHeight / 2 - 8, width: 18, height: 16)
                    projView.addSubview(pcb)
                    allCheckboxes.append(pcb)

                    let pLabel = NSTextField(labelWithString: "  \(proj.suggestedName) (\(proj.activityCount) activities)")
                    pLabel.frame = NSRect(x: 50, y: projHeight - 20, width: 380, height: 16)
                    pLabel.font = NSFont.systemFont(ofSize: 11)
                    projView.addSubview(pLabel)

                    let rulesText = proj.suggestedRules.map { "\($0.ruleType.rawValue): \($0.pattern)" }.joined(separator: ", ")
                    let rLabel = NSTextField(labelWithString: rulesText)
                    rLabel.frame = NSRect(x: 50, y: 2, width: 380, height: 14)
                    rLabel.font = NSFont.systemFont(ofSize: 10)
                    rLabel.textColor = .secondaryLabelColor
                    rLabel.lineBreakMode = .byTruncatingTail
                    projView.addSubview(rLabel)

                    contentView.addSubview(projView)
                    y += projHeight

                    projRows.append(ProjectRow(project: proj, checkbox: pcb))
                }

                brandRows.append(BrandRow(
                    brand: brand,
                    checkbox: cb,
                    isStandalone: false,
                    brandPopup: nil,
                    projectRows: projRows
                ))
            }

            // Separator
            let sep = NSBox(frame: NSRect(x: 8, y: y, width: 444, height: 1))
            sep.boxType = .separator
            contentView.addSubview(sep)
            y += 5
        }

        contentView.frame = NSRect(x: 0, y: 0, width: 460, height: max(y, 326))
        scrollView.documentView = contentView

        // Flip content so items appear top-to-bottom
        if y > 326 {
            for sub in contentView.subviews {
                sub.frame.origin.y = y - sub.frame.origin.y - sub.frame.height
            }
        }

        container.addSubview(scrollView)
        alert.accessoryView = container

        let response = alert.runModal()
        return RunResult(confirmed: response == .alertFirstButtonReturn)
    }

    private func rebuildBrandPopup(_ popup: NSPopUpButton, suggestedBrand: String) {
        popup.removeAllItems()

        // Existing brands
        for brand in currentBrands {
            popup.addItem(withTitle: brand.name)
        }

        if !popup.itemTitles.isEmpty {
            popup.menu?.addItem(.separator())
        }

        // Suggested new brand
        popup.addItem(withTitle: "New brand: \(suggestedBrand)")
    }

    @objc func selectAll() {
        for cb in allCheckboxes {
            cb.state = .on
        }
    }

    @objc func deselectAll() {
        for cb in allCheckboxes {
            cb.state = .off
        }
    }

    @objc func addBrandInline() {
        let alert = NSAlert()
        alert.messageText = "New Brand"
        alert.informativeText = "Enter brand name:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "Brand name"
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            let newId = try store.insertBrand(name: name)
            let newBrand = Brand(id: newId, name: name, color: "#6366f1", sortOrder: currentBrands.count)
            currentBrands.append(newBrand)

            // Update all standalone brand popups
            for row in brandRows where row.isStandalone {
                if let popup = row.brandPopup {
                    let selected = popup.indexOfSelectedItem
                    rebuildBrandPopup(popup, suggestedBrand: row.brand.suggestedName)
                    popup.selectItem(at: min(selected, popup.numberOfItems - 1))
                }
            }
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Error"
            errAlert.informativeText = "Could not create brand: \(error.localizedDescription)"
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }
}
