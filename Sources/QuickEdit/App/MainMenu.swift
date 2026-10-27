import AppKit

/// The menu bar, built in code. Items send nil-targeted actions, so they validate through the responder chain:
/// text commands reach the focused editor, document commands its NSDocument, app commands the AppDelegate.
enum MainMenu {
    /// Keeps Open Recent's delegate alive.
    private static let recentMenuDelegate = RecentDocumentsMenuDelegate()

    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(goMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    // MARK: Menus

    private static func appMenu() -> NSMenu {
        let name = AppVariant.displayName
        let menu = NSMenu(title: name)
        menu.addItem(item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(item("Make \(name) the Default Editor…", #selector(AppDelegate.showFileTypes(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services, title: "Services"))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("New Tab", #selector(NSResponder.newWindowForTab(_:)), "t"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        menu.addItem(item("Open Folder…", #selector(DocumentController.openFolderPanel(_:)), "o", [.command, .shift]))
        menu.addItem(item("Quick Open…", #selector(AppDelegate.quickOpen(_:)), "p"))
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = recentMenuDelegate
        menu.addItem(submenu(recent, title: "Open Recent"))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save…", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        let saveAs = item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift, .option])
        saveAs.isAlternate = true
        menu.addItem(saveAs)
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(item("Browse All Versions…", #selector(NSDocument.browseVersions(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        menu.addItem(item("Print…", #selector(NSDocument.printDocument(_:)), "p", [.command, .option]))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        find.addItem(finderItem("Find…", .showFindInterface, "f"))
        find.addItem(finderItem("Find and Replace…", .showReplaceInterface, "f", [.command, .option]))
        find.addItem(finderItem("Find Next", .nextMatch, "g"))
        find.addItem(finderItem("Find Previous", .previousMatch, "g", [.command, .shift]))
        find.addItem(finderItem("Use Selection for Find", .setSearchString, "e"))
        find.addItem(item("Jump to Selection", #selector(NSText.centerSelectionInVisibleArea(_:)), "j"))
        menu.addItem(submenu(find, title: "Find"))

        let lines = NSMenu(title: "Lines")
        lines.addItem(item("Indent", #selector(EditorTextView.indentSelectedLines(_:)), "]"))
        lines.addItem(item("Outdent", #selector(EditorTextView.outdentSelectedLines(_:)), "["))
        lines.addItem(.separator())
        lines.addItem(item("Move Line Up", #selector(EditorTextView.moveLineUp(_:)), arrow(NSUpArrowFunctionKey), [.command, .control]))
        lines.addItem(item("Move Line Down", #selector(EditorTextView.moveLineDown(_:)), arrow(NSDownArrowFunctionKey), [.command, .control]))
        lines.addItem(item("Duplicate Line", #selector(EditorTextView.duplicateLine(_:)), "d", [.command, .shift]))
        lines.addItem(item("Delete Line", #selector(EditorTextView.deleteLine(_:)), "k", [.control, .shift]))
        lines.addItem(item("Join Lines", #selector(EditorTextView.joinLines(_:)), "j", [.control]))
        lines.addItem(item("Sort Lines", #selector(EditorTextView.sortLines(_:))))
        menu.addItem(submenu(lines, title: "Lines"))
        menu.addItem(item("Toggle Comment", #selector(EditorTextView.toggleComment(_:)), "/"))
        menu.addItem(item("Record Voice Note", #selector(EditorViewController.recordVoiceNote(_:)), "r", [.command, .control]))

        let transformations = NSMenu(title: "Transformations")
        transformations.addItem(item("Make Upper Case", #selector(NSResponder.uppercaseWord(_:))))
        transformations.addItem(item("Make Lower Case", #selector(NSResponder.lowercaseWord(_:))))
        transformations.addItem(item("Capitalize", #selector(NSResponder.capitalizeWord(_:))))
        menu.addItem(submenu(transformations, title: "Transformations"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]))
        menu.addItem(item("Show Status Bar", #selector(AppDelegate.toggleStatusBar(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Line Numbers", #selector(AppDelegate.toggleLineNumbers(_:))))
        menu.addItem(item("Show Invisible Characters", #selector(AppDelegate.toggleInvisibles(_:)), "i", [.command, .option]))
        menu.addItem(item("Wrap Lines", #selector(AppDelegate.toggleWrapLines(_:)), "w", [.command, .option]))
        menu.addItem(item("Highlight Current Line", #selector(AppDelegate.toggleCurrentLineHighlight(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Editor", #selector(EditorViewController.showEditorOnly(_:)), "1"))
        menu.addItem(item("Split Preview", #selector(EditorViewController.showSplit(_:)), "2"))
        menu.addItem(item("Preview", #selector(EditorViewController.showPreviewOnly(_:)), "3"))
        menu.addItem(item("Table", #selector(EditorViewController.toggleTable(_:)), "t", [.command, .option]))
        menu.addItem(.separator())
        let folding = NSMenu(title: "Folding")
        folding.addItem(item("Fold", #selector(EditorViewController.fold(_:)), arrow(NSLeftArrowFunctionKey), [.command, .option]))
        folding.addItem(item("Unfold", #selector(EditorViewController.unfold(_:)), arrow(NSRightArrowFunctionKey), [.command, .option]))
        folding.addItem(item("Fold All", #selector(EditorViewController.foldAll(_:)), arrow(NSLeftArrowFunctionKey), [.command, .option, .shift]))
        folding.addItem(item("Unfold All", #selector(EditorViewController.unfoldAll(_:)), arrow(NSRightArrowFunctionKey), [.command, .option, .shift]))
        menu.addItem(submenu(folding, title: "Folding"))
        menu.addItem(.separator())
        let appearance = NSMenu(title: "Appearance")
        for mode in AppearanceMode.allCases {
            let entry = item(mode.title, #selector(AppDelegate.setAppearanceMode(_:)))
            entry.representedObject = mode.rawValue
            appearance.addItem(entry)
        }
        menu.addItem(submenu(appearance, title: "Appearance"))
        menu.addItem(.separator())
        menu.addItem(item("Bigger", #selector(AppDelegate.makeTextBigger(_:)), "+"))
        menu.addItem(item("Smaller", #selector(AppDelegate.makeTextSmaller(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(AppDelegate.makeTextActualSize(_:)), "0"))
        menu.addItem(.separator())
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "Go")
        menu.addItem(item("Go to Line…", #selector(EditorViewController.showGoToLine(_:)), "l"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    // MARK: Helpers

    static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        return item
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }

    private static func finderItem(_ title: String, _ action: NSTextFinder.Action, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = item(title, #selector(NSResponder.performTextFinderAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func submenu(_ menu: NSMenu, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Fills File › Open Recent from NSDocumentController each time it opens.
private final class RecentDocumentsMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let entry = NSMenuItem(title: FileManager.default.displayName(atPath: url.path), action: #selector(openRecent(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = url
            entry.image = NSWorkspace.shared.icon(forFile: url.path)
            entry.image?.size = NSSize(width: 16, height: 16)
            entry.toolTip = url.path
            menu.addItem(entry)
        }
        if menu.items.isEmpty == false { menu.addItem(.separator()) }
        menu.addItem(MainMenu.item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error, Dialogs.shouldPresent(error) { NSApp.presentError(error) }
        }
    }
}
