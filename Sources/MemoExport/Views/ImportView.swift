import SwiftUI

struct ImportView: View {
    @State private var selectedFile: URL?
    @State private var bundle: NotesBundle?
    @State private var targetFolder = ""
    @State private var isImporting = false
    @State private var progress: (current: Int, total: Int) = (0, 0)
    @State private var statusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private let notesService = sharedNotesService

    var body: some View {
        VStack(spacing: 0) {
            // File selection toolbar
            HStack {
                Button(action: selectFile) {
                    Label("JSONファイルを選択", systemImage: "doc.badge.plus")
                }

                if let url = selectedFile {
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding()

            Divider()

            if let bundle = bundle {
                HStack(spacing: 16) {
                    // Left: Note preview list
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("プレビュー")
                                .font(.headline)
                            Spacer()
                            Text("\(bundle.notes.count)件のメモ")
                                .foregroundStyle(.secondary)
                        }

                        Text("エクスポート日: \(bundle.exportDate, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        List(bundle.notes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                HStack {
                                    Label(note.folder, systemImage: "folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(note.modifiedAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(note.plainText.isEmpty
                                     ? HTMLConverter.toPlainText(note.htmlBody)
                                     : note.plainText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(minWidth: 300)

                    Divider()

                    // Right: Import settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("インポート設定")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("インポート先フォルダ:")
                            TextField("元のフォルダを使用", text: $targetFolder)
                                .textFieldStyle(.roundedBorder)
                            Text("空欄の場合、元のフォルダ名を使用します")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("バンドル情報")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            LabeledContent("バージョン", value: bundle.version)
                            LabeledContent("メモ数", value: "\(bundle.notes.count)件")
                            let folderSet = Set(bundle.notes.map(\.folder))
                            LabeledContent("フォルダ数", value: "\(folderSet.count)件")
                        }

                        Spacer()

                        // Progress
                        if isImporting {
                            VStack(spacing: 4) {
                                ProgressView(
                                    value: Double(progress.current),
                                    total: Double(max(progress.total, 1))
                                )
                                Text("\(progress.current) / \(progress.total)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .foregroundStyle(.green)
                                .font(.callout)
                        }

                        Button(action: performImport) {
                            HStack {
                                if isImporting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isImporting ? "インポート中..." : "インポート")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isImporting)
                    }
                    .frame(width: 240)
                    .padding(.vertical)
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("JSONバンドルファイルを選択してください")
                        .foregroundStyle(.secondary)
                    Text("エクスポートで作成したJSONファイルを読み込みます")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "インポートするJSONバンドルファイルを選択してください"

        if panel.runModal() == .OK, let url = panel.url {
            selectedFile = url
            loadBundle(from: url)
        }
    }

    private func loadBundle(from url: URL) {
        do {
            bundle = try ImportService.loadBundle(from: url)
            statusMessage = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            bundle = nil
        }
    }

    private func performImport() {
        guard let bundle = bundle else { return }
        isImporting = true
        statusMessage = ""
        progress = (0, bundle.notes.count)

        Task {
            do {
                let count = try await ImportService.importNotes(
                    bundle: bundle,
                    targetFolder: targetFolder,
                    notesService: notesService,
                    onProgress: { current, total in
                        Task { @MainActor in
                            progress = (current, total)
                        }
                    }
                )
                await MainActor.run {
                    statusMessage = "\(count)件のメモをインポートしました"
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isImporting = false
                }
            }
        }
    }
}
