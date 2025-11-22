import SwiftUI

struct SettingsView: View {
    @AppStorage("maxHistoryItems") private var maxHistoryItems: Int = 50
    @AppStorage("enableTextItems") private var enableTextItems: Bool = true
    @AppStorage("enableImageItems") private var enableImageItems: Bool = true
    @AppStorage("enableFileItems") private var enableFileItems: Bool = true
    @AppStorage("enableURLItems") private var enableURLItems: Bool = true
    @AppStorage("autoLaunchOnStartup") private var autoLaunchOnStartup: Bool = false
    @AppStorage("excludedApps") private var excludedAppsData: Data = Data()
    @AppStorage("enableSensitiveContentFiltering") private var enableSensitiveContentFiltering: Bool = true
    @AppStorage("enableAIInsights") private var enableAIInsights: Bool = false

    @EnvironmentObject var settingsManager: SettingsManager

    @State private var excludedApps: [String] = []
    @State private var newAppName: String = ""
    @State private var showingClearHistoryAlert: Bool = false
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case contentTypes = "Content Types"
        case privacy = "Privacy"
        
        var icon: String {
            switch self {
            case .general:
                return "gear"
            case .contentTypes:
                return "doc.on.clipboard"
            case .privacy:
                return "hand.raised"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack(spacing: 0) {
                Spacer()
                
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Divider
            Divider()
            
            // Content Area
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:
                        generalSettingsView
                    case .contentTypes:
                        contentTypesView
                    case .privacy:
                        privacySettingsView
                    }
                }
                .padding(20)
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 550)
        .onAppear {
            loadExcludedApps()
        }
    }
    
    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // History Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("History")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Retention Strategy:")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Picker("Retention Strategy", selection: $settingsManager.retentionStrategy) {
                            ForEach(RetentionStrategy.allCases) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    
                    if settingsManager.retentionStrategy == .count {
                        HStack {
                            Text("Maximum items to keep:")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Stepper(value: $maxHistoryItems, in: 10...200, step: 10) {
                                Text("\(maxHistoryItems)")
                                    .frame(width: 50, alignment: .trailing)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .frame(width: 120)
                        }
                    } else {
                        HStack {
                            Text("Keep items for:")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Picker("Duration", selection: $settingsManager.historyRetentionDuration) {
                                Text("1 Day").tag(TimeInterval(24 * 60 * 60))
                                Text("3 Days").tag(TimeInterval(3 * 24 * 60 * 60))
                                Text("1 Week").tag(TimeInterval(7 * 24 * 60 * 60))
                                Text("2 Weeks").tag(TimeInterval(14 * 24 * 60 * 60))
                                Text("1 Month").tag(TimeInterval(30 * 24 * 60 * 60))
                            }
                            .frame(width: 180)
                        }
                    }
                    
                    HStack {
                        Button("Clear History") {
                            showingClearHistoryAlert = true
                        }
                        .foregroundColor(.red)
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                }
                .padding(.leading, 32)
            }
            
            // Startup Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "power")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)

                    Text("Startup")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch at system startup", isOn: $autoLaunchOnStartup)
                        .onChange(of: autoLaunchOnStartup) { _, newValue in
                            setAutoLaunch(enabled: newValue)
                        }

                    Text("Automatically start Photocopy when you log in to your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 32)
            }

            // Hotkey Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)

                    Text("Hotkey")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Global hotkey for paste menu:")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Hotkey", selection: $settingsManager.hotkeyModifier) {
                            ForEach(HotkeyModifier.allCases) { modifier in
                                HStack {
                                    Text(modifier.displayName)
                                        .font(.system(.body, design: .monospaced))
                                    Text("(\(modifier.description))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(modifier)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }

                    Text("Choose the keyboard shortcut to open the paste menu. The change will take effect immediately.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 32)
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .alert("Clear Clipboard History", isPresented: $showingClearHistoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearClipboardHistory()
            }
        } message: {
            Text("This will permanently delete all clipboard history. This action cannot be undone.")
        }
    }
    
    private var contentTypesView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Content Types Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Content Types to Monitor")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Text", isOn: $enableTextItems)
                        .help("Monitor copied text content")
                    
                    Toggle("Images", isOn: $enableImageItems)
                        .help("Monitor copied images and screenshots")

                    if enableImageItems {
                        Toggle("Enable AI Insights for Images", isOn: $enableAIInsights)
                            .help("Use machine learning to automatically classify and analyze image content")
                            .padding(.leading, 20)
                    }

                    Toggle("Files", isOn: $enableFileItems)
                        .help("Monitor copied files and folders")
                    
                    Toggle("URLs", isOn: $enableURLItems)
                        .help("Monitor copied web links and URLs")
                }
                .padding(.leading, 32)
            }
            
            // Info Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    Text("Information")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                Text("Disabling content types will prevent them from being saved to clipboard history, but won't affect existing items.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)
            }
            
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var privacySettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Content Filtering Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "shield.checkered")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Content Filtering")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Filter sensitive content", isOn: $enableSensitiveContentFiltering)
                        .help("Automatically exclude content copied from password managers and security apps")
                    
                    Text("Automatically excludes content from password managers (1Password, Bitwarden, etc.), Keychain Access, and other security apps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 32)
            }
            
            // Excluded Applications Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "app.badge.checkmark")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Excluded Applications")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clipboard content from these applications will not be monitored:")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    
                    // List of excluded apps
                    if excludedApps.isEmpty {
                        Text("No excluded applications")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(excludedApps, id: \.self) { appName in
                                HStack {
                                    Image(systemName: "app")
                                        .foregroundColor(.secondary)
                                        .frame(width: 16)
                                    Text(appName)
                                        .font(.system(.callout, design: .monospaced))
                                    Spacer()
                                    Button("Remove") {
                                        removeExcludedApp(appName)
                                    }
                                    .foregroundColor(.red)
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                    
                    // Add new app
                    HStack {
                        TextField("Application name (e.g., 1Password)", text: $newAppName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Add") {
                            addExcludedApp()
                        }
                        .buttonStyle(.bordered)
                        .disabled(newAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.leading, 32)
            }
            
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Helper Methods
    
    private func loadExcludedApps() {
        if let apps = try? JSONDecoder().decode([String].self, from: excludedAppsData) {
            excludedApps = apps
        }
    }
    
    private func saveExcludedApps() {
        if let data = try? JSONEncoder().encode(excludedApps) {
            excludedAppsData = data
        }
    }
    
    private func addExcludedApp() {
        let appName = newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appName.isEmpty && !excludedApps.contains(appName) {
            excludedApps.append(appName)
            saveExcludedApps()
            newAppName = ""
        }
    }
    
    private func removeExcludedApp(_ appName: String) {
        excludedApps.removeAll { $0 == appName }
        saveExcludedApps()
    }
    
    private func deleteExcludedApps(at offsets: IndexSet) {
        excludedApps.remove(atOffsets: offsets)
        saveExcludedApps()
    }
    
    private func clearClipboardHistory() {
        // This will be implemented to clear the SwiftData store
        NotificationCenter.default.post(name: .clearClipboardHistory, object: nil)
    }
    
    private func setAutoLaunch(enabled: Bool) {
        // This will be implemented to set up auto-launch
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "me.rafaelcosta.Photocopy"
        
        if enabled {
            // Add to login items
            let script = """
            tell application "System Events"
                make login item at end with properties {path:"\(Bundle.main.bundlePath)", hidden:false}
            end tell
            """
            
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("Error adding login item: \(error)")
                }
            }
        } else {
            // Remove from login items
            let script = """
            tell application "System Events"
                delete login item "\(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Photocopy")"
            end tell
            """
            
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("Error removing login item: \(error)")
                }
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let clearClipboardHistory = Notification.Name("clearClipboardHistory")
}

#Preview {
    SettingsView()
} 