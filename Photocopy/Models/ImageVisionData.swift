//
//  ImageVisionData.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-10-22.
//

import Foundation
import SwiftData

final class ImageVisionData {
    let id: UUID
    let clipboardItemId: UUID?
    let createdAt: Date
    private var _observations: [String: Float]

    init(
        clipboardItemId: UUID? = nil,
        observations: [String: Float] = [:]
    ) {
        self.id = UUID()
        self.clipboardItemId = clipboardItemId
        self.createdAt = Date()
        self._observations = observations
    }

    // MARK: - Computed Properties

    var observationsDictionary: [String: Float] {
        get { _observations }
        set { _observations = newValue }
    }

    var topClassification: (String, Float)? {
        let dict = observationsDictionary
        guard let maxEntry = dict.max(by: { $0.value < $1.value }) else {
            return nil
        }
        return maxEntry
    }

    var allClassifications: [(String, Float)] {
        return observationsDictionary
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    // MARK: - No longer needed (in-memory storage)

    // MARK: - Helper Methods

    func addObservation(_ classification: String, confidence: Float) {
        var dict = observationsDictionary
        dict[classification] = confidence
        observationsDictionary = dict
    }

    func removeObservation(_ classification: String) {
        var dict = observationsDictionary
        dict.removeValue(forKey: classification)
        observationsDictionary = dict
    }

    func hasClassification(_ classification: String) -> Bool {
        return observationsDictionary[classification] != nil
    }

    func getConfidence(for classification: String) -> Float? {
        return observationsDictionary[classification]
    }

    func getClassificationsAbove(threshold: Float) -> [(String, Float)] {
        return observationsDictionary
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }
}

// MARK: - Convenience Extensions

@available(macOS 15.0, *)
extension ImageVisionData {
    convenience init(clipboardItem: ClipboardItem? = nil, imageClassifierData: VisionClassifications) {
        self.init(
            clipboardItemId: clipboardItem?.id,
            observations: imageClassifierData.observations
        )
    }

    func matchesClassifierData(_ classifierData: VisionClassifications) -> Bool {
        let dict = observationsDictionary
        return dict.keys.sorted() == classifierData.observations.keys.sorted() &&
               dict.allSatisfy { key, value in
                   abs(value - (classifierData.observations[key] ?? 0)) < 0.001
               }
    }
}
