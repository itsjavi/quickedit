import AppKit

/// Alerts and sheets go through here. The agents' background Test build never shows them: a sheet can make its
/// window key and activate the app, taking focus from the user. It records them for `debug/state` instead.
enum Dialogs {
    /// The last alert or error the background build swallowed.
    static var lastSuppressed: String?

    static var isSuppressed: Bool { AppVariant.isBackground }

    static func show(_ alert: NSAlert, for window: NSWindow?, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        if isSuppressed {
            lastSuppressed = alert.messageText
            return
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion?(alert.runModal())
        }
    }

    /// Returns false when the error was only recorded (background build).
    static func shouldPresent(_ error: Error) -> Bool {
        guard isSuppressed else { return true }
        lastSuppressed = error.localizedDescription
        return false
    }
}
