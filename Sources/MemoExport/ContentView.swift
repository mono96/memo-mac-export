import SwiftUI

struct ContentView: View {
    @State private var selectedFormat: ExportFormat = .text
    @State private var preserveFolders = true
    @State private var isExporting = false
    @State private var exportProgress: (current: Int, total: Int) = (0, 0)
    @State private var folderStatus = ""
    @State private var statusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private let notesService = sharedNotesService

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("MemoExport")
                .font(.title2)
                .fontWeight(.bold)

            Text("Apple メモの全メモをエクスポート")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            // Format selection
            VStack(alignment: .leading, spacing: 12) {
                Picker("形式:", selection: $selectedFormat) {
                    Text("テキスト (.txt)").tag(ExportFormat.text)
                    Text("Markdown (.md)").tag(ExportFormat.markdown)
                }
                .pickerStyle(.radioGroup)

                Toggle("フォルダ構造を保持", isOn: $preserveFolders)
            }
            .padding(.horizontal, 60)

            Spacer()

            // Progress
            if isExporting {
                VStack(spacing: 6) {
                    ProgressView(
                        value: Double(exportProgress.current),
                        total: Double(max(exportProgress.total, 1))
                    )
                    if !folderStatus.isEmpty {
                        Text(folderStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("エクスポート中... \(exportProgress.current)/\(exportProgress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 60)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusMessage.contains("スキップ") ? .orange : .green)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            // Export button
            Button(action: performExport) {
                Label(
                    isExporting ? "エクスポート中..." : "エクスポート",
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isExporting)
            .padding(.horizontal, 60)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 400, minHeight: 320)
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func performExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "保存先フォルダを選択してください"

        guard panel.runModal() == .OK, let outputDir = panel.url else { return }

        isExporting = true
        statusMessage = ""
        folderStatus = ""
        exportProgress = (0, 0)

        let format = selectedFormat
        let preserve = preserveFolders

        Task {
            do {
                let writeErrors = ErrorCollector()

                let result = try await notesService.exportAllNotes(
                    writer: { notes in
                        let writeResult = ExportService.exportWithErrors(
                            notes: notes,
                            format: format,
                            to: outputDir,
                            preserveFolders: preserve
                        )
                        writeErrors.append(writeResult.errors)
                        return writeResult.count
                    },
                    onProgress: { current, total in
                        Task { @MainActor in
                            exportProgress = (current, total)
                        }
                    },
                    onStatus: { status in
                        Task { @MainActor in
                            folderStatus = status
                        }
                    }
                )

                // Combine errors from NotesService and ExportService
                let combinedErrors = result.errors + writeErrors.all
                let skipped = result.total - result.written

                // Write error log if there are any errors
                if !combinedErrors.isEmpty {
                    let logContent = "MemoExport エラーログ (\(ISO8601DateFormatter().string(from: Date())))\n"
                        + "合計: \(result.total)件  エクスポート: \(result.written)件  スキップ: \(skipped)件\n"
                        + String(repeating: "─", count: 60) + "\n"
                        + combinedErrors.joined(separator: "\n")
                        + "\n"
                    let logPath = outputDir.appendingPathComponent("MemoExport_errors.log")
                    try? logContent.write(to: logPath, atomically: true, encoding: .utf8)
                }

                await MainActor.run {
                    if combinedErrors.isEmpty {
                        statusMessage = "\(result.written)件のメモをエクスポートしました"
                    } else {
                        statusMessage = "\(result.written)件エクスポート、\(skipped)件スキップ\n（エラーログ: MemoExport_errors.log）"
                    }
                    isExporting = false
                }
            } catch is CancellationError {
                // ignored
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isExporting = false
                }
            }
        }
    }
}

/// Thread-safe error collector for use in @Sendable closures.
private final class ErrorCollector: @unchecked Sendable {
    private var errors: [String] = []
    private let lock = NSLock()

    func append(_ newErrors: [String]) {
        guard !newErrors.isEmpty else { return }
        lock.lock()
        errors.append(contentsOf: newErrors)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return errors
    }
}
