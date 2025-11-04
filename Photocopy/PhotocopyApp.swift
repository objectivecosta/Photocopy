//
//  PhotocopyApp.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import SwiftUI
import SwiftData
import os.log

@main
struct PhotocopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var clipboardManager = ClipboardManager()
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var overlayManager = OverlayWindowManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var showOnboarding = true
    
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
    }
    
    private func setupApp() {
        // Configure clipboard manager with model context
        let modelContext = sharedModelContainer.mainContext
        modelContext.autosaveEnabled = true
        clipboardManager.configure(with: modelContext)
        
        // Set up hotkey handler
        hotkeyManager.onHotkeyPressed = {
            overlayManager.toggleOverlay()
        }
        
        // Set up menu bar
        menuBarManager.checkForUpdatesClosure = {
            appDelegate.checkForUpdates()
        }
        menuBarManager.setupMenuBar()
        
        // Start services
        clipboardManager.startMonitoring()
        hotkeyManager.registerGlobalHotkey()
        
        // Set up auto-launch if enabled
        if settingsManager.autoLaunchOnStartup {
            settingsManager.setAutoLaunch(enabled: true)
        }
        
        // Generate ML classifications for existing images
        Task {
            await generateMLClassificationsOnLaunch()
        }

        logger.info("🚀 Photocopy app initialized")
        logger.info("📋 Clipboard monitoring: \(clipboardManager.isMonitoring)")
        logger.info("⌨️ Hotkey registered: \(hotkeyManager.isHotkeyRegistered)")
        logger.info("📱 Menu bar set up")
    }
    
    // MARK: - ML Classification Generation

    @MainActor
    private func generateMLClassificationsOnLaunch() async {
        guard #available(macOS 15.0, *) else {
            logger.info("🤖 ML classification requires macOS 15.0+ - skipping")
            return
        }

        // Check if AI insights are enabled in settings
        guard settingsManager.enableAIInsights else {
            logger.info("🤖 AI Insights are disabled in settings - skipping ML classification")
            return
        }

        logger.info("🤖 Starting ML classification generation for existing images...")

        let startTime = Date()

        do {
            // Get all clipboard items and filter for images stored on disk
            let descriptor = FetchDescriptor<ClipboardItem>()
            let allItems = try sharedModelContainer.mainContext.fetch(descriptor)
            let diskImageItems = allItems.filter { item in
                if case .imageOnDisk = item.content { return true }
                return false
            }

            if diskImageItems.isEmpty {
                logger.info("🤖 No disk images found for ML classification")
                return
            }

            logger.info("🤖 Found \(diskImageItems.count) images on disk for ML classification")

            // Batch classify images with progress reporting
            let classifications = try await ImageClassifier.shared.batchClassifyItems(diskImageItems) { processed, total in
                let progress = Double(processed) / Double(total)
                logger.info("🤖 ML classification progress: \(processed)/\(total) (\(String(format: "%.1f", progress * 100))%)")
            }

            let duration = Date().timeIntervalSince(startTime)
            logger.info("🤖 ML classification completed in \(String(format: "%.2f", duration))s")
            logger.info("🤖 Generated \(classifications.count) classifications")

            // Log top classifications for debugging
            for classification in classifications.prefix(5) {
                if let topClassification = classification.observations.max(by: { $0.value < $1.value }) {
                    logger.info("🤖 Item: \(topClassification.key) (\(String(format: "%.2f", topClassification.value)))")
                }
            }

        } catch {
            logger.error("❌ Failed to generate ML classifications: \(error.localizedDescription)")
        }
    }
}
