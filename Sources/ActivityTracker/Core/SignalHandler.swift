import Foundation

final class SignalHandler {
    private var sources: [DispatchSourceSignal] = []
    private let onShutdown: () -> Void

    init(onShutdown: @escaping () -> Void) {
        self.onShutdown = onShutdown
    }

    func setup() {
        // Ignore default signal handling
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

        sigintSource.setEventHandler { [weak self] in
            self?.handleShutdown()
        }

        sigtermSource.setEventHandler { [weak self] in
            self?.handleShutdown()
        }

        sigintSource.resume()
        sigtermSource.resume()

        sources = [sigintSource, sigtermSource]
    }

    private func handleShutdown() {
        let green = "\u{001B}[32m"
        let reset = "\u{001B}[0m"
        print("\n\(green)Shutting down gracefully...\(reset)")
        onShutdown()
        exit(0)
    }
}
