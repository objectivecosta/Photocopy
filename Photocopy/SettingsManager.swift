import Foundation
import SwiftUI
import ServiceManagement

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // MARK: - Published Properties
    @Published var maxHistoryItems: Int = 50
    @Published var enableTextItems: Bool = true
    @Published var enableImageItems: Bool = true
    @Published var enableFileItems: Bool = true
    @Published var enableURLItems: Bool = true
    @Published var autoLaunchOnStartup: Bool = false
    @Published var excludedApps: [String] = []
    @Published var enableSensitiveContentFiltering: Bool = true
    @Published var enableAIInsights: Bool = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadSettings()
        setupNotificationObservers()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        maxHistoryItems = userDefaults.object(forKey: "maxHistoryItems") as? Int ?? 50
        enableTextItems = userDefaults.object(forKey: "enableTextItems") as? Bool ?? true
        enableImageItems = userDefaults.object(forKey: "enableImageItems") as? Bool ?? true
        enableFileItems = userDefaults.object(forKey: "enableFileItems") as? Bool ?? true
        enableURLItems = userDefaults.object(forKey: "enableURLItems") as? Bool ?? true
        autoLaunchOnStartup = userDefaults.object(forKey: "autoLaunchOnStartup") as? Bool ?? false
        enableSensitiveContentFiltering = userDefaults.object(forKey: "enableSensitiveContentFiltering") as? Bool ?? true
        enableAIInsights = userDefaults.object(forKey: "enableAIInsights") as? Bool ?? false
        
        if let excludedAppsData = userDefaults.data(forKey: "excludedApps"),
           let apps = try? JSONDecoder().decode([String].self, from: excludedAppsData) {
            excludedApps = apps
        }
    }
    
    func saveSettings() {
        userDefaults.set(maxHistoryItems, forKey: "maxHistoryItems")
        userDefaults.set(enableTextItems, forKey: "enableTextItems")
        userDefaults.set(enableImageItems, forKey: "enableImageItems")
        userDefaults.set(enableFileItems, forKey: "enableFileItems")
        userDefaults.set(enableURLItems, forKey: "enableURLItems")
        userDefaults.set(autoLaunchOnStartup, forKey: "autoLaunchOnStartup")
        userDefaults.set(enableSensitiveContentFiltering, forKey: "enableSensitiveContentFiltering")
        userDefaults.set(enableAIInsights, forKey: "enableAIInsights")
        
        if let excludedAppsData = try? JSONEncoder().encode(excludedApps) {
            userDefaults.set(excludedAppsData, forKey: "excludedApps")
        }
    }
    
    // MARK: - Content Filtering
    
    func shouldMonitorContentType(_ type: ClipboardContentType) -> Bool {
        switch type {
        case .text:
            return enableTextItems
        case .image:
            return enableImageItems
        case .file:
            return enableFileItems
        case .url:
            return enableURLItems
        case .richText:
            return enableTextItems // Rich text follows text setting
        case .unknown:
            return true // Always allow unknown types for now
        }
    }
    
    func shouldExcludeApp(_ appName: String?) -> Bool {
        guard let appName = appName else { return false }
        return excludedApps.contains { excludedApp in
            appName.localizedCaseInsensitiveContains(excludedApp)
        }
    }
    
    func isSensitiveContent(_ content: String) -> Bool {
        guard enableSensitiveContentFiltering else { return false }
        
        // Check if the current app is a password manager or security app
        if let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName {
            return isPasswordManagerApp(frontmostApp)
        }
        
        return false
    }
    
    private func isPasswordManagerApp(_ appName: String) -> Bool {
        let passwordManagerApps = [
            // Popular password managers
            "1Password 7 - Password Manager",
            "1Password",
            "Bitwarden",
            "LastPass",
            "Dashlane",
            "Keeper Password Manager",
            "RoboForm",
            "Enpass",
            "KeePassXC",
            "KeePass",
            "NordPass",
            "Proton Pass",
            "Sticky Password",
            "LogMeOnce",
            "Zoho Vault",
            "Password Depot",
            "True Key",
            "Mela",
            "Secrets",
            "KeyShade",
            "Elpass",
            "Minimalist",
            
            // System security apps
            "Keychain Access",
            "Security Agent",
            "AuthenticationServicesCore",
            "CoreAuthUI",
            
            // Crypto wallets
            "Exodus",
            "Electrum",
            "Atomic Wallet",
            "Trust Wallet",
            "MetaMask",
            "Coinbase Wallet"
        ]
        
        return passwordManagerApps.contains { passwordApp in
            appName.localizedCaseInsensitiveContains(passwordApp)
        }
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // No notification observers needed here for now
    }
    
    // MARK: - Auto Launch Management
    
    func setAutoLaunch(enabled: Bool) {
        autoLaunchOnStartup = enabled
        saveSettings()
        
        if enabled {
            addToLoginItems()
        } else {
            removeFromLoginItems()
        }
    }
    
    private func addToLoginItems() {
        // Use SMAppService for modern login item management
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                print("✅ Successfully registered app for auto-launch")
            } catch {
                print("❌ Failed to register for auto-launch: \(error)")
                // Fallback to AppleScript
                fallbackAddToLoginItems()
            }
        } else {
            fallbackAddToLoginItems()
        }
    }
    
    private func removeFromLoginItems() {
        // Use SMAppService for modern login item management
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("✅ Successfully unregistered app from auto-launch")
            } catch {
                print("❌ Failed to unregister from auto-launch: \(error)")
                // Fallback to AppleScript
                fallbackRemoveFromLoginItems()
            }
        } else {
            fallbackRemoveFromLoginItems()
        }
    }
    
    private func fallbackAddToLoginItems() {
        let script = """
        tell application "System Events"
            make login item at end with properties {path:"\(Bundle.main.bundlePath)", hidden:false}
        end tell
        """
        
        executeAppleScript(script)
    }
    
    private func fallbackRemoveFromLoginItems() {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Photocopy"
        let script = """
        tell application "System Events"
            delete login item "\(appName)"
        end tell
        """
        
        executeAppleScript(script)
    }
    
    private func executeAppleScript(_ script: String) {
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Additional Notification Names
extension Notification.Name {
    static let clearClipboardHistoryRequested = Notification.Name("clearClipboardHistoryRequested")
    static let settingsChanged = Notification.Name("settingsChanged")
}

// MARK: - ClipboardContentType Extension
extension ClipboardContentType {
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "URL"
        case .richText:
            return "Rich Text"
        case .unknown:
            return "Unknown"
        }
    }
} 
