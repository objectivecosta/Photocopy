//
//  ClipboardContentType.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation

enum ClipboardContentType: String, Codable, CaseIterable {
    case text = "text"
    case image = "image"
    case file = "file"
    case url = "url"
    case richText = "richText"
    case unknown = "unknown"
}