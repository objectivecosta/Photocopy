import SwiftUI
import AppKit

@MainActor
class MenuBarManager: ObservableObject {
    private let overlayWindowManager: OverlayWindowManager
    private let settingsManager: SettingsManager
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    var checkForUpdatesClosure: (() -> Void)?
    
    init(overlayWindowManager: OverlayWindowManager, settingsManager: SettingsManager) {
        self.overlayWindowManager = overlayWindowManager
        self.settingsManager = settingsManager
    }
    
    func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Load the icon PNG image from the bundle
            let iconImage = NSImage(named: "MenuBarIcon_Alt")
            iconImage?.isTemplate = true
                
            button.image = iconImage
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Preferences
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Check for Updates iten
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Photocopy", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Right click - show menu
            statusItem?.menu?.popUp(positioning: nil, at: NSPoint.zero, in: statusItem?.button)
        } else {
            // Left click - toggle overlay
            
            overlayWindowManager.toggleOverlay()
        }
    }
    
    @objc private func showPreferences() {
        // Close existing settings window if it's open
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.close()
        }
        // Create a fresh settings window
        createSettingsWindow()
    }
    
    private func createSettingsWindow() {
        let settingsView = SettingsView()
            .environmentObject(settingsManager)
            .frame(minWidth: 500, minHeight: 550)
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Photocopy Preferences"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.minSize = NSSize(width: 500, height: 550)
        window.maxSize = NSSize(width: 700, height: 600)
        
        // Configure window appearance
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        
        // Store reference and show
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        // Call the AppDelegate's update checking method
        checkForUpdatesClosure?()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

 
