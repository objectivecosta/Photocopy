//
//  ClipboardItemCard.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-05-25.
//

import Foundation
import SwiftUI
import AppKit

struct ClipboardItemCard: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let onTap: () -> Void
    
    // MARK: - State
    @State private var aiInsights: ImageVisionData?
    @State private var isGeneratingAIInsights = false
    @State private var showingFullInsights = false
    
    // MARK: - Equatable
    
    static func == (lhs: ClipboardItemCard, rhs: ClipboardItemCard) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSelected == rhs.isSelected
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Left side: Icon and type tag grouped together
            VStack(spacing: 6) {
                // Icon (always SF Symbol, even for images)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(contentTypeColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(contentTypeColor.opacity(0.3), lineWidth: 1)
                        )
                    
                    contentTypeIcon
                        .foregroundColor(contentTypeColor)
                        .font(.system(size: 16))
                }
                .frame(width: 40, height: 40)
                
                // Type tag
                Text(item.contentType.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(contentTypeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(contentTypeColor.opacity(0.15), in: Capsule())
            }
            .frame(width: 60)
            
            // Right side: Content preview and timestamp
            VStack(alignment: .leading, spacing: 6) {
                // Content area - text or image
                if item.contentType == .image,
                   let imageData = item.imageData,
                   let nsImage = ImageCache.shared.getImage(for: imageData) {
                    // Display image in the content area (no white background)
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                        )
                } else {
                    // Display text content with white background
                    Text(item.shortPreview)
                        .font(.subheadline)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.black)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                }
                
                // Timestamp aligned to the right
                HStack {
                    // Source app (always available now)
                    HStack(spacing: 4) {
                        // App icon
                        sourceAppIcon
                        
                        // App name
                        Text(item.sourceApp.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                    
                    Spacer()
                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // AI Classification Pills (shown when available and enabled)
                if item.contentType == .image && SettingsManager.shared.enableAIInsights {
                    classificationPillsView
                }
            }
        }
        .padding(8)
        .frame(width: 380, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onTapGesture {
            onTap()
        }
        .onAppear {
            // Auto-generate AI insights when enabled and item is an image
            if item.contentType == .image && SettingsManager.shared.enableAIInsights && aiInsights == nil {
                generateAIInsights()
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: showingFullInsights) { _, isShowing in
                        if isShowing {
                            // Convert the card's frame to screen coordinates
                            let screenFrame = geometry.frame(in: .global)
                            let screenRect = NSRect(
                                x: screenFrame.minX,
                                y: NSScreen.main?.visibleFrame.height ?? 0 - screenFrame.maxY,
                                width: screenFrame.width,
                                height: screenFrame.height
                            )
                            AIInsightsWindowManager.shared.showInsights(
                                classifications: aiInsights?.allClassifications ?? [],
                                sourceRect: screenRect
                            )
                        } else {
                            AIInsightsWindowManager.shared.hideInsights()
                        }
                    }
            }
        )
    }
    
    private var contentTypeIcon: some View {
        Group {
            switch item.contentType {
            case .text:
                Image(systemName: "doc.text.fill")
            case .url:
                Image(systemName: "link.circle.fill")
            case .image:
                Image(systemName: "photo.fill")
            case .file:
                Image(systemName: "doc.fill")
            case .richText:
                Image(systemName: "doc.richtext.fill")
            case .unknown:
                Image(systemName: "questionmark.circle.fill")
            }
        }
    }
    
    private var contentTypeColor: Color {
        switch item.contentType {
        case .text: return .blue
        case .url: return .green
        case .image: return .purple
        case .file: return .orange
        case .richText: return .red
        case .unknown: return .gray
        }
    }
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.timestamp, relativeTo: Date())
    }
    
    private var sourceAppIcon: some View {
        if let icon = item.sourceApp.icon {
            return AnyView(Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
            )
        } else {
            return AnyView(Image(systemName: "app.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            )
        }
    }
    
    // MARK: - AI Insights Methods
    
    private func generateAIInsights() {
        guard #available(macOS 15.0, *) else {
            print("❌ AI Insights require macOS 15.0+")
            return
        }
        
        guard SettingsManager.shared.enableAIInsights else {
            print("❌ AI Insights are disabled in settings")
            return
        }
        
        isGeneratingAIInsights = true
        
        Task {
            do {
                if let classification = try await ImageClassifier.shared.classifyItemOnDemand(item) {
                    await MainActor.run {
                        self.aiInsights = ImageVisionData(
                            clipboardItemId: item.id,
                            observations: classification.observations
                        )
                        print("✅ Generated AI insights for image: \(item.id)")
                    }
                } else {
                    await MainActor.run {
                        print("⚠️ No AI insights available for this image")
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to generate AI insights: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                self.isGeneratingAIInsights = false
            }
        }
    }
    
    // MARK: - AI Classification Pills View
    
    private var classificationPillsView: some View {
        HStack(spacing: 6) {
            // First pill: AI Sparkles (always shown first when enabled)
            HStack(spacing: 4) {
                Image(systemName: isGeneratingAIInsights ? "sparkles" : "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
            )
            .help("AI-powered image classification")
            
            // Classification pills
            if let insights = aiInsights, !insights.allClassifications.isEmpty {
                ForEach(Array(insights.allClassifications.prefix(3).enumerated()), id: \.offset) { index, classification in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(confidenceColor(for: classification.1))
                            .frame(width: 4, height: 4)
                        
                        Text(classification.0)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(confidenceBackgroundColor(for: classification.1))
                    )
                    .help("\(classification.0): \(Int(classification.1 * 100))% confidence")
                }
                
                // "More" indicator if there are more classifications
                if insights.allClassifications.count > 3 {
                    Button(action: {
                        showingFullInsights = true
                    }) {
                        Text("+\(insights.allClassifications.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Show all \(insights.allClassifications.count) classifications")
                }
            } else if isGeneratingAIInsights {
                // Loading indicator
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    
                    Text("Analyzing...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
        }
    }
    
    private func confidenceColor(for confidence: Float) -> Color {
        switch confidence {
        case 0.8...:
            return .green
        case 0.6..<0.8:
            return .orange
        case 0.4..<0.6:
            return .yellow
        default:
            return .red
        }
    }
    
    private func confidenceBackgroundColor(for confidence: Float) -> Color {
        switch confidence {
        case 0.8...:
            return .green.opacity(0.15)
        case 0.6..<0.8:
            return .orange.opacity(0.15)
        case 0.4..<0.6:
            return .yellow.opacity(0.15)
        default:
            return .red.opacity(0.15)
        }
    }
}

//// MARK: - Previews
//#Preview("Text Item - Selected") {
//    let sampleTextItem = ClipboardItem(
//        contentType: .text,
//        textContent: "This is a sample text content that demonstrates how the clipboard item card looks with a longer text preview. It should wrap nicely and show the text formatting.",
//        preview: "This is a sample text content that demonstrates how the clipboard item card looks with a longer text preview. It should wrap nicely and show the text formatting.",
//        sourceApp: SourceApp(name: "Safari", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleTextItem,
//        isSelected: true,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("Text Item - Unselected") {
//    let sampleTextItem = ClipboardItem(
//        contentType: .text,
//        textContent: "Short text sample",
//        preview: "Short text sample",
//        sourceApp: SourceApp(name: "Notes", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleTextItem,
//        isSelected: false,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("URL Item") {
//    let sampleURLItem = ClipboardItem(
//        contentType: .url,
//        urlString: "https://www.apple.com/developer/documentation/swiftui/",
//        preview: "https://www.apple.com/developer/documentation/swiftui/",
//        sourceApp: SourceApp(name: "Chrome", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleURLItem,
//        isSelected: false,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("File Item") {
//    let sampleFileItem = ClipboardItem(
//        contentType: .file,
//        fileURLs: ["/Users/username/Documents/Important Document.pdf"],
//        preview: "File: Important Document.pdf",
//        sourceApp: SourceApp(name: "Finder", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleFileItem,
//        isSelected: false,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("Rich Text Item") {
//    let sampleRichTextItem = ClipboardItem(
//        contentType: .richText,
//        richTextData: "Sample rich text content".data(using: .utf8),
//        preview: "This is a sample rich text content that might contain formatting, bold text, italics, and other styling elements.",
//        sourceApp: SourceApp(name: "Pages", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleRichTextItem,
//        isSelected: false,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("Unknown Item") {
//    let sampleUnknownItem = ClipboardItem(
//        contentType: .unknown,
//        preview: "Unknown content type: com.custom.type (2.5 MB)",
//        sourceApp: SourceApp(name: "Terminal", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleUnknownItem,
//        isSelected: false,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("Image Item") {
//    // Create a simple colored rectangle as sample image data
//    let sampleImage = NSImage(size: NSSize(width: 200, height: 150))
//    sampleImage.lockFocus()
//    NSColor.systemPurple.setFill()
//    NSRect(x: 0, y: 0, width: 200, height: 150).fill()
//    NSColor.white.setFill()
//    "Sample Image".draw(at: NSPoint(x: 50, y: 65), withAttributes: [
//        .font: NSFont.systemFont(ofSize: 16),
//        .foregroundColor: NSColor.white
//    ])
//    sampleImage.unlockFocus()
//    
//    let sampleImageItem = ClipboardItem(
//        contentType: .image,
//        imageData: sampleImage.tiffRepresentation,
//        preview: "Sample Image (PNG, 200×150, 15.2 KB)",
//        sourceApp: SourceApp(name: "Preview", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleImageItem,
//        isSelected: false,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("Source App with Icon") {
//    // Create a sample app icon
//    let sampleIcon = NSImage(size: NSSize(width: 32, height: 32))
//    sampleIcon.lockFocus()
//    NSColor.systemBlue.setFill()
//    NSRect(x: 0, y: 0, width: 32, height: 32).fill()
//    NSColor.white.setFill()
//    "S".draw(at: NSPoint(x: 8, y: 8), withAttributes: [
//        .font: NSFont.systemFont(ofSize: 16, weight: .bold),
//        .foregroundColor: NSColor.white
//    ])
//    sampleIcon.unlockFocus()
//    
//    let sampleTextItem = ClipboardItem(
//        contentType: .text,
//        textContent: "This demonstrates how the source app looks with an actual app icon.",
//        preview: "This demonstrates how the source app looks with an actual app icon.",
//        sourceApp: SourceApp(name: "Sample App", appPath: "/Applications/Preview.app")
//    )
//    
//    return ClipboardItemCard(
//        item: sampleTextItem,
//        isSelected: false,
//        onTap: {}
//    )
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
//
//#Preview("All Content Types") {
//    let sampleItems = [
//        ClipboardItem(
//            contentType: .text,
//            textContent: "Sample text content for preview",
//            preview: "Sample text content for preview",
//            sourceApp: SourceApp(name: "Safari", appPath: "/Applications/Preview.app")
//        ),
//        ClipboardItem(
//            contentType: .url,
//            urlString: "https://example.com",
//            preview: "https://example.com",
//            sourceApp: SourceApp(name: "Chrome", appPath: "/Applications/Preview.app")
//        ),
//        ClipboardItem(
//            contentType: .file,
//            fileURLs: ["/path/to/document.pdf"],
//            preview: "File: document.pdf",
//            sourceApp: SourceApp(name: "Finder", appPath: "/Applications/Preview.app")
//        ),
//        ClipboardItem(
//            contentType: .richText,
//            richTextData: "Rich text sample".data(using: .utf8),
//            preview: "Rich text sample content",
//            sourceApp: SourceApp(name: "Pages", appPath: "/Applications/Preview.app")
//        ),
//        ClipboardItem(
//            contentType: .unknown,
//            preview: "Unknown content type",
//            sourceApp: SourceApp(name: "Terminal", appPath: "/Applications/Preview.app")
//        )
//    ]
//    
//    return VStack(spacing: 20) {
//        ForEach(Array(sampleItems.enumerated()), id: \.element.id) { index, item in
//            ClipboardItemCard(
//                item: item,
//                isSelected: index == 0, // First item selected
//                onTap: {}
//            )
//        }
//    }
//    .padding()
//    .background(Color.gray.opacity(0.1))
//}
