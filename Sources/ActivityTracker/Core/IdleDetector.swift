import Cocoa

final class IdleDetector {
    private let idleThreshold: TimeInterval
    private var timer: Timer?
    private var onIdleChanged: ((Bool) -> Void)?
    private(set) var isIdle = false

    init(idleThreshold: TimeInterval = 600) { // 10 minutes default
        self.idleThreshold = idleThreshold
    }

    func start(onIdleChanged: @escaping (Bool) -> Void) {
        self.onIdleChanged = onIdleChanged
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )

        let nowIdle = idleSeconds >= idleThreshold

        if nowIdle != isIdle {
            isIdle = nowIdle
            onIdleChanged?(isIdle)
        }
    }
}
