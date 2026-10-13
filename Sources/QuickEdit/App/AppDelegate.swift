import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var settings: AppSettings { .shared }
    private var settingsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppVariant.isBackground { NSApp.setActivationPolicy(.accessory) }
        NSApp.mainMenu = MainMenu.make()
        settings.applyAppearance()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error, !AppVariant.isBackground { NSApp.presentError(error) }
                }
            } else if url.scheme == AppVariant.urlScheme {
                URLCommandHandler.handle(url)
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !AppVariant.isBackground
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Commands

    /// ⌘T and the tab bar's + button: a new untitled document, which joins the current window as a tab.
    @objc func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }

    @objc func showSettings(_ sender: Any?) {
        let window = settingsWindow ?? SettingsWindow.make()
        settingsWindow = window
        if AppVariant.isBackground {
            window.orderBack(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc func toggleLineNumbers(_ sender: Any?) { settings.showLineNumbers.toggle() }
    @objc func toggleInvisibles(_ sender: Any?) { settings.showInvisibles.toggle() }
    @objc func toggleWrapLines(_ sender: Any?) { settings.wrapLines.toggle() }
    @objc func toggleCurrentLineHighlight(_ sender: Any?) { settings.highlightCurrentLine.toggle() }

    @objc func setAppearanceMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = AppearanceMode(rawValue: raw) { settings.appearance = mode }
    }

    @objc func makeTextBigger(_ sender: Any?) { settings.fontSize = min(settings.fontSize + 1, AppSettings.fontSizes.upperBound) }
    @objc func makeTextSmaller(_ sender: Any?) { settings.fontSize = max(settings.fontSize - 1, AppSettings.fontSizes.lowerBound) }
    @objc func makeTextActualSize(_ sender: Any?) { settings.fontSize = 13 }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleLineNumbers(_:)): menuItem.state = settings.showLineNumbers ? .on : .off
        case #selector(toggleInvisibles(_:)): menuItem.state = settings.showInvisibles ? .on : .off
        case #selector(toggleWrapLines(_:)): menuItem.state = settings.wrapLines ? .on : .off
        case #selector(toggleCurrentLineHighlight(_:)): menuItem.state = settings.highlightCurrentLine ? .on : .off
        case #selector(setAppearanceMode(_:)):
            menuItem.state = (menuItem.representedObject as? String) == settings.appearance.rawValue ? .on : .off
        default: break
        }
        return true
    }
}
