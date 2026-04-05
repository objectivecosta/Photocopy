import Cocoa
import SwiftUI
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {    
    // Updating
    var updaterController: SPUStandardUpdaterController?
    
    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "AppDelegate")
    
    func checkForUpdates() {
        logger.info("🔄 Checking for updates...")

        guard let updaterController = updaterController else {
            logger.error("❌ Updater controller is not initialized")
            return
        }

        updaterController.checkForUpdates(nil)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        logger.info("🚀 App delegate: Application did finish launching")
        // Since we're an LSUIElement app, we don't need to change activation policy
        // The app delegate will handle preventing termination

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when the last window closes - we're a menu bar app
        logger.info("🔄 App delegate: Preventing app termination after last window closed")
        logger.info("🔄 Current windows count: \(NSApp.windows.count)")
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("🛑 App delegate: Application should terminate called")
        return .terminateNow
    }
} 
