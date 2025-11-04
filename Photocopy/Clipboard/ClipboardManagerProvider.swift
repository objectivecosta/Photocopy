//
//  ClipboardManagerProvider.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-11-04.
//


protocol ClipboardManagerProvider: AnyObject {
    func provide() -> ClipboardManager
}

final class ClipboardManagerProviderImpl: ClipboardManagerProvider {
    var clipboardManager: ClipboardManager!
    
    func provide() -> ClipboardManager {
        clipboardManager
    }
}