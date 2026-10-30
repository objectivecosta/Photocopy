//
//  Logger.swift
//  Photocopy
//
//  Created by Rafael Costa on 2026-04-05.
//

import OSLog
import Combine
import Foundation

@Observable
final class ApplicationLogger {
    static let shared = ApplicationLogger()

    struct Entry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let level: Level
        let category: String
        let message: String

        enum Level: String, Codable {
            case debug = "DEBUG"
            case info = "INFO"
            case warning = "WARNING"
            case error = "ERROR"
        }

        var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }

    private(set) var entries: [Entry] = []
    private var subscriptions: Set<AnyCancellable> = []
    private let maxEntries = 1000

    // MARK: - File logging

    private static let logsDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Photocopy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let currentLogFileURL = logsDirectory.appendingPathComponent("photocopy.log")
    static let previousLogFileURL = logsDirectory.appendingPathComponent("photocopy-previous.log")

    private let fileQueue = DispatchQueue(label: "com.photocopy.log-file", qos: .utility)
    private var fileHandle: FileHandle?

    private static var hasBootstrapped = false

    /// Must be called once at startup to set up file logging.
    /// Safe to call multiple times — subsequent calls are no-ops.
    static func bootstrapFileLogging() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // Rotate: delete old previous, rename current → previous, create new
        try? FileManager.default.removeItem(at: previousLogFileURL)

        if FileManager.default.fileExists(atPath: currentLogFileURL.path) {
            try? FileManager.default.moveItem(at: currentLogFileURL, to: previousLogFileURL)
        }

        // Create the new log file
        FileManager.default.createFile(atPath: currentLogFileURL.path, contents: nil)

        // Write a header so we know when this session started
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let header = "=== Photocopy session started at \(formatter.string(from: Date())) ===\n"
        if let data = header.data(using: .utf8) {
            try? data.write(to: currentLogFileURL, options: .atomic)
        }

        // Open file handle for appending
        shared.fileHandle = try? FileHandle(forWritingTo: currentLogFileURL)
        shared.fileHandle?.seekToEndOfFile()
    }

    private func writeToFile(_ entry: Entry) {
        fileQueue.async { [weak self] in
            guard let self, let handle = self.fileHandle else { return }
            let line = "[\(entry.formattedTimestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)\n"
            if let data = line.data(using: .utf8) {
                handle.write(data)
                handle.synchronizeFile()
            }
        }
    }

    // MARK: - Public

    static var logsDirectoryURL: URL { logsDirectory }

    static var logFileSize: Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: currentLogFileURL.path) else {
            return -1
        }
        return (attrs[.size] as? Int) ?? -1
    }

    func subscribe(logger: Logger) {
        logger.logPublisher
            .sink(receiveValue: { [weak self] entry in
                guard let self else { return }
                entries.append(entry)
                if entries.count > maxEntries {
                    entries.removeFirst(entries.count - maxEntries)
                }
                self.writeToFile(entry)
            }).store(in: &subscriptions)
    }

    func clear() {
        entries.removeAll()
    }
}

final class Logger {
    private let logSubject: PassthroughSubject<ApplicationLogger.Entry, Never> = .init()
    public var logPublisher: AnyPublisher<ApplicationLogger.Entry, Never> {
        logSubject.eraseToAnyPublisher()
    }

    private let operatingSystemLogger: os.Logger
    private let subsystem: String
    private let category: String

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        self.operatingSystemLogger = os.Logger.init(subsystem: subsystem, category: category)

        ApplicationLogger.shared.subscribe(logger: self)
    }

    func debug(_ message: String) {
        let entry = ApplicationLogger.Entry(
            id: UUID(),
            timestamp: Date(),
            level: .debug,
            category: category,
            message: message
        )
        logSubject.send(entry)
        operatingSystemLogger.debug("\(message)")
    }

    func info(_ message: String, category: String = "App") {
        let entry = ApplicationLogger.Entry(
            id: UUID(),
            timestamp: Date(),
            level: .info,
            category: category,
            message: message
        )
        logSubject.send(entry)
        operatingSystemLogger.info("\(message)")
    }

    func error(_ message: String, category: String = "App") {
        let entry = ApplicationLogger.Entry(
            id: UUID(),
            timestamp: Date(),
            level: .error,
            category: category,
            message: message
        )
        logSubject.send(entry)
        operatingSystemLogger.error("\(message)")
    }

    func warning(_ message: String, category: String = "App") {
        let entry = ApplicationLogger.Entry(
            id: UUID(),
            timestamp: Date(),
            level: .warning,
            category: category,
            message: message
        )
        logSubject.send(entry)
        operatingSystemLogger.warning("\(message)")
    }
}
