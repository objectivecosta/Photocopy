import SwiftUI
import AppKit

@MainActor
class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    var checkForUpdatesClosure: (() -> Void)?
    
    func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Load the icon PNG image from the bundle
            let iconImage = NSImage(named: "MenuBarIcon_Alt")
                
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
            OverlayWindowManager.shared.toggleOverlay()
        }
    }
    
    @objc private func showPreferences() {
        // Always create a fresh settings window
        createSettingsWindow()
    }
    
    private func createSettingsWindow() {
        let settingsView = SettingsView()
            .environmentObject(SettingsManager.shared)
            .frame(minWidth: 500, minHeight: 400)
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Photocopy Preferences"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.minSize = NSSize(width: 500, height: 400)
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

 
