//
//  Logger.swift
//  Photocopy
//
//  Created by Rafael Costa on 2026-04-05.
//

import OSLog
import Combine

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

    func subscribe(logger: Logger) {
        logger.logPublisher
            .sink(receiveValue: { [weak self] entry in
                guard let self else { return }
                entries.append(entry)
                // Trim if needed
                if entries.count > maxEntries {
                    entries.removeFirst(entries.count - maxEntries)
                }
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
            level: .debug,
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
        operatingSystemLogger.debug("\(message)")
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
