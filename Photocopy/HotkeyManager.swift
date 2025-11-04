//
//  HotkeyManager.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation
import Carbon
import AppKit
import os.log

@MainActor
class HotkeyManager: ObservableObject {    
    @Published var isHotkeyRegistered = false
    
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotkeyID = EventHotKeyID(signature: FourCharCode("PCPY".fourCharCodeValue), id: 1)
    
    // Default hotkey: Command + Shift + V
    private var modifierFlags: UInt32 = UInt32(cmdKey | shiftKey)
    private var keyCode: UInt32 = 9 // V key
    
    var onHotkeyPressed: (() -> Void)?
    
    private var permissionCheckTimer: Timer?
    
    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "HotkeyManager")
    
    init() {
        // Start a timer to periodically check for accessibility permissions
        startPermissionMonitoring()
    }
    
    // MARK: - Hotkey Registration
    
    func registerGlobalHotkey() {
        guard !isHotkeyRegistered else { return }
        
        // Force the app to appear in accessibility list by making an API call
        forceAccessibilityListAppearance()
        
        // Request accessibility permissions if needed
        if !hasAccessibilityPermissions() {
            requestAccessibilityPermissions()
            return
        }
        
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        ]
        
        // Install event handler
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                // Get the manager instance from userData
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
                return manager.handleHotkeyEvent(nextHandler: nextHandler, event: theEvent)
            },
            1,
            eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        guard status == noErr else {
            logger.error("❌ Failed to install event handler: \(status)")
            return
        }
        
        // Register the hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifierFlags,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKeyRef
        )
        
        if registerStatus == noErr {
            isHotkeyRegistered = true
            logger.info("⌨️ Global hotkey registered: Cmd+Shift+V")
        } else {
            logger.error("❌ Failed to register hotkey: \(registerStatus)")
            // Clean up event handler if hotkey registration failed
            if let eventHandler = eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
        }
    }
    
    func unregisterGlobalHotkey() {
        guard isHotkeyRegistered else { return }
        
        if let eventHotKeyRef = eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            self.eventHotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        
        isHotkeyRegistered = false
        logger.info("⌨️ Global hotkey unregistered")
    }
    
    // MARK: - Event Handling
    
    private func handleHotkeyEvent(nextHandler: EventHandlerCallRef?, event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        if status == noErr && hotKeyID.id == hotkeyID.id {
            // Hotkey was pressed
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyPressed?()
            }
            return noErr
        }
        
        return CallNextEventHandler(nextHandler, event)
    }
    
    // MARK: - Accessibility Permissions
    
    private func forceAccessibilityListAppearance() {
        // Make a simple accessibility API call to force the app to appear in the list
        // Use a safer approach that just checks permissions without complex API calls
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        let _ = AXIsProcessTrustedWithOptions(options)
    }
    
    private func hasAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func requestAccessibilityPermissions() {
        // Request accessibility permissions, this should prompt
        // macOS to open and present the required dialogue open
        // to the correct page for the user to just hit the add 
        // button.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let hasPermission = AXIsProcessTrustedWithOptions(options)
        
        if !hasPermission {
            // Show detailed alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = """
                Photocopy needs accessibility permissions to:
                • Register global hotkeys (⌘⇧V)
                • Monitor clipboard changes
                • Simulate paste commands
                
                Steps to enable:
                1. Click "Open System Preferences" below
                2. Find "Photocopy" in the list (you may need to add it with the + button)
                3. Check the box next to "Photocopy"
                4. Restart the app
                
                If Photocopy doesn't appear in the list, try running the app first, then check again.
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open System Preferences")
                alert.addButton(withTitle: "I'll Do It Later")
                alert.addButton(withTitle: "Help")
                
                let response = alert.runModal()
                switch response {
                case .alertFirstButtonReturn:
                    self.openAccessibilityPreferences()
                case .alertThirdButtonReturn:
                    self.showDetailedHelp()
                default:
                    break
                }
            }
        }
    }
    
    private func openAccessibilityPreferences() {
        // Try the modern System Settings first (macOS 13+)
        if #available(macOS 13.0, *) {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        } else {
            // Fallback for older macOS versions
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
        
        // Also try to make the app appear in the list by requesting permission again
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
            let _ = AXIsProcessTrustedWithOptions(options)
        }
    }
    
    private func showDetailedHelp() {
        let alert = NSAlert()
        alert.messageText = "Detailed Setup Instructions"
        alert.informativeText = """
        If Photocopy doesn't appear in the Accessibility list:
        
        1. Make sure Photocopy is running
        2. Try pressing ⌘⇧V (this triggers the permission request)
        3. Go to System Preferences > Security & Privacy > Privacy > Accessibility
        4. Click the lock icon and enter your password
        5. Click the + button to add Photocopy manually
        6. Navigate to Applications and select Photocopy
        7. Make sure the checkbox next to Photocopy is checked
        8. Restart Photocopy
        
        Alternative method:
        • Drag Photocopy from Applications directly into the Accessibility list
        
        Still having trouble? Try restarting your Mac and repeating the process.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got It")
        alert.runModal()
    }
    
    // MARK: - Permission Monitoring
    
    private func startPermissionMonitoring() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissionStatus()
            }
        }
    }
    
    private func checkPermissionStatus() {
        if !isHotkeyRegistered && hasAccessibilityPermissions() {
            // Permissions were granted, try to register hotkey again
            registerGlobalHotkey()
        }
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
        
        // Clean up hotkey registration without main actor requirement
        if let eventHotKeyRef = eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
    
    // MARK: - Custom Hotkey Configuration
    
    func updateHotkey(keyCode: UInt32, modifierFlags: UInt32) {
        // Unregister current hotkey
        unregisterGlobalHotkey()
        
        // Update configuration
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        
        // Re-register with new configuration
        registerGlobalHotkey()
    }
    
    func getHotkeyDescription() -> String {
        var description = ""
        
        if modifierFlags & UInt32(controlKey) != 0 {
            description += "⌃"
        }
        if modifierFlags & UInt32(optionKey) != 0 {
            description += "⌥"
        }
        if modifierFlags & UInt32(shiftKey) != 0 {
            description += "⇧"
        }
        if modifierFlags & UInt32(cmdKey) != 0 {
            description += "⌘"
        }
        
        // Convert key code to character
        let keyChar = keyCodeToCharacter(keyCode)
        description += keyChar
        
        return description
    }
    
    private func keyCodeToCharacter(_ keyCode: UInt32) -> String {
        // Common key codes
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "\(keyCode)"
        }
    }
}

// MARK: - String Extension for FourCharCode

private extension String {
    var fourCharCodeValue: Int {
        var result: Int = 0
        if let data = self.data(using: .macOSRoman) {
            data.withUnsafeBytes { bytes in
                for i in 0..<min(4, data.count) {
                    result = result << 8 + Int(bytes[i])
                }
            }
        }
        return result
    }
} 
