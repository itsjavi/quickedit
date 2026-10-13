import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppVariant.isBackground { NSApp.setActivationPolicy(.accessory) }
    }
}
