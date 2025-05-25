//
//  SourceApp.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation
import AppKit

struct SourceApp: Codable, Equatable {
    let name: String
    let appPath: String

    init(name: String, appPath: String) {
        self.name = name
        self.appPath = appPath
    }

    var icon: NSImage? {
        guard appPath != "/" else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appPath)
    }

    // Static instance for unknown apps
    static let unknown = SourceApp(name: "Unknown App", appPath: "/")
}