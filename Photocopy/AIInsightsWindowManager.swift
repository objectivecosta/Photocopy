//
//  AIInsightsWindowManager.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-10-25.
//

import Foundation
import SwiftUI
import AppKit
import os.log

@MainActor
class AIInsightsWindowManager: NSObject, ObservableObject {
    static let shared = AIInsightsWindowManager()

    @Published var isVisible = false

    private var insightsWindow: NSWindow?
    private var insightsHostingView: NSHostingView<AIInsightsPopup>?

    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "AIInsightsWindowManager")

    // Configuration
    private let insightsWidth: CGFloat = 300
    private let arrowHeight: CGFloat = 10
    private let windowMargin: CGFloat = 20

    var onWindowHidden: (() -> Void)?

    // MARK: - Window Management

    func showInsights(classifications: [(String, Float)], sourceRect: NSRect) {
        guard !isVisible else { return }

        createInsightsWindow(classifications: classifications, sourceRect: sourceRect)
        setupWindowPosition(sourceRect: sourceRect)
        animateIn()

        isVisible = true
        logger.info("✨ AI insights window shown")
    }

    func hideInsights() {
        guard isVisible else { return }

        animateOut { [weak self] in
            self?.destroyInsightsWindow()
            self?.isVisible = false
            self?.onWindowHidden?()
            self?.logger.info("✨ AI insights window hidden")
        }
    }

    // MARK: - Window Creation

    private func createInsightsWindow(classifications: [(String, Float)], sourceRect: NSRect) {
        let insightsView = AIInsightsPopup(
            classifications: classifications,
            isVisible: true,
            onClose: { [weak self] in
                self?.hideInsights()
            }
        )

        insightsHostingView = NSHostingView(rootView: insightsView)

        // Calculate window frame (will be positioned later)
        let windowFrame = NSRect(x: 0, y: 0, width: insightsWidth, height: 400) // Height will be adjusted by the view

        insightsWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        guard let window = insightsWindow,
              let hostingView = insightsHostingView else { return }

        // Configure window properties
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        // Make window appear above other windows
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        // Set up click-outside detection
        setupClickOutsideDetection()
    }

    private func destroyInsightsWindow() {
        removeClickOutsideDetection()
        insightsWindow?.orderOut(nil)
        insightsWindow?.delegate = nil
        insightsWindow = nil
        insightsHostingView = nil
    }

    // MARK: - Positioning

    private func setupWindowPosition(sourceRect: NSRect) {
        guard let window = insightsWindow else { return }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame

        // Calculate the position above the source rect
        // Try to position the popup above the source, but if there's not enough space, position below

        // Get the actual height of the content view
        let contentHeight = window.contentView?.frame.height ?? 300
        let totalHeight = contentHeight + arrowHeight

        // Try positioning above first
        var windowFrame = NSRect(
            x: sourceRect.midX - (insightsWidth / 2),
            y: sourceRect.maxY + arrowHeight,
            width: insightsWidth,
            height: contentHeight
        )

        // Check if it fits above
        if windowFrame.maxY > screenFrame.maxY - windowMargin {
            // Position below instead
            windowFrame.origin.y = sourceRect.minY - totalHeight
        }

        // Ensure it doesn't go off screen horizontally
        if windowFrame.minX < screenFrame.minX + windowMargin {
            windowFrame.origin.x = screenFrame.minX + windowMargin
        } else if windowFrame.maxX > screenFrame.maxX - windowMargin {
            windowFrame.origin.x = screenFrame.maxX - windowMargin - insightsWidth
        }

        // Ensure it doesn't go off screen vertically
        if windowFrame.minY < screenFrame.minY + windowMargin {
            windowFrame.origin.y = screenFrame.minY + windowMargin
        } else if windowFrame.maxY > screenFrame.maxY - windowMargin {
            windowFrame.origin.y = screenFrame.maxY - windowMargin - contentHeight
        }

        window.setFrame(windowFrame, display: false)
    }

    // MARK: - Animations

    private func animateIn() {
        guard let window = insightsWindow else { return }

        window.alphaValue = 0.0

        // Animate to full opacity
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    private func animateOut(completion: @escaping () -> Void) {
        guard let window = insightsWindow else {
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
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
        guard let window = insightsWindow else { return }

        let globalClickLocation = NSEvent.mouseLocation
        let windowFrame = window.frame

        if !windowFrame.contains(globalClickLocation) {
            logger.info("🖱️ Click outside AI insights detected")
            hideInsights()
        }
    }

    // MARK: - Keyboard Handling

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }

        switch event.keyCode {
        case 53: // Escape key
            hideInsights()
            return true
        default:
            return false
        }
    }
}