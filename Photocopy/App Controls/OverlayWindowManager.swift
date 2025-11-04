//
//  OverlayWindowManager.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation
import SwiftUI
import AppKit
import os.log

@MainActor
class OverlayWindowManager: NSObject, ObservableObject {
    @Published var isVisible = false
    
    private var overlayWindow: NSWindow?
    private var overlayHostingView: NSHostingView<AnyView>?
    private var previouslyActiveApp: NSRunningApplication?
    
    private let clipboardManagerProvider: ClipboardManagerProvider
    
    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "OverlayWindowManager")
    
    // Configuration
    private let windowHeight: CGFloat = 300
    private let windowMargin: CGFloat = 20
    private let animationDuration: TimeInterval = 0.1
    
    var onWindowHidden: (() -> Void)?
    
    init(clipboardManagerProvider: ClipboardManagerProvider) {
        self.clipboardManagerProvider = clipboardManagerProvider
    }
    
    // MARK: - Window Management
    
    func showOverlay() {
        guard !isVisible else { return }
        
        // Capture the currently active app before showing overlay
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        logger.info("🖼️ Captured previously active app: \(self.previouslyActiveApp?.localizedName ?? "Unknown")")
        
        createOverlayWindow()
        setupWindowPosition()
        animateIn()
        
        isVisible = true
        logger.info("🖼️ Overlay window shown")
    }
    
    func hideOverlay() {
        guard isVisible else { return }
        
        animateOut { [weak self] in
            self?.destroyOverlayWindow()
            self?.isVisible = false
            self?.onWindowHidden?()
            self?.logger.info("🖼️ Overlay window hidden")
        }
    }
    
    func toggleOverlay() {
        if isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }
    
    // MARK: - Window Creation
    
    private func createOverlayWindow() {
        let overlayView = OverlayView(onDismiss: { [weak self] in
            // TODO: Simplify this logic into a single method with a 'source' enum parameter
            self?.hideOverlay()
            self?.activatePreviousApp()
        })
        .environmentObject(clipboardManagerProvider.provide())
        
        overlayHostingView = NSHostingView(rootView: AnyView(overlayView))
        
        let screen = getCurrentActiveScreen()
        let screenFrame = screen.visibleFrame
        
        let windowFrame = NSRect(
            x: screenFrame.minX + windowMargin,
            y: screenFrame.minY + windowMargin,
            width: screenFrame.width - (windowMargin * 2),
            height: windowHeight
        )
        
        overlayWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        guard let window = overlayWindow,
              let hostingView = overlayHostingView else { return }
        
        // Configure window properties
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        
        // Set up window delegate for focus handling
        window.delegate = self
        
        // Make window key and order front
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        
        // Ensure the window becomes the key window for keyboard input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            self.logger.info("🖼️ Overlay window made key for keyboard input")
        }
        
        // Set up click-outside detection
        setupClickOutsideDetection()
    }
    
    private func destroyOverlayWindow() {
        removeClickOutsideDetection()
        overlayWindow?.orderOut(nil)
        overlayWindow?.delegate = nil
        overlayWindow = nil
        overlayHostingView = nil
    }
    
    // MARK: - Positioning
    
    private func setupWindowPosition() {
        guard let window = overlayWindow else { return }
        
        let screen = getCurrentActiveScreen()
        let screenFrame = screen.visibleFrame
        
        // Calculate window position relative to the screen's frame
        let windowFrame = NSRect(
            x: screenFrame.minX + windowMargin,
            y: screenFrame.minY + windowMargin,
            width: screenFrame.width - (windowMargin * 2),
            height: windowHeight
        )
        
        window.setFrame(windowFrame, display: false)
    }
    
    // MARK: - Animations
    
    private func animateIn() {
        guard let window = overlayWindow else { return }
        
        // Start with the window off-screen (below)
        let finalFrame = window.frame
        var startFrame = finalFrame
        startFrame.origin.y = -windowHeight
        
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0.0
        
        // Animate to final position
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1.0
        }
    }
    
    private func animateOut(completion: @escaping () -> Void) {
        guard let window = overlayWindow else {
            completion()
            return
        }
        
        var finalFrame = window.frame
        finalFrame.origin.y = -windowHeight
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 0.0
        }, completionHandler: completion)
    }
    
    // MARK: - Click Outside Detection
    
    private var clickOutsideMonitor: Any?
    
    private func setupClickOutsideDetection() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleClickOutside(event)
        }
    }
    
    private func removeClickOutsideDetection() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
    
    private func handleClickOutside(_ event: NSEvent) {
        guard let window = overlayWindow else { return }
        
        // Get the global mouse location (screen coordinates)
        let globalClickLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        
        // Check if click is outside our overlay window
        if !windowFrame.contains(globalClickLocation) {
            logger.info("🖱️ Click outside overlay detected at \(String(describing: globalClickLocation)), window frame: \(String(describing: windowFrame))")
            // TODO: Simplify this logic into a single method with a 'source' enum parameter
            hideOverlay()
            activatePreviousApp()
        } else {
            logger.info("🖱️ Click inside overlay at \(String(describing: globalClickLocation)), window frame: \(String(describing: windowFrame))")
        }
    }
    
    // MARK: - Multi-Monitor Support
    
    private func getCurrentActiveScreen() -> NSScreen {
        // Method 1: Try to get the screen from the frontmost application's window
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            logger.info("🖥️ Frontmost app: \(frontmostApp.localizedName ?? "Unknown")")
            
            // Get all windows from all applications
            let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
            
            if let windows = windowList {
                // Find windows belonging to the frontmost app, prioritizing focused windows
                var candidateWindows: [(CGRect, Int)] = []
                
                for windowInfo in windows {
                    if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                       ownerPID == frontmostApp.processIdentifier,
                       let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                       let x = bounds["X"] as? CGFloat,
                       let y = bounds["Y"] as? CGFloat,
                       let width = bounds["Width"] as? CGFloat,
                       let height = bounds["Height"] as? CGFloat,
                       let layer = windowInfo[kCGWindowLayer as String] as? Int {
                        
                        let windowFrame = CGRect(x: x, y: y, width: width, height: height)
                        
                        // Skip tiny windows (likely not main content windows)
                        if windowFrame.width > 100 && windowFrame.height > 100 {
                            candidateWindows.append((windowFrame, layer))
                        }
                    }
                }
                
                // Sort by layer (lower layer = more in front) and take the frontmost window
                candidateWindows.sort { $0.1 < $1.1 }
                
                if let frontmostWindow = candidateWindows.first {
                    let windowCenter = CGPoint(x: frontmostWindow.0.midX, y: frontmostWindow.0.midY)
                    
                    // Find which screen contains this window's center
                    for screen in NSScreen.screens {
                        if screen.frame.contains(windowCenter) {
                            logger.info("🖥️ Found active screen from frontmost app window: \(screen.localizedName) at \(String(describing: windowCenter))")
                            return screen
                        }
                    }
                }
            }
        }
        
        // Method 2: Fall back to mouse location
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                logger.info("🖥️ Found active screen from mouse location: \(screen.localizedName) at \(String(describing: mouseLocation))")
                return screen
            }
        }
        
        // Final fallback: use main screen
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first!
        logger.info("🖥️ Using fallback screen: \(fallbackScreen.localizedName)")
        return fallbackScreen
    }
    
    func updateForScreenChange() {
        guard isVisible, let window = overlayWindow else { return }
        
        // Re-position window for current screen
        setupWindowPosition()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().setFrame(window.frame, display: true)
        }
    }
    
    // MARK: - Paste to Previous App
    
    func pasteToActiveApp() {
        guard let previousApp = previouslyActiveApp else {
            logger.info("🖼️ No previously active app to paste to")
            return
        }
        
        logger.info("🖼️ Attempting to paste to: \(previousApp.localizedName ?? "Unknown")")
        
        // Hide overlay first
        hideOverlay()
        
        // Activate the previous app
        // TODO: Simplify this logic into a single method with a 'source' enum parameter
        activatePreviousApp()
        
        // Wait for the app to become active, then send paste command
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.sendPasteCommand()
        }
    }
    
    private func sendPasteCommand() {
        logger.info("🖼️ Sending paste command")
        
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        
        cmdVDown?.flags = .maskCommand
        cmdVUp?.flags = .maskCommand
        
        cmdVDown?.post(tap: .cghidEventTap)
        cmdVUp?.post(tap: .cghidEventTap)
        
        logger.info("🖼️ Paste command sent")
    }
    
    private func activatePreviousApp() {
        guard let previousApp = previouslyActiveApp else {
            logger.info("🖼️ No previously active app to activate")
            return
        }
        
        logger.info("🖼️ Activating previously active app: \(previousApp.localizedName ?? "Unknown")")
        
        // Wait a moment for the overlay to finish hiding, then activate the previous app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            previousApp.activate(options: [.activateIgnoringOtherApps])
        }
    }
    
    // MARK: - Keyboard Handling
    
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        
        switch event.keyCode {
        case 53: // Escape key
            // TODO: Simplify this logic into a single method with a 'source' enum parameter
            hideOverlay()
            activatePreviousApp()
            return true
        default:
            return false
        }
    }
}

// MARK: - NSWindowDelegate

extension OverlayWindowManager: NSWindowDelegate {
    func windowDidChangeScreen(_ notification: Notification) {
        updateForScreenChange()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        logger.info("🖼️ Overlay window became key")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        logger.info("🖼️ Overlay window resigned key")
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // TODO: Simplify this logic into a single method with a 'source' enum parameter
        hideOverlay()
        activatePreviousApp()
        return false
    }
} 
