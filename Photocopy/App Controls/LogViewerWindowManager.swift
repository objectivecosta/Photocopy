import SwiftUI
import AppKit

@MainActor
final class LogViewerWindowManager {
    private var window: NSWindow?

    func showLogViewer() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.close()
        }

        let logViewerView = LogViewerView()
        let hostingController = NSHostingController(rootView: logViewerView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Photocopy Debug Logs"
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.setFrameAutosaveName("LogViewerWindow")
        newWindow.minSize = NSSize(width: 600, height: 300)
        newWindow.isReleasedWhenClosed = false

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}