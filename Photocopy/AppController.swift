//
//  AppController.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-11-04.
//

import SwiftUI


@MainActor
final class AppController {
    lazy var imageClassifier: any ImageClassifier & ObservableObject = {
        if #available(macOS 15.0, *) {
            ImageClassifierImpl(settingsManager: settingsManager)
        } else {
            NoOpImageClassifier()
        }
    }()
    
    lazy var clipboardManager = {
        ClipboardManager(
            overlayWindowManager: overlayManager,
            settingsManager: settingsManager
        )
    }()
    
    lazy var hotkeyManager = {
        HotkeyManager(settingsManager: settingsManager)
    }()
    
    lazy var menuBarManager = {
        MenuBarManager(overlayWindowManager: overlayManager, settingsManager: settingsManager)
    }()
    
    lazy var overlayManager = {
        OverlayWindowManager(imageClassifier: imageClassifier, settingsManager: settingsManager, clipboardManagerProvider: clipboardManagerProvider)
    }()
    
    lazy var settingsManager = {
        SettingsManager()
    }()
    
    lazy var clipboardManagerProvider: ClipboardManagerProviderImpl = {
        ClipboardManagerProviderImpl()
    }()

    init() {
        self.clipboardManagerProvider.clipboardManager = clipboardManager
    }
}
