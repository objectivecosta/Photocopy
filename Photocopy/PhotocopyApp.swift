//
//  PhotocopyApp.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import SwiftUI
import SwiftData

@main
struct PhotocopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private var appController: AppController = AppController()
    
    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "PhotocopyApp")

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ClipboardItem.self,
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        //try? FileManager.default.removeItem(at: modelConfiguration.url)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            print("📋 Starting fresh with new database...")
            
            
            // Delete the old database and start fresh
            do {
                try FileManager.default.removeItem(at: modelConfiguration.url)
                print("📋 Old database destroyed successfully")
            } catch {
                print("⚠️ Failed to destroy old database: \(error)")
            }
            
            // Try to create a fresh container
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create fresh ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        // Hidden main window that just initializes the app
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    setupApp()
                    // Hide the main window immediately
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
    }
    
    private func setupApp() {
        // Configure clipboard manager with model context
        let modelContext = sharedModelContainer.mainContext
        modelContext.autosaveEnabled = true
        appController.clipboardManager.configure(with: modelContext)
        
        // Set up hotkey handler
        appController.hotkeyManager.onHotkeyPressed = {
            appController.overlayManager.toggleOverlay()
        }
        
        // Set up menu bar
        appController.menuBarManager.checkForUpdatesClosure = {
            appDelegate.checkForUpdates()
        }
        appController.menuBarManager.setupMenuBar()
        
        // Start services
        appController.clipboardManager.startMonitoring()
        appController.hotkeyManager.registerGlobalHotkey()

        // Verify auto-launch setting is consistent with login items
        // This ensures the setting stays in sync if the user manually removed the app from login items
        if appController.settingsManager.autoLaunchOnStartup {
            if !appController.settingsManager.isRegisteredForAutoLaunch() {
                appController.settingsManager.setAutoLaunch(enabled: true)
            }
        }

        logger.info("🚀 Photocopy app initialized")
        logger.info("📋 Clipboard monitoring: \(appController.clipboardManager.isMonitoring)")
        logger.info("⌨️ Hotkey registered: \(appController.hotkeyManager.isHotkeyRegistered)")
        logger.info("📱 Menu bar set up")
    }
}
