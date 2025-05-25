//
//  ClipboardContent.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation

enum ClipboardContent: Codable {
    case text(String)
    case textOnDisk(String) // Large text stored on disk
    case imageInMemory(Data, thumbnail: Data?)
    case imageOnDisk(String, thumbnail: Data?) // Large images stored on disk (path, thumbnail)
    case file(String) // Single file path
    case url(String)
    case richText(Data)
    case richTextOnDisk(String) // Large rich text stored on disk
    case unknown

    // MARK: - Computed Properties

    var type: ClipboardContentType {
        switch self {
        case .text, .textOnDisk: return .text
        case .imageInMemory, .imageOnDisk: return .image
        case .file: return .file
        case .url: return .url
        case .richText, .richTextOnDisk: return .richText
        case .unknown: return .unknown
        }
    }

    var displayContent: String {
        switch self {
        case .text(let content):
            return content
        case .textOnDisk:
            return "Large text content (stored on disk)"
        case .imageInMemory, .imageOnDisk:
            return "Image"
        case .file(let path):
            return "File: \(URL(string: path)?.lastPathComponent ?? "Unknown")"
        case .url(let urlString):
            return urlString
        case .richText:
            return "Rich text content"
        case .richTextOnDisk:
            return "Rich text content (stored on disk)"
        case .unknown:
            return "Unknown content"
        }
    }

    var shortPreview: String {
        let maxLength = 100
        let content = displayContent
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        }
        return content
    }

    // MARK: - Data Access

    var textContent: String? {
        switch self {
        case .text(let content):
            return content
        default:
            return nil
        }
    }

    var imageData: Data? {
        switch self {
        case .imageInMemory(let data, _):
            return thumbnailData ?? data
        case .imageOnDisk:
            return thumbnailData // Only thumbnail is in memory
        default:
            return nil
        }
    }

    var thumbnailData: Data? {
        switch self {
        case .imageInMemory(_, let thumbnail), .imageOnDisk(_, let thumbnail):
            return thumbnail
        default:
            return nil
        }
    }

    var fileURL: String? {
        if case .file(let path) = self {
            return path
        }
        return nil
    }

    var urlString: String? {
        if case .url(let url) = self {
            return url
        }
        return nil
    }

    var richTextData: Data? {
        switch self {
        case .richText(let data):
            return data
        default:
            return nil
        }
    }

    // MARK: - Disk Storage Support

    var dataSize: Int {
        switch self {
        case .text(let content):
            return content.data(using: .utf8)?.count ?? 0
        case .textOnDisk:
            return 0 // Data is on disk
        case .imageInMemory(let data, let thumbnail):
            return data.count + (thumbnail?.count ?? 0)
        case .imageOnDisk(_, let thumbnail):
            return thumbnail?.count ?? 0 // Only thumbnail is in memory
        case .file:
            return 0 // Files are referenced by path, not stored
        case .url(let url):
            return url.data(using: .utf8)?.count ?? 0
        case .richText(let data):
            return data.count
        case .richTextOnDisk:
            return 0 // Data is on disk
        case .unknown:
            return 0
        }
    }

    var diskFilePath: String? {
        switch self {
        case .textOnDisk(let path), .imageOnDisk(let path, _), .richTextOnDisk(let path):
            return path
        default:
            return nil
        }
    }

    func toData() -> Data? {
        switch self {
        case .text(let content):
            return content.data(using: .utf8)
        case .textOnDisk, .richTextOnDisk:
            return nil // Data is on disk, need to load it via ClipboardItem
        case .imageInMemory(let data, _):
            return data
        case .imageOnDisk:
            return nil // Data is on disk, need to load it via ClipboardItem
        case .file:
            return nil // Files are referenced by path
        case .url(let url):
            return url.data(using: .utf8)
        case .richText(let data):
            return data
        case .unknown:
            return nil
        }
    }
}
