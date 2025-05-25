//
//  ImageClassifier.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-10-22.
//

import Vision
import VisionKit
import SwiftData

@available(macOS 15.0, *)
final class ImageClassifier {
    
    struct ImageVisionData {
        var observations: [String: VNConfidence] = [:]
    }
    
    static let shared = ImageClassifier()
    
    func classifyImageOnDiskItem(clipboardItem: ClipboardItem) async throws -> ImageVisionData {
        guard case let .imageOnDisk(imagePath, _) = clipboardItem.content else {
            return ImageVisionData()
        }
        
        let url = URL(fileURLWithPath: imagePath)

        let data = try Data(contentsOf: url)
        var image = ImageVisionData()

        // Vision request to classify an image.
        let request = ClassifyImageRequest()

        // Perform the request on the image, and return an array of `ClassificationObservation` objects.
        let results = try await request.perform(on: data)

        // High-recall approach: Get more classifications (better for clipboard search/discovery)
//        let filteredResults = results
//            .filter { $0.hasMinimumPrecision(0.1, forRecall: 0.8) }

        // Alternative high-precision approach (if you prefer accuracy over quantity):
         let filteredResults = results
             .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
        

        // Add each classification identifier and its respective confidence level into the observations dictionary.
        for classification in filteredResults {
            image.observations[classification.identifier] = classification.confidence
        }

        return image
    }
    
    func classifyImageItem(clipboardItem: ClipboardItem) async throws -> ImageVisionData {
        guard case let .imageInMemory(data, _) = clipboardItem.content else {
            return ImageVisionData()
        }

        var image = ImageVisionData()

        // Vision request to classify an image.
        let request = ClassifyImageRequest()

        // Perform the request on the image, and return an array of `ClassificationObservation` objects.
        let results = try await request.perform(on: data)
        // Use `hasMinimumPrecision` for a high-recall filter.
            .filter { $0.hasMinimumPrecision(0.1, forRecall: 0.8) }
        // Use `hasMinimumRecall` for a high-precision filter.
        // .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }

        // Add each classification identifier and its respective confidence level into the observations dictionary.
        for classification in results {
            image.observations[classification.identifier] = classification.confidence
        }

        return image
    }

    // MARK: - On-Demand Classification Methods

    func classifyItemOnDemand(_ clipboardItem: ClipboardItem) async throws -> ImageVisionData? {
        // Check if AI insights ModelConfigurationare enabled in settings
        guard await SettingsManager.shared.enableAIInsights else {
            return nil
        }

        // Only classify images stored on disk (we only want to classify disk images for performance)
        guard clipboardItem.content.type == .image else {
            return nil
        }

        // Perform classification

        switch clipboardItem.content {
        case .imageOnDisk:
            return try await classifyImageOnDiskItem(clipboardItem: clipboardItem)
        case .imageInMemory:
            return try await classifyImageItem(clipboardItem: clipboardItem)
        default:
            return nil
        }
    }

    func batchClassifyItems(
        _ items: [ClipboardItem],
        progressHandler: ((Int, Int) async -> Void)? = nil
    ) async throws -> [ImageVisionData] {
        let diskImageItems = items.filter { item in
            if case .imageOnDisk = item.content { return true }
            return false
        }

        var results: [ImageVisionData] = []
        var processedCount = 0

        for item in diskImageItems {
            if let classification = try await classifyItemOnDemand(item) {
                results.append(classification)
            }
            processedCount += 1

            // Report progress
            if let progressHandler = progressHandler {
                await progressHandler(processedCount, diskImageItems.count)
            }
        }

        print("✅ Batch classification completed. Processed \(results.count) images.")
        return results
    }

    func getClassificationsForItems(_ items: [ClipboardItem]) async throws -> [UUID: ImageVisionData] {
        var results: [UUID: ImageVisionData] = [:]

        for item in items {
            if let classification = try await classifyItemOnDemand(item) {
                results[item.id] = classification
            }
        }

        return results
    }
}
