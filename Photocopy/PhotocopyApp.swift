//
//  PhotocopyApp.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct PhotocopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private var appController: AppController = AppController()

    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "PhotocopyApp")

    // MARK: - Early boot

    private static let _earlyBoot: Void = {
        ApplicationLogger.bootstrapFileLogging()

        if isatty(STDERR_FILENO) == 0 {
            let path = ApplicationLogger.currentLogFileURL.path
            freopen(path, "a", stderr)
            freopen(path, "a", stdout)
        }

        let bootOSLog = os.Logger(subsystem: "com.photocopy.app", category: "Boot")
        bootOSLog.info("=== Photocopy process launched (pid: \(ProcessInfo.processInfo.processIdentifier)) ===")

        let isLoginItem = ProcessInfo.processInfo.environment["LAUNCHED_BY_SM_APP_SERVICE"] == "1"
            || ProcessInfo.processInfo.environment["XDG_SESSION_TYPE"] == nil
        bootOSLog.info("Launched via SMAppService login item: \(isLoginItem)")
        bootOSLog.info("Arguments: \(ProcessInfo.processInfo.arguments)")
        bootOSLog.info("Environment keys: \(ProcessInfo.processInfo.environment.keys.sorted().joined(separator: ", "))")
    }()

    init() {
        _ = Self._earlyBoot
        Self.sharedAppController = appController
    }

    // MARK: - Shared state for AppDelegate access

    static var sharedAppController: AppController?
    private static var sharedModelContainer: ModelContainer?

    var sharedModelContainer: ModelContainer = {
        let container = PhotocopyApp.createModelContainer()
        PhotocopyApp.sharedModelContainer = container
        return container
    }()

    private static func createModelContainer() -> ModelContainer {
        let schema = Schema([
            ClipboardItem.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            print("📋 Starting fresh with new database...")

            do {
                try FileManager.default.removeItem(at: modelConfiguration.url)
                print("📋 Old database destroyed successfully")
            } catch {
                print("⚠️ Failed to destroy old database: \(error)")
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create fresh ModelContainer: \(error)")
            }
        }
    }

    // MARK: - Centralized setup — called by AppDelegate AND onAppear

    static func runAppSetup() {
        guard let appController = sharedAppController,
              let modelContainer = sharedModelContainer else {
            let fallbackLog = os.Logger(subsystem: "com.photocopy.app", category: "Boot")
            fallbackLog.error("runAppSetup called but sharedAppController/modelContainer is nil")
            return
        }

        guard !appController.isSetup else { return }
        appController.markAsSetup()

        let logger = Logger(subsystem: "com.photocopy.app", category: "PhotocopyApp")

        ApplicationLogger.bootstrapFileLogging()

        logger.info("Setting up app...")
        logger.info("Log file: \(ApplicationLogger.currentLogFileURL.path)")

        let modelContext = modelContainer.mainContext
        modelContext.autosaveEnabled = true
        appController.clipboardManager.configure(with: modelContext)

        appController.hotkeyManager.onHotkeyPressed = {
            appController.overlayManager.toggleOverlay()
        }

        appController.menuBarManager.setupMenuBar()

        appController.clipboardManager.startMonitoring()
        appController.hotkeyManager.registerGlobalHotkey()

        if appController.settingsManager.autoLaunchOnStartup {
            logger.info("Auto-launch is enabled, verifying registration...")
            if !appController.settingsManager.isRegisteredForAutoLaunch() {
                logger.warning("Auto-launch was enabled but app not registered — re-registering")
                appController.settingsManager.setAutoLaunch(enabled: true)
            }
        }

        logger.info("Photocopy app initialized")
        logger.info("Clipboard monitoring: \(appController.clipboardManager.isMonitoring)")
        logger.info("Hotkey registered: \(appController.hotkeyManager.isHotkeyRegistered)")
        logger.info("Menu bar set up")
        logger.info("Log file exists: \(FileManager.default.fileExists(atPath: ApplicationLogger.currentLogFileURL.path))")
        logger.info("Log file size: \(ApplicationLogger.logFileSize) bytes")
    }

    // MARK: - SwiftUI Scene (belt-and-suspenders fallback)

    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    Self.runAppSetup()
                    DispatchQueue.main.async {
                        NSApp.windows.first?.close()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .modelContainer(sharedModelContainer)
        .environmentObject(appController.clipboardManager)
        .environmentObject(appController.hotkeyManager)
        .environmentObject(appController.menuBarManager)
        .environmentObject(appController.overlayManager)
        .environmentObject(appController.settingsManager)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Self.runAppSetup()
            }
        }
    }
}
