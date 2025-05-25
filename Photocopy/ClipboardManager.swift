//
//  ClipboardManager.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation
import AppKit
import SwiftData
import UserNotifications
import os.log

@MainActor
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var filteredItems: [ClipboardItem] = []
    @Published var isMonitoring = false
    @Published var searchText = "" {
        didSet {
            filterItems()
        }
    }
    
    private var pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var monitoringTimer: Timer?
    private var modelContext: ModelContext?
    private let settingsManager = SettingsManager.shared
    
    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "ClipboardManager")
    
    // Configuration
    private let monitoringInterval: TimeInterval = 0.5
    private let maxContentSize = 512 * 1024 * 1024 // 512MB per item (absolute limit)
    private let maxImageSize = 256 * 1024 * 1024 // 256MB per image (absolute limit)
    private let cleanupInterval: TimeInterval = 300 // 5 minutes
    private let maxItemAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    // Disk storage thresholds
    private let diskStorageTextThreshold = 1024 * 1024 // 1MB for text
    private let diskStorageImageThreshold = 5 * 1024 * 1024 // 5MB for images
    private let diskStorageRichTextThreshold = 1024 * 1024 // 1MB for rich text
    
    private var cleanupTimer: Timer?
    
    private init() {
        lastChangeCount = pasteboard.changeCount
        setupNotificationObservers()
        requestNotificationPermissions()
    }
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        loadStoredItems()
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .clearClipboardHistoryRequested,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await self.clearAllHistory()
            }
        }
    }
    
    // MARK: - User Notifications
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                self.logger.info("📱 Notification permissions granted")
            } else if let error = error {
                self.logger.error("📱 Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func showRejectionNotification(reason: String, contentType: String, size: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "Clipboard Item Skipped"
        
        if let size = size {
            content.body = "\(contentType) (\(size)) was too large. \(reason)"
        } else {
            content.body = "\(contentType) was skipped. \(reason)"
        }
        
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "clipboard-rejection-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("📱 Failed to show notification: \(error)")
            }
        }
    }
    
    private func clearAllHistory() {
        guard let modelContext = modelContext else { return }
        
        // Clear from SwiftData
        do {
            let descriptor = FetchDescriptor<ClipboardItem>()
            let allItems = try modelContext.fetch(descriptor)
            for item in allItems {
                modelContext.delete(item)
            }
            try modelContext.save()
        } catch {
            logger.error("❌ Error clearing clipboard history: \(error.localizedDescription)")
        }
        
        // Clear from memory
        clipboardItems.removeAll()
        logger.info("🗑️ Clipboard history cleared")
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForClipboardChanges()
            }
        }
        
        // Start cleanup timer
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performAutomaticCleanup()
            }
        }
        
        logger.info("📋 Clipboard monitoring started")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        logger.info("📋 Clipboard monitoring stopped")
    }
    
    // MARK: - Clipboard Processing
    
    private func checkForClipboardChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            processCurrentClipboardContent()
        }
    }
    
    private func processCurrentClipboardContent() {
        guard let modelContext = modelContext else { return }
        
        // Get all available types on the pasteboard
        let availableTypes = pasteboard.types ?? []
        logger.info("📋 Available pasteboard types: \(availableTypes.map { $0.rawValue })")
        
        // Debug: Try to get data for each type to see what's available
        for type in availableTypes {
            if let data = pasteboard.data(forType: type) {
                logger.info("📋 Type '\(type.rawValue)' has data: \(data.count) bytes")
            } else if let propertyList = pasteboard.propertyList(forType: type) {
                logger.info("📋 Type '\(type.rawValue)' has property list: \(String(describing: propertyList))")
            } else if let string = pasteboard.string(forType: type) {
                logger.info("📋 Type '\(type.rawValue)' has string: \(string.prefix(100))")
            } else {
                logger.info("📋 Type '\(type.rawValue)' has no accessible data")
            }
        }
        
        // Process content based on available types (in priority order)
        // Check if we have both file URLs and image data (common when copying image files from Finder)
        let hasFileURLs = availableTypes.contains(.fileURL) || availableTypes.contains(NSPasteboard.PasteboardType("public.file-url"))
        let hasImageData = availableTypes.contains(.tiff) || availableTypes.contains(.png) || availableTypes.contains(.pdf)
        
        if hasFileURLs {
            // Always prioritize file URLs - check if they're image files first
            logger.info("📋 Found file URLs - checking if they're image files")
            
            // Try different methods to get file URLs
            var fileURLs: [String]? = nil
            
            // Method 1: Try .fileURL type
            if let urls = pasteboard.propertyList(forType: .fileURL) as? [String] {
                fileURLs = urls
                logger.info("📋 Got file URLs via .fileURL: \(urls)")
            }
            // Method 2: Try public.file-url type
            else if let urls = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("public.file-url")) as? [String] {
                fileURLs = urls
                logger.info("📋 Got file URLs via public.file-url: \(urls)")
            }
            // Method 3: Try NSFilenamesPboardType (legacy)
            else if let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
                fileURLs = filenames
                print("📋 Got file URLs via NSFilenamesPboardType: \(filenames)")
            }
            
            if let fileURLs = fileURLs {
                print("📋 Found file URLs: \(fileURLs)")
                
                // Check if this is an image file - if so, process as image file instead of generic file
                if fileURLs.count == 1, let urlString = fileURLs.first {
                    print("📋 Processing single file URL: \(urlString)")
                    
                    // Create proper file URL from path
                    let url = URL(fileURLWithPath: urlString)
                    print("📋 Created file URL: \(url)")
                    let pathExtension = url.pathExtension.lowercased()
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
                    
                    print("📋 File extension: '\(pathExtension)', is image: \(imageExtensions.contains(pathExtension))")
                    
                    if imageExtensions.contains(pathExtension) {
                        print("📋 Detected image file from Finder: \(url.lastPathComponent)")
                        processImageFile(at: url, modelContext: modelContext)
                        return
                    }
                }
                // Process as regular file(s)
                print("📋 Processing as regular file(s)")
                processFileContent(fileURLs, modelContext: modelContext)
            } else {
                print("📋 ⚠️ Failed to get file URLs from pasteboard using any method")
            }
        } else if hasImageData {
            // Only image data, no file URLs (copied from web/apps)
            print("📋 Found image data on pasteboard - processing as image")
            processImageFromPasteboard(modelContext: modelContext)
        } else if availableTypes.contains(.string) {
            if let string = pasteboard.string(forType: .string) {
                processTextContent(string, modelContext: modelContext)
            }
        } else if availableTypes.contains(.rtf) {
            if let rtfData = pasteboard.data(forType: .rtf) {
                processRichTextContent(rtfData, modelContext: modelContext)
            }
        } else if availableTypes.contains(.html) {
            if let htmlData = pasteboard.data(forType: .html) {
                processHTMLContent(htmlData, modelContext: modelContext)
            }
        } else {
            // Handle unknown content types
            processUnknownContent(availableTypes, modelContext: modelContext)
        }
    }
    
    private func processTextContent(_ text: String, modelContext: ModelContext) {
        guard !text.isEmpty else { return }

        if text.count > maxContentSize {
            let size = ByteCountFormatter.string(fromByteCount: Int64(text.count), countStyle: .binary)
            let maxSize = ByteCountFormatter.string(fromByteCount: Int64(maxContentSize), countStyle: .binary)
            showRejectionNotification(reason: "Maximum size is \(maxSize).", contentType: "Text", size: size)
            return
        }

        // Check if text content monitoring is enabled
        guard settingsManager.shouldMonitorContentType(.text) else {
            showRejectionNotification(reason: "Text monitoring is disabled in settings.", contentType: "Text")
            return
        }

        // Check for sensitive content
        if settingsManager.isSensitiveContent(text) {
            if let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName {
                showRejectionNotification(reason: "Content from '\(frontmostApp)' is automatically excluded for security.", contentType: "Text")
                print("🔒 Skipping content from password manager/security app: \(frontmostApp)")
            } else {
                showRejectionNotification(reason: "Content from security apps is automatically excluded.", contentType: "Text")
                print("🔒 Skipping sensitive content")
            }
            return
        }

        // Check if current app should be excluded
        if let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName,
           settingsManager.shouldExcludeApp(frontmostApp) {
            showRejectionNotification(reason: "App '\(frontmostApp)' is excluded in settings.", contentType: "Text")
            print("🚫 Skipping content from excluded app: \(frontmostApp)")
            return
        }

        let contentHash = ClipboardItem.generateContentHash(for: .text(text))

        // Check for duplicates
        if let existingItem = clipboardItems.first(where: { $0.contentHash == contentHash }) {
            return
        }

        // Detect content type and create appropriate item
        if isURL(text) || isEmail(text) {
            // Create URL item
            let clipboardItem = ClipboardItem(
                url: text,
                sourceApp: getSourceApp()
            )
            upsertClipboardItem(clipboardItem, modelContext: modelContext)
        } else {
            // Create text item with smart storage strategy
            let clipboardItem = ClipboardItem.createTextItem(
                text: text,
                sourceApp: getSourceApp()
            )
            upsertClipboardItem(clipboardItem, modelContext: modelContext)
        }
    }
    
    private func processImageFromPasteboard(modelContext: ModelContext) {
        // Check if image content monitoring is enabled
        guard settingsManager.shouldMonitorContentType(.image) else {
            showRejectionNotification(reason: "Image monitoring is disabled in settings.", contentType: "Image")
            return
        }

        // Check if current app should be excluded
        if let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName,
           settingsManager.shouldExcludeApp(frontmostApp) {
            showRejectionNotification(reason: "App '\(frontmostApp)' is excluded in settings.", contentType: "Image")
            print("🚫 Skipping image from excluded app: \(frontmostApp)")
            return
        }

        var imageData: Data?
        var imageFormat = "Unknown"

        // Try different image formats in order of preference
        if let tiffData = pasteboard.data(forType: .tiff) {
            imageData = tiffData
            imageFormat = "TIFF"
            print("📋 Found TIFF image data: \(ByteCountFormatter.string(fromByteCount: Int64(tiffData.count), countStyle: .binary))")
        } else if let pngData = pasteboard.data(forType: .png) {
            imageData = pngData
            imageFormat = "PNG"
            print("📋 Found PNG image data: \(ByteCountFormatter.string(fromByteCount: Int64(pngData.count), countStyle: .binary))")
        } else if let pdfData = pasteboard.data(forType: .pdf) {
            imageData = pdfData
            imageFormat = "PDF"
            print("📋 Found PDF image data: \(ByteCountFormatter.string(fromByteCount: Int64(pdfData.count), countStyle: .binary))")
        }

        guard let data = imageData else {
            showRejectionNotification(reason: "No valid image data found.", contentType: "Image")
            return
        }

        if data.count > maxImageSize {
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)
            let maxSize = ByteCountFormatter.string(fromByteCount: Int64(maxImageSize), countStyle: .binary)
            showRejectionNotification(reason: "Maximum size is \(maxSize).", contentType: "Image", size: size)
            print("📋 Image too large (\(size)), skipping")
            return
        }

        // Try to get filename if available (for images copied from Finder)
        var fileName: String? = nil
        if let fileURLs = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           let urlString = fileURLs.first {
            fileName = URL(fileURLWithPath: urlString).lastPathComponent
            print("📋 Found associated filename: \(fileName!)")
        }

        let contentHash = ClipboardItem.generateContentHash(for: .imageInMemory(data, thumbnail: nil))

        // Check for duplicates
        if clipboardItems.first?.contentHash == contentHash {
            print("📋 Duplicate image detected, skipping")
            return
        }

        // Test if we can create an NSImage from the data
        if let testImage = NSImage(data: data) {
            print("📋 Successfully created NSImage with size: \(testImage.size)")
        } else {
            print("📋 ⚠️ Failed to create NSImage from data")
        }

        // Generate thumbnail and get image info
        let (thumbnailData, imageInfo) = generateImageThumbnail(from: data)

        // Create preview with filename if available
        let basePreview = imageInfo.isEmpty ?
        "Image (\(imageFormat), \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)))" :
        "Image (\(imageFormat), \(imageInfo), \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)))"

        let preview = fileName != nil ? "\(fileName!) - \(basePreview)" : basePreview

        print("📋 Using \(thumbnailData != nil ? "thumbnail" : "original") image data: \(ByteCountFormatter.string(fromByteCount: Int64((thumbnailData ?? data).count), countStyle: .binary))")

        // Use smart storage strategy for images
        let clipboardItem = ClipboardItem.createImageItem(
            imageData: data,
            thumbnail: thumbnailData,
            sourceApp: getSourceApp()
        )

        upsertClipboardItem(clipboardItem, modelContext: modelContext)
    }
    
    private func generateImageThumbnail(from imageData: Data) -> (Data?, String) {
        guard let nsImage = NSImage(data: imageData) else {
            print("📋 ⚠️ Failed to create NSImage for thumbnail generation")
            return (nil, "")
        }
        
        let originalSize = nsImage.size
        let maxThumbnailSize: CGFloat = 200
        
        print("📋 Generating thumbnail for image: \(Int(originalSize.width))×\(Int(originalSize.height))")
        
        // Calculate thumbnail size maintaining aspect ratio
        let aspectRatio = originalSize.width / originalSize.height
        var thumbnailSize: NSSize
        
        if originalSize.width > originalSize.height {
            thumbnailSize = NSSize(width: maxThumbnailSize, height: maxThumbnailSize / aspectRatio)
        } else {
            thumbnailSize = NSSize(width: maxThumbnailSize * aspectRatio, height: maxThumbnailSize)
        }
        
        print("📋 Thumbnail size: \(Int(thumbnailSize.width))×\(Int(thumbnailSize.height))")
        
        // Create thumbnail
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: thumbnailSize))
        thumbnail.unlockFocus()
        
        // Convert to data
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let thumbnailData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("📋 ⚠️ Failed to generate thumbnail data")
            return (nil, "\(Int(originalSize.width))×\(Int(originalSize.height))")
        }
        
        print("📋 ✅ Successfully generated thumbnail: \(ByteCountFormatter.string(fromByteCount: Int64(thumbnailData.count), countStyle: .binary))")
        
        let imageInfo = "\(Int(originalSize.width))×\(Int(originalSize.height))"
        return (thumbnailData, imageInfo)
    }
    
    private func processFileContent(_ fileURLs: [String], modelContext: ModelContext) {
        print("📋 🔧 processFileContent called with URLs: \(fileURLs)")
        
        // Check if file content monitoring is enabled
        guard settingsManager.shouldMonitorContentType(.file) else {
            showRejectionNotification(reason: "File monitoring is disabled in settings.", contentType: "File")
            return
        }
        
        // Check if current app should be excluded
        if let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName,
           settingsManager.shouldExcludeApp(frontmostApp) {
            showRejectionNotification(reason: "App '\(frontmostApp)' is excluded in settings.", contentType: "File")
            print("🚫 Skipping files from excluded app: \(frontmostApp)")
            return
        }
        
        let contentHash = ClipboardItem.generateContentHash(for: .file(fileURLs.first!))
        print("📋 Generated content hash: \(contentHash)")
        
        // Check for duplicates
        if clipboardItems.first?.contentHash == contentHash {
            print("📋 Duplicate file detected, skipping")
            return
        }

        // Only handle the first file for now
        let firstFileURL = fileURLs.first!

        if fileURLs.count > 1 {
            print("⚠️ Multiple files detected, only processing the first one: \(firstFileURL)")
        }

        let preview = "File: \(URL(string: firstFileURL)?.lastPathComponent ?? "Unknown")"
        print("📋 Creating file clipboard item with preview: \(preview)")

        let clipboardItem = ClipboardItem(
            file: firstFileURL,
            sourceApp: getSourceApp()
        )
        
        print("📋 Adding file clipboard item to list")
        upsertClipboardItem(clipboardItem, modelContext: modelContext)
    }
    
    private func processImageFile(at url: URL, modelContext: ModelContext) {
        print("📋 🖼️ processImageFile called with URL: \(url)")
        print("📋 URL path: \(url.path)")
        print("📋 URL absoluteString: \(url.absoluteString)")
        print("📋 File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        // Check if file is readable
        let isReadable = FileManager.default.isReadableFile(atPath: url.path)
        print("📋 File is readable: \(isReadable)")
        
        // Try using NSImage directly first (it might handle file access better)
        if let nsImage = NSImage(contentsOf: url) {
            print("📋 ✅ Successfully loaded NSImage directly from URL")
            
            // Convert NSImage back to data for storage
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let imageData = bitmapRep.representation(using: .png, properties: [:]) else {
                print("📋 ⚠️ Failed to convert NSImage to data")
                // Fallback to regular file processing
                processFileContent([url.path], modelContext: modelContext)
                return
            }
            
            print("📋 Successfully converted to image data: \(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .binary))")

            if imageData.count > maxImageSize {
                // Image is too big, process as File URL
                return processFileContent([url.path], modelContext: modelContext)
            }

            // Use file path + modification date for hash to avoid false duplicates
            do {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let modificationDate = fileAttributes[.modificationDate] as? Date ?? Date()
                let hashString = "\(url.path)_\(modificationDate.timeIntervalSince1970)"
                let contentHash = ClipboardItem.generateContentHash(for: .text(hashString))

                // Check for duplicates
                if clipboardItems.first?.contentHash == contentHash {
                    print("📋 Duplicate image file detected, skipping")
                    return
                }

                print("📋 Successfully loaded image file: \(url.lastPathComponent) (\(Int(nsImage.size.width))×\(Int(nsImage.size.height)))")

                // Generate thumbnail and get image info
                let (thumbnailData, imageInfo) = generateImageThumbnail(from: imageData)

                let fileName = url.lastPathComponent
                let fileExtension = url.pathExtension.uppercased()
                let preview = imageInfo.isEmpty ?
                "Image file: \(fileName) (\(fileExtension), \(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .binary)))" :
                "Image file: \(fileName) (\(fileExtension), \(imageInfo), \(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .binary)))"

                print("📋 Using \(thumbnailData != nil ? "thumbnail" : "original") image data: \(ByteCountFormatter.string(fromByteCount: Int64((thumbnailData ?? imageData).count), countStyle: .binary))")

                // Use smart storage strategy for image files
                let clipboardItem = ClipboardItem.createImageItem(
                    imageData: imageData,
                    thumbnail: thumbnailData,
                    sourceApp: getSourceApp()
                )

                upsertClipboardItem(clipboardItem, modelContext: modelContext)
            } catch {
                print("📋 ❌ Failed to get file attributes: \(error)")
                // Use a simpler hash based on file path
                let contentHash = ClipboardItem.generateContentHash(for: .text(url.path))
                
                // Check for duplicates
                if clipboardItems.first?.contentHash == contentHash {
                    print("📋 Duplicate image file detected, skipping")
                    return
                }
                
                // Continue with processing even without file attributes
                let fileName = url.lastPathComponent
                let fileExtension = url.pathExtension.uppercased()
                let preview = "Image file: \(fileName) (\(fileExtension), \(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .binary)))"

                let (thumbnailData, _) = generateImageThumbnail(from: imageData)

                // Use smart storage strategy for image files
                let clipboardItem = ClipboardItem.createImageItem(
                    imageData: imageData,
                    thumbnail: thumbnailData,
                    sourceApp: getSourceApp()
                )

                upsertClipboardItem(clipboardItem, modelContext: modelContext)
            }
            
        } else {
            print("📋 ❌ Failed to load NSImage from URL")
            // Fallback: Process as a regular file instead of an image
            print("📋 Falling back to processing as regular file")
            processFileContent([url.path], modelContext: modelContext)
        }
    }
    
    private func processRichTextContent(_ rtfData: Data, modelContext: ModelContext) {
        if rtfData.count > maxContentSize {
            let size = ByteCountFormatter.string(fromByteCount: Int64(rtfData.count), countStyle: .binary)
            let maxSize = ByteCountFormatter.string(fromByteCount: Int64(maxContentSize), countStyle: .binary)
            showRejectionNotification(reason: "Maximum size is \(maxSize).", contentType: "Rich Text", size: size)
            return
        }

        let contentHash = ClipboardItem.generateContentHash(for: .richText(rtfData))

        // Check for duplicates
        if clipboardItems.first?.contentHash == contentHash { return }

        // Try to extract plain text for preview
        var preview = "Rich text content"
        if let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            preview = String(attributedString.string.prefix(200))
        }

        // Use smart storage strategy for rich text
        let clipboardItem = ClipboardItem.createRichTextItem(
            richText: rtfData,
            sourceApp: getSourceApp()
        )

        upsertClipboardItem(clipboardItem, modelContext: modelContext)
    }
    
    private func processHTMLContent(_ htmlData: Data, modelContext: ModelContext) {
        if htmlData.count > maxContentSize {
            let size = ByteCountFormatter.string(fromByteCount: Int64(htmlData.count), countStyle: .binary)
            let maxSize = ByteCountFormatter.string(fromByteCount: Int64(maxContentSize), countStyle: .binary)
            showRejectionNotification(reason: "Maximum size is \(maxSize).", contentType: "HTML", size: size)
            return
        }

        let contentHash = ClipboardItem.generateContentHash(for: .richText(htmlData))

        // Check for duplicates
        if clipboardItems.first?.contentHash == contentHash { return }

        // Try to extract plain text for preview
        var preview = "HTML content"
        if let htmlString = String(data: htmlData, encoding: .utf8) {
            // Simple HTML tag removal for preview
            let plainText = htmlString.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            preview = String(plainText.prefix(200))
        }

        // Use smart storage strategy for HTML content (treated as rich text)
        let clipboardItem = ClipboardItem.createRichTextItem(
            richText: htmlData,
            sourceApp: getSourceApp()
        )

        upsertClipboardItem(clipboardItem, modelContext: modelContext)
    }
    
    private func processUnknownContent(_ availableTypes: [NSPasteboard.PasteboardType], modelContext: ModelContext) {
        // Try to get some content from the first available type
        guard let firstType = availableTypes.first,
              let data = pasteboard.data(forType: firstType) else {
            showRejectionNotification(reason: "No readable data found.", contentType: "Unknown Content")
            return
        }
        
        if data.count > maxContentSize {
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)
            let maxSize = ByteCountFormatter.string(fromByteCount: Int64(maxContentSize), countStyle: .binary)
            showRejectionNotification(reason: "Maximum size is \(maxSize).", contentType: "Unknown Content", size: size)
            return
        }
        
        let contentHash = ClipboardItem.generateContentHash(for: .imageInMemory(data, thumbnail: nil))
        
        // Check for duplicates
        if clipboardItems.first?.contentHash == contentHash { return }
        
        let typeString = firstType.rawValue
        let preview = "Unknown content type: \(typeString) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)))"
        
        let clipboardItem = ClipboardItem(sourceApp: getSourceApp())
        
        upsertClipboardItem(clipboardItem, modelContext: modelContext)
        print("📋 Processed unknown content type: \(typeString)")
    }
    
    // MARK: - Item Management
    private func upsertClipboardItem(_ item: ClipboardItem, modelContext: ModelContext) {
        print("📋 ➕ upsertClipboardItem called for: \(item.contentType.rawValue) - \(item.shortPreview)")

        if let existingIndex = clipboardItems.firstIndex(where: { $0.contentHash == item.contentHash }) {
            let existingItem = clipboardItems.remove(at: existingIndex)
            existingItem.timestamp = Date()
            clipboardItems.insert(existingItem, at: 0)
            print("📋 Item updated in the clipboardItems array. Total items: \(clipboardItems.count)")
        } else {
            // Insert at the beginning (most recent first)
            clipboardItems.insert(item, at: 0)
            print("📋 Item inserted into clipboardItems array. Total items: \(clipboardItems.count)")
        }
        
        // Limit the number of items based on settings
        let maxItems = settingsManager.maxHistoryItems
        if clipboardItems.count > maxItems {
            let itemsToRemove = clipboardItems.suffix(clipboardItems.count - maxItems)
            for itemToRemove in itemsToRemove {
                modelContext.delete(itemToRemove)
            }
            clipboardItems = Array(clipboardItems.prefix(maxItems))
        }
        
        // Update filtered items
        filterItems()
        
        // Save to persistent storage
        modelContext.insert(item)
        
        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to save clipboard item: \(error)")
        }
        
        print("📋 Added new clipboard item: \(item.shortPreview)")
    }
    
    func deleteItem(_ item: ClipboardItem) {
        guard let modelContext = modelContext else { return }

        if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) {
            clipboardItems.remove(at: index)
            filterItems() // Update filtered items

            // Clean up disk file if item is stored on disk
            if item.diskFilePath != nil {
                item.deleteDiskFile()
            }

            modelContext.delete(item)

            do {
                try modelContext.save()
            } catch {
                print("❌ Failed to delete clipboard item: \(error)")
            }
        }
    }
    
    func clearHistory() {
        guard let modelContext = modelContext else { return }

        // Clean up all disk files before deleting items
        for item in clipboardItems {
            if item.diskFilePath != nil {
                item.deleteDiskFile()
            }
            modelContext.delete(item)
        }

        clipboardItems.removeAll()
        filteredItems.removeAll() // Clear filtered items too

        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to clear clipboard history: \(error)")
        }
    }
    
    // MARK: - Data Loading
    
    private func loadStoredItems() {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            clipboardItems = try modelContext.fetch(descriptor)
            
            // Migration: Handle existing items that don't have sourceApp data
            var needsSave = false
            var migratedCount = 0
            
            for item in clipboardItems {
                // Check if this item needs migration
                // Items created before sourceApp was added will have empty or invalid sourceApp data
                if item.sourceApp.name.isEmpty {
                    item.sourceApp = SourceApp.unknown
                    needsSave = true
                    migratedCount += 1
                }
            }
            
            if needsSave {
                try modelContext.save()
                print("📋 Migration completed: updated \(migratedCount) items with source app information")
            }
            
            filteredItems = clipboardItems // Initialize filtered items
            print("📋 Loaded \(clipboardItems.count) clipboard items from storage")
        } catch {
            print("❌ Failed to load clipboard items: \(error)")
            // If loading fails, start with empty items
            // The database should have been recreated at the container level
            clipboardItems = []
            filteredItems = []
        }
    }
    
    // MARK: - Paste Functionality
    
    func pasteItem(_ item: ClipboardItem) {
        // Clear current pasteboard
        pasteboard.clearContents()
        
        // Write content based on type
        switch item.contentType {
        case .text:
            if let text = item.fullTextContent {
                pasteboard.setString(text, forType: .string)
            }
        case .url:
            if let urlString = item.urlString {
                pasteboard.setString(urlString, forType: .string)
            }
        case .image:
            if let imageData = item.fullImageData {  // Use original image data for pasting
                // Try to set as PNG first for better quality
                if let nsImage = NSImage(data: imageData),
                   let tiffData = nsImage.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    pasteboard.setData(pngData, forType: .png)
                } else {
                    // Fallback to TIFF if PNG conversion fails
                    pasteboard.setData(imageData, forType: .tiff)
                }
            }
        case .file:
            if let fileURL = item.fileURL {
                pasteboard.setPropertyList([fileURL], forType: .fileURL)
            }
        case .richText:
            if let rtfData = item.fullRichTextData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
        case .unknown:
            break
        }
        
        // Use the overlay window manager to paste to the previously active app
        // TODO: Extract paste functionality into a separate PasteManager class and remove singleton dependency - OverlayWindowManager shouldn't handle pasting
        OverlayWindowManager.shared.pasteToActiveApp()
        
        item.incrementAccessCount()
        
        print("📋 Pasted item: \(item.shortPreview)")
    }
    
    // MARK: - Performance Optimization
    
    private func performAutomaticCleanup() {
        guard let modelContext = modelContext else { return }
        
        let currentDate = Date()
        var itemsToRemove: [ClipboardItem] = []
        
        // Remove items older than maxItemAge
        for item in clipboardItems {
            if currentDate.timeIntervalSince(item.timestamp) > maxItemAge {
                itemsToRemove.append(item)
            }
        }
        
        // Remove old items
        for item in itemsToRemove {
            if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) {
                clipboardItems.remove(at: index)
                modelContext.delete(item)
            }
        }
        
        // Limit total items if we exceed the maximum
        let maxItems = settingsManager.maxHistoryItems
        if clipboardItems.count > maxItems {
            let excessItems = clipboardItems.suffix(clipboardItems.count - maxItems)
            for item in excessItems {
                if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) {
                    clipboardItems.remove(at: index)
                    modelContext.delete(item)
                }
            }
        }
        
        // Save changes if any items were removed
        if !itemsToRemove.isEmpty || clipboardItems.count > maxItems {
            do {
                try modelContext.save()
                print("📋 Automatic cleanup: removed \(itemsToRemove.count) old items")
            } catch {
                print("❌ Failed to save during cleanup: \(error)")
            }
        }

        // Also cleanup orphaned disk files
        cleanupOrphanedDiskFiles()
    }
    
    func getMemoryUsage() -> (totalItems: Int, totalSize: String, diskStoredItems: Int) {
        var totalSize: Int64 = 0
        var diskStoredCount = 0

        for item in clipboardItems {
            if item.diskFilePath != nil {
                diskStoredCount += 1
                // Only count preview/thumbnail data for disk-stored items
                if let thumbnailData = item.thumbnailData {
                    totalSize += Int64(thumbnailData.count)
                }
            } else {
                // Count full content for memory-stored items
                if let imageData = item.imageData {
                    totalSize += Int64(imageData.count)
                }
                if let richTextData = item.richTextData {
                    totalSize += Int64(richTextData.count)
                }
                if let textContent = item.textContent {
                    totalSize += Int64(textContent.utf8.count)
                }
            }
        }

        return (
            clipboardItems.count,
            ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .binary),
            diskStoredCount
        )
    }

    // MARK: - Memory Management
    func cleanupOrphanedDiskFiles() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupportPath = documentsPath?.appendingPathComponent("Photocopy") else {
            return
        }

        do {
            let filesOnDisk = try fileManager.contentsOfDirectory(atPath: appSupportPath.path)
            let diskFilePaths = Set(clipboardItems.compactMap { $0.diskFilePath })

            var orphanedFiles = 0
            for filename in filesOnDisk {
                let filePath = appSupportPath.appendingPathComponent(filename).path
                if !diskFilePaths.contains(filePath) {
                    try fileManager.removeItem(atPath: filePath)
                    orphanedFiles += 1
                }
            }

            if orphanedFiles > 0 {
                print("📋 Cleaned up \(orphanedFiles) orphaned disk files")
            }
        } catch {
            print("❌ Failed to cleanup orphaned disk files: \(error)")
        }
    }
    
    // MARK: - Content Detection Helpers
    
    private func getSourceApp() -> SourceApp {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return SourceApp.unknown
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown App"
        
        // Try to get the app icon
        if let appURL = frontmostApp.bundleURL {
            return SourceApp(name: appName, appPath: appURL.path)
        }
        
        return SourceApp(name: appName, appPath: "/")
    }
    
    private func isURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased() else { return false }
        
        return ["http", "https", "ftp", "file", "mailto", "tel", "sms"].contains(scheme)
    }
    
    private func isEmail(_ text: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return text.range(of: emailRegex, options: .regularExpression) != nil
    }
    
    private func isPhoneNumber(_ text: String) -> Bool {
        let phoneRegex = #"^[\+]?[1-9][\d]{0,15}$"#
        let cleanedText = text.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return cleanedText.range(of: phoneRegex, options: .regularExpression) != nil && cleanedText.count >= 7
    }
    
    // MARK: - Search Functionality
    
    func filterItems() {
        if searchText.isEmpty {
            filteredItems = clipboardItems
        } else {
            filteredItems = clipboardItems.filter { item in
                searchMatches(item: item, query: searchText)
            }
        }
    }
    
    private func searchMatches(item: ClipboardItem, query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        
        // Search in text content
        if let textContent = item.textContent {
            if textContent.lowercased().contains(lowercaseQuery) {
                return true
            }
        }
        
        // Search in URL string
        if let urlString = item.urlString {
            if urlString.lowercased().contains(lowercaseQuery) {
                return true
            }
        }
        
        // Search in file URLs
        if let fileURL = item.fileURL {
            if fileURL.lowercased().contains(lowercaseQuery) {
                return true
            }
        }
        
        // Search in content type
        if item.contentType.rawValue.lowercased().contains(lowercaseQuery) {
            return true
        }
        
        // Search in preview text
        if item.shortPreview.lowercased().contains(lowercaseQuery) {
            return true
        }
        
        // Search in source app name
        if item.sourceApp.name.lowercased().contains(lowercaseQuery) {
            return true
        }
        
        return false
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
