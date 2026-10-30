import SwiftUI
import AppKit

struct LogViewerView: View {
    private let applicationLogger = ApplicationLogger.shared
    @State private var selectedLevel: ApplicationLogger.Entry.Level? = nil
    @State private var searchText: String = ""

    var filteredLogs: [ApplicationLogger.Entry] {
        applicationLogger.entries.filter { entry in
            let levelMatch = selectedLevel == nil || entry.level == selectedLevel
            let searchMatch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.localizedCaseInsensitiveContains(searchText)
            return levelMatch && searchMatch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Level", selection: $selectedLevel) {
                    Text("All").tag(nil as ApplicationLogger.Entry.Level?)
                    Text("Debug").tag(ApplicationLogger.Entry.Level.debug as ApplicationLogger.Entry.Level?)
                    Text("Info").tag(ApplicationLogger.Entry.Level.info as ApplicationLogger.Entry.Level?)
                    Text("Warning").tag(ApplicationLogger.Entry.Level.warning as ApplicationLogger.Entry.Level?)
                    Text("Error").tag(ApplicationLogger.Entry.Level.error as ApplicationLogger.Entry.Level?)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()

                Text("\(filteredLogs.count) / \(applicationLogger.entries.count) logs")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([ApplicationLogger.currentLogFileURL])
                }) {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .help("Show log file in Finder")

                Button(action: { applicationLogger.clear() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Log list
            if filteredLogs.isEmpty {
                VStack {
                    Spacer()
                    if applicationLogger.entries.isEmpty {
                        Text("No logs yet")
                            .font(.headline)
                        Text("Logs will appear here as the app runs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No logs match the current filter")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                    .padding(8)
                }
            }

            // Footer with log file path
            Divider()
            HStack {
                Text(ApplicationLogger.currentLogFileURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(ApplicationLogger.currentLogFileURL.path)

                Spacer()

                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(ApplicationLogger.currentLogFileURL.path, forType: .string)
                }) {
                    Label("Copy Path", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy log file path to clipboard")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .searchable(text: $searchText, prompt: "Search logs")
        .frame(minWidth: 700, minHeight: 400)
    }
}

struct LogEntryRow: View {
    let entry: ApplicationLogger.Entry

    var levelColor: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    var levelIcon: String {
        switch entry.level {
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.formattedTimestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            Image(systemName: levelIcon)
                .foregroundColor(levelColor)
                .font(.caption)

            Text("[\(entry.category)]")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.orange)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }
}