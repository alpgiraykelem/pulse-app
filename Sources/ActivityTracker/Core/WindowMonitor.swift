import Cocoa

final class WindowMonitor {
    private let interval: TimeInterval
    private let merger: HeartbeatMerger
    private let extractor: AppDetailExtractor
    private let idleDetector: IdleDetector
    private var backgroundMonitor: BackgroundProcessMonitor?
    private var musicMonitor: BackgroundMusicMonitor?
    private var timer: Timer?
    private(set) var isPaused = false
    private(set) var sessionStart: Date = Date()
    private var pauseStart: Date?
    private var totalPausedSeconds: TimeInterval = 0

    var onStateChanged: (() -> Void)?

    var activeSeconds: Int {
        let elapsed = Date().timeIntervalSince(sessionStart)
        let currentPause = isPaused ? Date().timeIntervalSince(pauseStart ?? Date()) : 0
        return max(0, Int(elapsed - totalPausedSeconds - currentPause))
    }

    init(
        interval: TimeInterval,
        merger: HeartbeatMerger,
        store: ActivityStore,
        extractor: AppDetailExtractor = AppDetailExtractor(),
        idleThreshold: TimeInterval = 600
    ) {
        self.interval = interval
        self.merger = merger
        self.extractor = extractor
        self.idleDetector = IdleDetector(idleThreshold: idleThreshold)
        self.backgroundMonitor = BackgroundProcessMonitor(store: store)
        self.musicMonitor = BackgroundMusicMonitor(store: store)
    }

    func start() {
        sessionStart = Date()
        totalPausedSeconds = 0
        isPaused = false

        // Sleep/Wake observers
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        // Screen lock/unlock
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleSleep), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleWake), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        // Idle detection (skip for passive media apps like YouTube, Spotify)
        idleDetector.start { [weak self] isIdle in
            guard let self else { return }
            if isIdle {
                if self.merger.isCurrentPassiveMedia { return }
                self.pause(reason: "idle")
            } else {
                self.resume(reason: "activity detected")
            }
        }

        poll() // Immediate first poll
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        idleDetector.stop()
        backgroundMonitor?.stop()
        musicMonitor?.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        merger.flush()
    }

    func pause(reason: String) {
        guard !isPaused else { return }
        isPaused = true
        pauseStart = Date()
        merger.flush()
        musicMonitor?.flushAll()
        onStateChanged?()
    }

    func resume(reason: String) {
        guard isPaused else { return }
        if let ps = pauseStart {
            totalPausedSeconds += Date().timeIntervalSince(ps)
        }
        isPaused = false
        pauseStart = nil
        onStateChanged?()
    }

    func togglePause() {
        if isPaused {
            resume(reason: "manual")
        } else {
            pause(reason: "manual")
        }
    }

    @objc private func handleSleep() {
        pause(reason: "sleep")
    }

    @objc private func handleWake() {
        resume(reason: "wake")
    }

    private func poll() {
        guard !isPaused else { return }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let appName = app.localizedName,
              let bundleId = app.bundleIdentifier else {
            return
        }

        let cgWindowTitle = getActiveWindowTitle(pid: app.processIdentifier) ?? appName
        let details = extractor.extract(bundleId: bundleId, windowTitle: cgWindowTitle)

        // Use overrides if available (virtual apps like YouTube, GitHub, etc.)
        let finalAppName = details.appNameOverride ?? appName
        let finalBundleId = details.bundleIdOverride ?? bundleId
        let windowTitle = details.windowTitleOverride ?? cgWindowTitle

        let heartbeat = Heartbeat(
            appName: finalAppName,
            bundleId: finalBundleId,
            windowTitle: windowTitle,
            url: details.url,
            extraInfo: details.extraInfo
        )

        merger.process(heartbeat: heartbeat, interval: Int(interval))

        // Check background Terminal processes
        backgroundMonitor?.check(frontmostBundleId: bundleId, interval: Int(interval))

        // Check background music apps (Spotify, Apple Music)
        musicMonitor?.check(frontmostBundleId: bundleId, interval: Int(interval))
    }

    private func getActiveWindowTitle(pid: pid_t) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let title = window[kCGWindowName as String] as? String,
                  !title.isEmpty else {
                continue
            }
            if let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let height = bounds["Height"] as? Double,
               height < 50 {
                continue
            }
            return title
        }
        return nil
    }
}
