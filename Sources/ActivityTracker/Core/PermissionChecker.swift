import Cocoa
import ApplicationServices

enum PermissionChecker {
    private static let accessibilityPromptedKey = "accessibilityPrompted"

    static func checkAccessibility() -> Bool {
        let alreadyPrompted = UserDefaults.standard.bool(forKey: accessibilityPromptedKey)
        let shouldPrompt = !alreadyPrompted

        if shouldPrompt {
            // Show system dialog only on first run
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            UserDefaults.standard.set(true, forKey: accessibilityPromptedKey)
            if !trusted {
                printWarning(
                    "Accessibility permission not granted.",
                    instructions: "System Settings > Privacy & Security > Accessibility > Add ActivityTracker"
                )
            }
            return trusted
        } else {
            let trusted = AXIsProcessTrusted()
            if !trusted {
                printWarning(
                    "Accessibility permission not granted.",
                    instructions: "System Settings > Privacy & Security > Accessibility > Add ActivityTracker"
                )
            }
            return trusted
        }
    }

    static func checkScreenRecording() -> Bool {
        // Attempt to get window list - if Screen Recording is not granted,
        // window titles will be empty but the call won't fail
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            printWarning(
                "Screen Recording permission not granted.",
                instructions: "System Settings > Privacy & Security > Screen Recording > Add Terminal (or your terminal app)"
            )
            return false
        }

        // Check if we can actually read window titles
        let hasTitle = windowList.contains { info in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerName != "Window Server",
                  ownerName != "Dock" else { return false }
            return info[kCGWindowName as String] as? String != nil
        }

        if !hasTitle {
            printWarning(
                "Screen Recording permission may not be granted.",
                instructions: "System Settings > Privacy & Security > Screen Recording > Add Terminal (or your terminal app)"
            )
        }
        return hasTitle
    }

    static func checkAll() {
        _ = checkAccessibility()
        _ = checkScreenRecording()
    }

    private static func printWarning(_ message: String, instructions: String) {
        let yellow = "\u{001B}[33m"
        let reset = "\u{001B}[0m"
        print("\(yellow)⚠ \(message)\(reset)")
        print("  → \(instructions)")
    }
}
