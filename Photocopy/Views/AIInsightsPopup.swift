//
//  AIInsightsPopup.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-10-22.
//

import SwiftUI

struct AIInsightsPopup: View {
    let classifications: [(String, Float)]
    let isVisible: Bool
    let onClose: () -> Void

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 16, weight: .medium))

                        Text("AI Insights")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }

                // Divider
                Divider()

                // Classifications content
                if classifications.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("No AI insights available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("This image hasn't been analyzed yet")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image Classifications:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(classifications.prefix(5).enumerated()), id: \.offset) { index, classification in
                                HStack {
                                    // Rank number
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .frame(width: 20, alignment: .leading)

                                    // Classification label
                                    Text(classification.0)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .help(classification.0)

                                    Spacer()

                                    // Confidence score
                                    HStack(spacing: 4) {
                                        // Confidence bar
                                        GeometryReader { geometry in
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(confidenceColor(for: classification.1))
                                                .frame(width: geometry.size.width * CGFloat(classification.1), height: 4)
                                        }
                                        .frame(width: 30, height: 4)

                                        // Confidence percentage
                                        Text("\(Int(classification.1 * 100))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(confidenceColor(for: classification.1))
                                            .frame(width: 35, alignment: .trailing)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.05))
                                )
                            }
                        }

                        if classifications.count > 5 {
                            Text("... and \(classifications.count - 5) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                        }
                    }
                }

                // Footer info
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("AI-powered image analysis using Vision framework")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
            }
            .padding(16)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
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
}

#Preview {
    VStack {
        Spacer()

        AIInsightsPopup(
            classifications: [
                ("Cat", 0.92),
                ("Animal", 0.87),
                ("Pet", 0.78),
                ("Feline", 0.65),
                ("Kitten", 0.54),
                ("Domestic", 0.43),
                ("Mammal", 0.38)
            ],
            isVisible: true,
            onClose: {}
        )

        Spacer()
    }
    .background(Color.gray.opacity(0.1))
}