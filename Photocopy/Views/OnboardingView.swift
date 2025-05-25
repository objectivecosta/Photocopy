//
//  OnboardingView.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @Binding var showOnboarding: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Welcome to Photocopy!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your intelligent clipboard manager")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "command",
                    title: "Global Hotkey",
                    description: "Press ⌘⇧V anywhere to access your clipboard history"
                )
                
                FeatureRow(
                    icon: "clock.arrow.circlepath",
                    title: "Automatic History",
                    description: "Everything you copy is automatically saved and organized"
                )
                
                FeatureRow(
                    icon: "photo.on.rectangle.angled",
                    title: "Multiple Content Types",
                    description: "Text, images, files, and URLs - all supported"
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Permission Status
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: hotkeyManager.isHotkeyRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hotkeyManager.isHotkeyRegistered ? .green : .orange)
                    
                    Text(hotkeyManager.isHotkeyRegistered ? "Accessibility permissions granted!" : "Accessibility permissions needed")
                        .font(.headline)
                    
                    Spacer()
                }
                
                if !hotkeyManager.isHotkeyRegistered {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To use global hotkeys, Photocopy needs accessibility permissions:")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Click 'Grant Permissions' below")
                            Text("2. Find 'Photocopy' in the accessibility list")
                            Text("3. Check the box next to 'Photocopy'")
                            Text("4. The app will automatically detect the change")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            
            // Action Buttons
            VStack(spacing: 12) {
                if !hotkeyManager.isHotkeyRegistered {
                    Button("Grant Permissions") {
                        hotkeyManager.registerGlobalHotkey()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                    .controlSize(.large)
                }
                
                Button(hotkeyManager.isHotkeyRegistered ? "Get Started" : "Skip for Now") {
                    showOnboarding = false
                }
                .buttonStyle(.bordered)
                .foregroundColor(hotkeyManager.isHotkeyRegistered ? .white : .primary)
                .background(hotkeyManager.isHotkeyRegistered ? Color.accentColor : Color.clear)
                .cornerRadius(8)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(showOnboarding: .constant(true))
        .frame(width: 600, height: 500)
} 