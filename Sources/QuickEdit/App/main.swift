import AppKit

// AppKit lifecycle: menus are built in code so document and text commands validate through the responder chain.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
