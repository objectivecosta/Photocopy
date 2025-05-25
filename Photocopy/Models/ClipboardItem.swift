//
//  ClipboardItem.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation
import SwiftData
import AppKit

@Model
final class ClipboardItem {
    var id: UUID
    var timestamp: Date
    var content: ClipboardContent
    var preview: String
    var contentHash: String
    var isStarred: Bool
    var accessCount: Int
    var lastAccessDate: Date?
    var sourceApp: SourceApp

    // Computed property to get disk path from enum
    var diskFilePath: String? {
        return content.diskFilePath
    }

    init(
        content: ClipboardContent,
        preview: String = "",
        contentHash: String = "",
        sourceApp: SourceApp = SourceApp.unknown
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.content = content
        self.preview = preview.isEmpty ? content.shortPreview : preview
        self.contentHash = contentHash.isEmpty ? Self.generateContentHash(for: content) : contentHash
        self.isStarred = false
        self.accessCount = 0
        self.lastAccessDate = nil
        self.sourceApp = sourceApp
    }

    // MARK: - Computed Properties

    var contentType: ClipboardContentType {
        return content.type
    }

    var displayContent: String {
        switch content {
        case .text:
            return content.displayContent
        case .textOnDisk:
            return preview.isEmpty ? content.displayContent : preview
        case .richText:
            return content.displayContent
        case .richTextOnDisk:
            return preview.isEmpty ? content.displayContent : preview
        case .imageInMemory, .imageOnDisk, .file, .url, .unknown:
            return content.displayContent
        }
    }

    // Computed properties that load from disk when needed
    var fullImageData: Data? {
        switch content {
        case .imageInMemory(let data, _):
            return data
        case .imageOnDisk(let path, _):
            return getDiskContent(from: path)
        default:
            return nil
        }
    }

    var fullRichTextData: Data? {
        switch content {
        case .richText(let data):
            return data
        case .richTextOnDisk(let path):
            return getDiskContent(from: path)
        default:
            return nil
        }
    }

    var fullTextContent: String? {
        switch content {
        case .text(let text):
            return text
        case .textOnDisk(let path):
            return getDiskContentAsText(from: path)
        default:
            return nil
        }
    }
    
    // Preview items, shown on the UI for the clipboard history

    var imageData: Data? {
        
        
        
        return content.imageData
    }

    var thumbnailData: Data? {
        return content.thumbnailData
    }

    var textContent: String? {
        return content.textContent
    }

    var fileURL: String? {
        return content.fileURL
    }

    var urlString: String? {
        return content.urlString
    }

    var richTextData: Data? {
        return content.richTextData
    }

    var shortPreview: String {
        return content.shortPreview
    }

    // MARK: - Disk Storage Methods

    func getDiskContent(from path: String) -> Data? {
        // Load from disk
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return data
        } catch {
            print("❌ Failed to load content from disk: \(error)")
            return nil
        }
    }

    func getDiskContentAsText(from path: String) -> String? {
        guard let data = getDiskContent(from: path) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func deleteDiskFile() {
        guard let diskFilePath = diskFilePath else {
            return
        }

        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: diskFilePath)
            print("✅ Deleted disk file: \(diskFilePath)")
        } catch {
            print("❌ Failed to delete disk file: \(error)")
        }
    }

    // MARK: - Helper Methods

    func incrementAccessCount() {
        accessCount += 1
        lastAccessDate = Date()
    }

    func toggleStarred() {
        isStarred.toggle()
    }

    static func generateContentHash(for content: ClipboardContent) -> String {
        switch content {
        case .text(let text):
            return String(text.hashValue)
        case .textOnDisk(let path):
            return String(path.hashValue)
        case .imageInMemory(let data, _):
            return String(data.hashValue)
        case .imageOnDisk(let path, _):
            return String(path.hashValue)
        case .file(let path):
            return String(path.hashValue)
        case .url(let url):
            return String(url.hashValue)
        case .richText(let data):
            return String(data.hashValue)
        case .richTextOnDisk(let path):
            return String(path.hashValue)
        case .unknown:
            return String(UUID().uuidString.hashValue)
        }
    }

    private func generateContentHash() -> String {
        return Self.generateContentHash(for: content)
    }

    // MARK: - Convenience Initializers

    convenience init(text: String, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .text(text),
            sourceApp: sourceApp
        )
    }

    convenience init(imageData: Data, thumbnail: Data? = nil, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .imageInMemory(imageData, thumbnail: thumbnail),
            sourceApp: sourceApp
        )
    }

    convenience init(imageOnDisk path: String, thumbnail: Data? = nil, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .imageOnDisk(path, thumbnail: thumbnail),
            sourceApp: sourceApp
        )
    }

    convenience init(textOnDisk path: String, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .textOnDisk(path),
            sourceApp: sourceApp
        )
    }

    convenience init(richTextOnDisk path: String, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .richTextOnDisk(path),
            sourceApp: sourceApp
        )
    }

    convenience init(file path: String, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .file(path),
            sourceApp: sourceApp
        )
    }

    convenience init(url: String, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .url(url),
            sourceApp: sourceApp
        )
    }

    convenience init(richText: Data, sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .richText(richText),
            sourceApp: sourceApp
        )
    }

    convenience init(sourceApp: SourceApp = SourceApp.unknown) {
        self.init(
            content: .unknown,
            sourceApp: sourceApp
        )
    }

    // MARK: - Storage Strategy Helpers

    private static let imageMemoryThreshold = 5 * 1024 * 1024 // 5MB
    private static let textMemoryThreshold = 1 * 1024 * 1024 // 1MB
    private static let richTextMemoryThreshold = 1 * 1024 * 1024 // 1MB

    static func createImageItem(
        imageData: Data,
        thumbnail: Data? = nil,
        sourceApp: SourceApp = SourceApp.unknown
    ) -> ClipboardItem {
        if imageData.count > imageMemoryThreshold {
            // Large image - store on disk
            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            guard let appSupportPath = documentsPath?.appendingPathComponent("Photocopy") else {
                // Fallback to memory if disk storage fails
                return ClipboardItem(imageData: imageData, thumbnail: thumbnail, sourceApp: sourceApp)
            }

            // Create directory if it doesn't exist
            do {
                try fileManager.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create app support directory: \(error)")
                return ClipboardItem(imageData: imageData, thumbnail: thumbnail, sourceApp: sourceApp)
            }

            // Create unique filename
            let fileName = "\(UUID().uuidString)_image_\(Date().timeIntervalSince1970)"
            let fileURL = appSupportPath.appendingPathComponent(fileName)

            // Write data to disk
            do {
                try imageData.write(to: fileURL)
                print("✅ Stored image on disk: \(fileURL.path)")
                return ClipboardItem(imageOnDisk: fileURL.path, thumbnail: thumbnail, sourceApp: sourceApp)
            } catch {
                print("❌ Failed to write image to disk: \(error)")
                return ClipboardItem(imageData: imageData, thumbnail: thumbnail, sourceApp: sourceApp)
            }
        } else {
            // Small image - keep in memory
            return ClipboardItem(imageData: imageData, thumbnail: thumbnail, sourceApp: sourceApp)
        }
    }

    static func createTextItem(
        text: String,
        sourceApp: SourceApp = SourceApp.unknown
    ) -> ClipboardItem {
        let textSize = text.data(using: .utf8)?.count ?? 0
        if textSize > textMemoryThreshold {
            // Large text - store on disk
            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            guard let appSupportPath = documentsPath?.appendingPathComponent("Photocopy") else {
                return ClipboardItem(text: text, sourceApp: sourceApp)
            }

            do {
                try fileManager.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create app support directory: \(error)")
                return ClipboardItem(text: text, sourceApp: sourceApp)
            }

            let fileName = "\(UUID().uuidString)_text_\(Date().timeIntervalSince1970)"
            let fileURL = appSupportPath.appendingPathComponent(fileName)

            do {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ Stored text on disk: \(fileURL.path)")
                return ClipboardItem(textOnDisk: fileURL.path, sourceApp: sourceApp)
            } catch {
                print("❌ Failed to write text to disk: \(error)")
                return ClipboardItem(text: text, sourceApp: sourceApp)
            }
        } else {
            return ClipboardItem(text: text, sourceApp: sourceApp)
        }
    }

    static func createRichTextItem(
        richText: Data,
        sourceApp: SourceApp = SourceApp.unknown
    ) -> ClipboardItem {
        if richText.count > richTextMemoryThreshold {
            // Large rich text - store on disk
            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            guard let appSupportPath = documentsPath?.appendingPathComponent("Photocopy") else {
                return ClipboardItem(richText: richText, sourceApp: sourceApp)
            }

            do {
                try fileManager.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create app support directory: \(error)")
                return ClipboardItem(richText: richText, sourceApp: sourceApp)
            }

            let fileName = "\(UUID().uuidString)_richText_\(Date().timeIntervalSince1970)"
            let fileURL = appSupportPath.appendingPathComponent(fileName)

            do {
                try richText.write(to: fileURL)
                print("✅ Stored rich text on disk: \(fileURL.path)")
                return ClipboardItem(richTextOnDisk: fileURL.path, sourceApp: sourceApp)
            } catch {
                print("❌ Failed to write rich text to disk: \(error)")
                return ClipboardItem(richText: richText, sourceApp: sourceApp)
            }
        } else {
            return ClipboardItem(richText: richText, sourceApp: sourceApp)
        }
    }
}

// MARK: - Image Cache
class ImageCache {
    static let shared = ImageCache()

    private var cache: [Int: NSImage] = [:]
    private let cacheQueue = DispatchQueue(label: "com.photocopy.imagequeue", attributes: .concurrent)

    private init() {}

    func getImage(for data: Data) -> NSImage? {
        return cacheQueue.sync {
            let key = data.hashValue
            if let cachedIcon = cache[key] {
                return cachedIcon
            }

            let newIcon = NSImage(data: data)
            if let newIcon = newIcon {
                cache[key] = newIcon
            }
            return newIcon
        }
    }

    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}
