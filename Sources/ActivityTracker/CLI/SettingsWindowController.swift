import Cocoa
import WebKit

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static var shared: SettingsWindowController?

    private let window: NSWindow
    private let webView: WKWebView

    static func show(apiPort: Int) {
        if let existing = shared {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController(apiPort: apiPort)
        shared = controller
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(apiPort: Int) {
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "Pulse Settings"
        window.setFrameAutosaveName("ActivityTrackerSettings")
        window.center()
        window.isReleasedWhenClosed = false

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        // Keep default white background for native macOS look

        super.init()

        window.delegate = self
        window.contentView?.addSubview(webView)

        let html = SettingsPageGenerator.generate(apiPort: apiPort)
        let baseURL = URL(string: "http://127.0.0.1:\(apiPort)")
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismiss() {
        shared?.window.close()
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }
}
