# Photocopy - Copy/Paste Manager

## Project Overview
A macOS copy/paste manager that displays a horizontal scrollview of recently copied items at the bottom of the screen when triggered with Command+Shift+V.

## Current State
- ✅ **Alpha Release Complete** - Fully functional clipboard manager
- ✅ SwiftUI macOS app with SwiftData integration for clipboard history
- ✅ Global hotkey support (⌘⇧V) with accessibility permissions
- ✅ Horizontal overlay window with smooth animations
- ✅ Menu bar integration with quick access
- ✅ Search functionality for clipboard history
- ✅ Comprehensive settings with privacy controls
- ✅ Launch at login capability
- ✅ Multi-content type support (text, images, files, URLs)
- ✅ Modern UI with dark/light mode support

## TODO List

### 🏗️ **1. Core Architecture & Setup** ✅
- [x] **Update app permissions and entitlements**
  - Add accessibility permissions for monitoring pasteboard
  - Add global hotkey registration permissions
  - Configure proper sandboxing settings

- [x] **Create proper data models**
  - Refactor `Item.swift` to `ClipboardItem.swift` with proper properties (content, type, timestamp, preview)
  - Add support for different content types (text, images, files, URLs)
  - Implement content deduplication logic

- [x] **Set up app architecture**
  - Create `ClipboardManager` singleton to monitor pasteboard
  - Create `HotkeyManager` for global keyboard shortcuts
  - Create `OverlayWindowManager` for bottom-screen display

### 🎯 **2. Clipboard Monitoring System** ✅
- [x] **Implement pasteboard monitoring**
  - Create background timer to check pasteboard changes
  - Detect when new content is copied
  - Handle different pasteboard content types (NSString, NSImage, NSFilenamesPboard, etc.)

- [x] **Content processing and storage**
  - Extract and process clipboard content
  - Generate thumbnails for images
  - Create previews for different content types
  - Store items in SwiftData with metadata

- [x] **Performance optimization**
  - Implement content size limits
  - Add automatic cleanup of old items
  - Optimize memory usage for large clipboard items

### ⌨️ **3. Global Hotkey System** ✅
- [x] **Hotkey registration**
  - [x] Register Command+Shift+V global hotkey
  - [x] Handle hotkey conflicts gracefully
  - [ ] Allow customizable hotkey combinations in preferences (future enhancement)

- [x] **Event handling**
  - [x] Trigger overlay window on hotkey press
  - [x] Hide overlay when user clicks elsewhere or presses Escape
  - [x] Handle app focus and window management

### 🖼️ **4. Overlay Window & UI** ✅
- [x] **Create overlay window**
  - [x] Design borderless, always-on-top window
  - [x] Position at bottom of screen with proper margins
  - [x] Handle multiple monitor setups

- [x] **Horizontal scroll view**
  - [x] Create horizontal collection view for clipboard items
  - [x] Implement smooth scrolling and item selection
  - [x] Add visual indicators for different content types

- [x] **Item preview components**
  - [x] Text preview with proper formatting
  - [x] Image thumbnails with proper aspect ratios
  - [x] File icons and metadata display
  - [x] URL previews with proper formatting

- [x] **Interaction design**
  - [x] Click to paste selected item
  - [x] Keyboard navigation (arrow keys, Enter, Escape)
  - [x] Delete items with keyboard shortcut (Delete key)
  - [x] Visual feedback for selection and hover states

### 🎨 **5. UI/UX Polish** ✅
- [x] **Visual design**
  - [x] Modern, clean interface with proper spacing
  - [x] Dark/light mode support (automatic via SwiftUI)
  - [x] Smooth animations and transitions
  - [ ] Proper accessibility labels and VoiceOver support (future enhancement)

- [x] **Content type indicators**
  - [x] Icons for different content types
  - [x] Color coding or badges
  - [x] Content preview quality indicators

- [x] **Empty states and error handling**
  - [x] "No clipboard history" state
  - [x] Error handling for failed operations
  - [x] Proper loading states

### ⚙️ **6. Preferences & Settings** ✅
- [x] **Settings window**
  - [ ] Hotkey customization (future enhancement)
  - [x] Number of items to keep in history
  - [x] Content type filtering options
  - [x] Auto-launch on system startup

- [x] **Privacy controls**
  - [x] Option to exclude certain apps from monitoring
  - [x] Sensitive content filtering (passwords, credit cards)
  - [x] Manual clear history option

### 🔧 **7. System Integration** ✅
- [x] **Menu bar app**
  - [x] Create menu bar icon and menu
  - [x] Quick access to preferences and history
  - [x] Status indicators and recent items preview

- [x] **App lifecycle management**
  - [x] Proper app hiding (no dock icon during normal use)
  - [x] Background operation management
  - [x] Graceful shutdown and resource cleanup

### 🚀 **8. Advanced Features** (Partially Complete)
- [x] **Search functionality**
  - [x] Search through clipboard history
  - [x] Filter by content type
  - [x] Recent/frequent items prioritization

- [ ] **Smart features** (Future Enhancements)
  - [ ] Detect and group similar content
  - [ ] Format conversion (e.g., Markdown to HTML)
  - [ ] Text transformation utilities

- [x] **Data persistence**
  - [x] Secure storage of clipboard history
  - [ ] Export/import clipboard history (future enhancement)
  - [ ] Cloud sync considerations (future enhancement)

### 🧪 **9. Testing & Quality**
- [ ] **Unit tests**
  - Test clipboard monitoring logic
  - Test data models and persistence
  - Test hotkey registration and handling

- [ ] **Integration tests**
  - Test complete copy-paste workflows
  - Test overlay window behavior
  - Test with different content types

- [ ] **Performance testing**
  - Memory usage with large clipboard history
  - CPU usage during monitoring
  - App responsiveness during heavy operations

### 📦 **10. Deployment & Distribution** (In Progress)
- [ ] **Code signing and notarization**
  - [ ] Configure proper developer certificates
  - [ ] Notarize app for distribution outside App Store
  - [ ] Test installation on clean systems

- [x] **Documentation**
  - [x] User guide and setup instructions (README)
  - [ ] Privacy policy and data handling explanation (future)
  - [ ] Troubleshooting guide (future)

- [x] **Distribution preparation**
  - [x] App icon design and integration
  - [ ] Version management and update mechanism
  - [ ] Installer or distribution package creation (future)

## Technical Stack
- **Platform**: macOS (SwiftUI)
- **Data**: SwiftData for persistence
- **Language**: Swift
- **Architecture**: MVVM with Managers for system integration

## Key Challenges
1. **System Permissions**: Accessibility and global hotkey registration
2. **Performance**: Efficient clipboard monitoring without impacting system performance
3. **UI/UX**: Seamless overlay window that doesn't interfere with user workflow
4. **Security**: Handling sensitive clipboard content appropriately

## Next Steps
1. Start with core architecture setup (data models and managers)
2. Implement basic clipboard monitoring
3. Create overlay window and basic UI
4. Add global hotkey support
5. Polish UI and add advanced features 