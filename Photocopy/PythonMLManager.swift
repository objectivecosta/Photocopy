//
//  PythonMLManager.swift
//  Photocopy
//
//  Created by Rafael Costa on 2025-10-27.
//

import Foundation
import os.log

@MainActor
class PythonMLManager: ObservableObject {
    static let shared = PythonMLManager()

    // MARK: - Published Properties
    @Published var isModelLoaded = false
    @Published var isProcessing = false
    @Published var lastError: String?

    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.photocopy.app", category: "PythonMLManager")
    private var pythonBinaryPath: String?
    private var configPath: String?
    private var processQueue: [PythonMLTask] = []
    private var isTaskRunning = false

    // Configuration
    private let maxConcurrentTasks = 1
    private let taskTimeout: TimeInterval = 120.0 // 2 minutes

    private init() {
        setupPythonEnvironment()
    }

    // MARK: - Setup

    private func setupPythonEnvironment() {
        guard let bundlePath = Bundle.main.resourcePath else {
            logger.error("Failed to get bundle path")
            return
        }

        let pythonResourcesPath = bundlePath.appending("/Python")
        pythonBinaryPath = pythonResourcesPath.appending("/photocopier")
        configPath = pythonResourcesPath.appending("/config.json")

        // Verify paths exist
        guard FileManager.default.fileExists(atPath: pythonBinaryPath!) else {
            logger.error("Python binary not found at: \(self.pythonBinaryPath ?? "unknown")")
            pythonBinaryPath = nil
            return
        }

        guard FileManager.default.fileExists(atPath: configPath!) else {
            logger.error("Python config not found at: \(self.configPath ?? "unknown")")
            configPath = nil
            return
        }

        logger.info("Python environment setup complete")
        logger.info("Binary path: \(self.pythonBinaryPath!)")
        logger.info("Config path: \(self.configPath!)")
    }

    // MARK: - Health Check

    func performHealthCheck() async -> Bool {
        guard let binaryPath = pythonBinaryPath else {
            logger.error("Python binary path not configured")
            return false
        }

        do {
            let result = try await runPythonProcess(arguments: ["--mode", "health"])
            let response = try JSONDecoder().decode(PythonHealthResponse.self, from: result.data(using: .utf8)!)

            isModelLoaded = response.modelLoaded ?? false

            if response.status == "healthy" {
                logger.info("Python ML service health check passed")
                return true
            } else {
                logger.error("Python ML service health check failed: \(response.status)")
                return false
            }

        } catch {
            logger.error("Health check failed: \(error.localizedDescription)")
            lastError = "Health check failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Image Analysis

    func analyzeImage(_ imagePath: String) async -> String? {
        let response = await analyzeImageWithResponse(imagePath)
        return response?.caption
    }

    func analyzeImageWithResponse(_ imagePath: String) async -> PythonAnalysisResponse? {
        guard let binaryPath = pythonBinaryPath else {
            logger.error("Python binary not configured")
            lastError = "Python binary not configured"
            return nil
        }

        logger.info("Starting image analysis for: \(imagePath)")
        isProcessing = true
        lastError = nil

        defer {
            isProcessing = false
        }

        do {
            let result = try await runPythonProcess(arguments: ["--mode", "analyze", "--image", imagePath])
            let response = try JSONDecoder().decode(PythonAnalysisResponse.self, from: result.data(using: .utf8)!)

            if response.status == "success" {
                logger.info("Image analysis completed successfully")
                logger.info("Caption: \(response.caption ?? "No caption")")
                if let tags = response.tags {
                    logger.info("Tags: \(tags.joined(separator: ", "))")
                }
                return response
            } else {
                logger.error("Image analysis failed: \(response.error ?? "Unknown error")")
                lastError = response.error
                return nil
            }

        } catch {
            logger.error("Image analysis failed: \(error.localizedDescription)")
            lastError = "Analysis failed: \(error.localizedDescription)"
            return nil
        }
    }

    func analyzeImageWithSettings(_ imagePath: String, settings: PythonAnalysisSettings) async -> String? {
        guard let binaryPath = pythonBinaryPath else {
            logger.error("Python binary not configured")
            lastError = "Python binary not configured"
            return nil
        }

        logger.info("Starting image analysis with custom settings for: \(imagePath)")
        isProcessing = true
        lastError = nil
        
        defer {
            isProcessing = false
        }

        do {
            let requestData = PythonAnalysisRequest(
                action: "analyze",
                imagePath: imagePath,
                settings: settings
            )

            let jsonData = try JSONEncoder().encode(requestData)
            let jsonString = String(data: jsonData, encoding: .utf8)!

            let result = try await runPythonProcessWithInput(input: jsonString)
            let response = try JSONDecoder().decode(PythonAnalysisResponse.self, from: result.data(using: .utf8)!)

            if response.status == "success" {
                logger.info("Custom settings analysis completed successfully")
                logger.info("Caption: \(response.caption ?? "No caption")")
                return response.caption
            } else {
                logger.error("Custom settings analysis failed: \(response.error ?? "Unknown error")")
                lastError = response.error
                return nil
            }

        } catch {
            logger.error("Custom settings analysis failed: \(error.localizedDescription)")
            lastError = "Analysis failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Private Process Methods

    private func runPythonProcess(arguments: [String]) async throws -> String {
        guard let binaryPath = pythonBinaryPath else {
            throw PythonMLError.binaryNotConfigured
        }

        let process = Process()
        // Old way: Running through shell - incorrect
        // process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // process.arguments = ["-c", binaryPath] + arguments

        // New way: Run Python script directly
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let data = try outputPipe.fileHandleForReading.readToEnd()
        let errorData = try errorPipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        // Log stderr for debugging
        if let errorString = errorData.flatMap({ String(data: $0, encoding: .utf8) }), !errorString.isEmpty {
            logger.error("Python process stderr: \(errorString)")
        }

        guard let output = data.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw PythonMLError.noOutput
        }

        if process.terminationStatus != 0 {
            throw PythonMLError.processFailed(process.terminationStatus, output)
        }

        return output
    }

    private func runPythonProcessWithInput(input: String) async throws -> String {
        guard let binaryPath = pythonBinaryPath else {
            throw PythonMLError.binaryNotConfigured
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError

        try process.run()

        // Write input to process
        try inputPipe.fileHandleForWriting.write(contentsOf: input.data(using: .utf8) ?? Data())
        try inputPipe.fileHandleForWriting.close()

        let data = try outputPipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        guard let output = data.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw PythonMLError.noOutput
        }

        if process.terminationStatus != 0 {
            throw PythonMLError.processFailed(process.terminationStatus, output)
        }

        return output
    }
}

// MARK: - Data Models

struct PythonAnalysisRequest: Codable {
    let action: String
    let imagePath: String
    let settings: PythonAnalysisSettings?
}

struct PythonAnalysisSettings: Codable {
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let length: String?

    init(temperature: Double? = nil, maxTokens: Int? = nil, topP: Double? = nil, length: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.length = length
    }
}

struct PythonAnalysisResponse: Codable {
    let status: String
    let caption: String?
    let tags: [String]?
    let analysis: PythonAnalysisData?
    let error: String?
    let processingTime: Double?
    let imagePath: String?
    let imageSize: [Int]?
    let modelInfo: PythonModelInfo?
}

struct PythonAnalysisData: Codable {
    let objects: [String]?
    let scene: String?
    let colors: [String]?
    let actions: [String]?
}

struct PythonHealthResponse: Codable {
    let status: String
    let modelLoaded: Bool?
    let device: String?
    let config: PythonConfig?
}

struct PythonConfig: Codable {
    let model: PythonModelConfig?
    let generationSettings: PythonGenerationSettings?
}

struct PythonModelConfig: Codable {
    let name: String?
    let repository: String?
    let device: String?
}

struct PythonGenerationSettings: Codable {
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let length: String?
}

struct PythonModelInfo: Codable {
    let name: String?
    let repository: String?
}

// MARK: - Error Types

enum PythonMLError: LocalizedError {
    case binaryNotConfigured
    case noOutput
    case processFailed(Int32, String)
    case jsonDecoding(Error)

    var errorDescription: String? {
        switch self {
        case .binaryNotConfigured:
            return "Python binary is not configured or missing"
        case .noOutput:
            return "Python process produced no output"
        case .processFailed(let code, let output):
            return "Python process failed with exit code \(code): \(output)"
        case .jsonDecoding(let error):
            return "Failed to decode JSON response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Task Management

struct PythonMLTask {
    let id: UUID
    let type: TaskType
    let imagePath: String
    let settings: PythonAnalysisSettings?
    let completion: (Result<String?, PythonMLError>) -> Void

    enum TaskType {
        case basicAnalysis
        case customSettingsAnalysis
    }
}
