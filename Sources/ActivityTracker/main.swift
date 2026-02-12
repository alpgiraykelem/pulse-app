import Foundation

// When launched with no arguments (e.g., double-click .app), start menu bar directly.
// When launched with arguments (e.g., CLI), use ArgumentParser.
let args = CommandLine.arguments.dropFirst() // drop executable path

if args.isEmpty {
    let app = StatusBarApp(interval: 2)
    try app.run()
} else {
    ActivityTrackerCLI.main()
}
