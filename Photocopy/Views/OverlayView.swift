//
//  OverlayView.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation
import SwiftUI
import AppKit

struct OverlayView: View {
    let onDismiss: () -> Void
    
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var selectedIndex: Int = 0
    @State private var keyboardMonitor: Any?
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with instructions
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clipboard.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                    
                    Text("Clipboard History")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("Type to search • ← → Navigate • Enter Paste • Esc Close")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, newValue in
                        clipboardManager.searchText = newValue
                        selectedIndex = 0 // Reset selection when searching
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        clipboardManager.clearSearch()
                        selectedIndex = 0
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSearchFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSearchFocused ? 2 : 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            
            // Clipboard items scroll view
            if clipboardManager.filteredItems.isEmpty {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "clipboard")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(spacing: 4) {
                        Text(searchText.isEmpty ? "No clipboard history" : "No matching items")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(searchText.isEmpty ? "Copy something to get started" : "Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 20) {
                            ForEach(Array(clipboardManager.filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemCardWrapper(
                                    item: item,
                                    isSelected: index == selectedIndex,
                                    onTap: {
                                        selectedIndex = index
                                        pasteSelectedItem()
                                    }
                                )
                                .id(index) // Add ID for scrollTo
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        // Auto-scroll to keep selected item visible
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
                
            
            Spacer(minLength: 8)
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .onAppear {
            setupKeyboardHandling()
            // Clear any previous search
            searchText = ""
            clipboardManager.clearSearch()
            selectedIndex = 0
            isSearchFocused = false // Don't auto-focus, let user start typing
        }
        .onDisappear {
            removeKeyboardHandling()
        }
        .focusable()
    }
    
    // MARK: - Keyboard Handling
    
    private func setupKeyboardHandling() {
        // Remove any existing monitor first
        removeKeyboardHandling()
        
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            
            // Check if this is a printable character (letters, numbers, symbols)
            let isPrintableCharacter = event.characters?.first?.isLetter == true || 
                                     event.characters?.first?.isNumber == true ||
                                     event.characters?.first?.isSymbol == true ||
                                     event.characters?.first?.isPunctuation == true ||
                                     event.characters == " "
            
            // If search field is focused, handle input manually
            if isSearchFocused {
                switch event.keyCode {
                case 36: // Return/Enter - paste selected item
                    pasteSelectedItem()
                    return nil
                case 53: // Escape
                    if !searchText.isEmpty {
                        // Clear search if we have text
                        searchText = ""
                        clipboardManager.clearSearch()
                        selectedIndex = 0
                        return nil
                    } else {
                        // Otherwise dismiss overlay
                        onDismiss()
                        return nil
                    }
                case 123, 124: // Left/Right arrow
                    if searchText.isEmpty {
                        // If search is empty, unfocus and handle navigation
                        isSearchFocused = false
                        if event.keyCode == 123 { // Left arrow
                            moveSelection(-1)
                        } else { // Right arrow
                            moveSelection(1)
                        }
                        return nil
                    }
                    return nil
                case 125, 126: // Down/Up arrow - move focus to items
                    isSearchFocused = false
                    return nil
                case 51: // Delete/Backspace
                    if !searchText.isEmpty {
                        searchText = String(searchText.dropLast())
                    }
                    return nil
                default:
                    // Handle printable characters manually
                    if isPrintableCharacter, let characters = event.characters {
                        searchText += characters
                        return nil
                    }
                    // Ignore other keys when search is focused
                    return nil
                }
            } else {
                // Navigation mode - only handle when search is NOT focused
                switch event.keyCode {
                case 36: // Return/Enter - paste selected item
                    pasteSelectedItem()
                    return nil
                case 53: // Escape
                    onDismiss()
                    return nil
                case 123: // Left arrow
                    moveSelection(-1)
                    return nil
                case 124: // Right arrow
                    moveSelection(1)
                    return nil
                case 125, 126: // Down/Up arrow - focus search
                    isSearchFocused = true
                    return nil
                case 51: // Delete/Backspace - delete selected item if search is empty, otherwise focus search
                    if searchText.isEmpty {
                        // Delete the selected item
                        deleteSelectedItem()
                    } else {
                        // Focus search and delete last character
                        isSearchFocused = true
                        searchText = String(searchText.dropLast())
                    }
                    return nil
                default:
                    // For any printable character, focus search and add the character
                    if isPrintableCharacter, let characters = event.characters {
                        isSearchFocused = true
                        searchText += characters
                        return nil
                    }
                    return event
                }
            }
        }
    }
    
    private func removeKeyboardHandling() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }
    
    private func moveSelection(_ direction: Int) {
        let newIndex = selectedIndex + direction
        if newIndex >= 0 && newIndex < clipboardManager.filteredItems.count {
            selectedIndex = newIndex
        }
    }
    
    private func pasteSelectedItem() {
        guard selectedIndex < clipboardManager.filteredItems.count else { return }

        let item = clipboardManager.filteredItems[selectedIndex]
        clipboardManager.pasteItem(item)
        onDismiss()
    }

    private func deleteSelectedItem() {
        guard selectedIndex < clipboardManager.filteredItems.count else { return }

        let itemToDelete = clipboardManager.filteredItems[selectedIndex]

        Task { @MainActor in
            clipboardManager.deleteItem(itemToDelete)

            // Adjust selected index after deletion (run after deletion is processed)
            DispatchQueue.main.async {
                if selectedIndex >= clipboardManager.filteredItems.count && selectedIndex > 0 {
                    selectedIndex = clipboardManager.filteredItems.count - 1
                } else if clipboardManager.filteredItems.isEmpty {
                    selectedIndex = 0
                }
            }
        }
    }
} 
