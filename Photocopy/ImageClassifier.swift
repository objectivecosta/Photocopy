//
//  ImageClassifier.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-10-22.
//

import Vision
import VisionKit
import SwiftData
import os.log

@available(macOS 15.0, *)
final class ImageClassifier {
    
    struct ImageVisionData {
        var observations: [String: VNConfidence] = [:]
        var pythonAnalysis: String? = nil
        var pythonAnalysisModel: String? = nil
        var pythonTags: [String]? = nil
        var pythonAnalysisData: PythonAnalysisData? = nil
    }
    
    static let shared = ImageClassifier()

    // Python ML Manager
    private let pythonMLManager = PythonMLManager.shared

    // Logging
    private let logger = Logger(subsystem: "com.photocopy.app", category: "ImageClassifier")
    
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

    // MARK: - Python ML Analysis Methods

    private func analyzeImageWithPython(imagePath: String) async -> (analysis: String?, tags: [String]?, analysisData: PythonAnalysisData?) {
        logger.info("Starting Python ML analysis for image: \(imagePath)")

        do {
            let response = await pythonMLManager.analyzeImageWithResponse(imagePath)

            if let response = response {
                logger.info("Python ML analysis completed successfully")
                logger.info("Analysis result: \(response.caption?.prefix(100) ?? "No caption")...")
                if let tags = response.tags {
                    logger.info("Generated tags: \(tags.joined(separator: ", "))")
                }
                return (response.caption, response.tags, response.analysis)
            } else {
                logger.warning("Python ML analysis returned nil")
                return (nil, nil, nil)
            }

        } catch {
            logger.error("Python ML analysis failed: \(error.localizedDescription)")
            return (nil, nil, nil)
        }
    }

    func classifyImageOnDiskItemWithPython(clipboardItem: ClipboardItem) async throws -> ImageVisionData {
        guard case let .imageOnDisk(imagePath, _) = clipboardItem.content else {
            return ImageVisionData()
        }

        var imageVisionData = ImageVisionData()

        // Perform Python ML analysis
        let (analysis, tags, analysisData) = await analyzeImageWithPython(imagePath: imagePath)
        imageVisionData.pythonAnalysis = analysis
        imageVisionData.pythonTags = tags
        imageVisionData.pythonAnalysisData = analysisData
        imageVisionData.pythonAnalysisModel = "moondream2"

        return imageVisionData
    }

    func classifyImageInMemoryItemWithPython(clipboardItem: ClipboardItem) async throws -> ImageVisionData {
        guard case let .imageInMemory(data, _) = clipboardItem.content else {
            return ImageVisionData()
        }

        // Create temporary file for in-memory image
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("temp_image_\(UUID().uuidString).jpg")

        do {
            // Write image data to temporary file
            try data.write(to: tempFile)

            // Perform Python ML analysis
            var imageVisionData = ImageVisionData()
            let (analysis, tags, analysisData) = await analyzeImageWithPython(imagePath: tempFile.path)
            imageVisionData.pythonAnalysis = analysis
            imageVisionData.pythonTags = tags
            imageVisionData.pythonAnalysisData = analysisData
            imageVisionData.pythonAnalysisModel = "moondream2"

            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempFile)

            return imageVisionData

        } catch {
            logger.error("Failed to process in-memory image with Python ML: \(error.localizedDescription)")
            // Clean up temporary file on error
            try? FileManager.default.removeItem(at: tempFile)
            return ImageVisionData()
        }
    }

    func classifyItemOnDemandWithPython(_ clipboardItem: ClipboardItem) async throws -> ImageVisionData? {
        // Check if AI insights are enabled in settings
        guard await SettingsManager.shared.enableAIInsights else {
            return nil
        }

        // Only classify images
        guard clipboardItem.content.type == .image else {
            return nil
        }

        // Check if Python ML is available
        guard await pythonMLManager.performHealthCheck() else {
            logger.warning("Python ML service health check failed - skipping Python analysis")
            return nil
        }

        // Perform classification based on storage type
        switch clipboardItem.content {
        case .imageOnDisk:
            return try await classifyImageOnDiskItemWithPython(clipboardItem: clipboardItem)
        case .imageInMemory:
            return try await classifyImageInMemoryItemWithPython(clipboardItem: clipboardItem)
        default:
            return nil
        }
    }

    func batchClassifyItemsWithPython(
        _ items: [ClipboardItem],
        progressHandler: ((Int, Int) async -> Void)? = nil
    ) async throws -> [ImageVisionData] {
        let imageItems = items.filter { item in
            if item.content.type == .image { return true }
            return false
        }

        var results: [ImageVisionData] = []
        var processedCount = 0

        // Check if Python ML is available
        guard await pythonMLManager.performHealthCheck() else {
            logger.warning("Python ML service not available - skipping batch Python classification")
            return results
        }

        for item in imageItems {
            if let classification = try await classifyItemOnDemandWithPython(item) {
                results.append(classification)
            }
            processedCount += 1

            // Report progress
            if let progressHandler = progressHandler {
                await progressHandler(processedCount, imageItems.count)
            }

            // Add small delay to prevent overwhelming the system
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        logger.info("✅ Batch Python classification completed. Processed \(results.count) images.")
        return results
    }
}
