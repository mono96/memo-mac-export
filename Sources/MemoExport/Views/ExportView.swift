import SwiftUI

/// JSONバンドル エクスポート画面（上級者向けメニューから開く）
struct ExportView: View {
    @State private var notes: [NoteItem] = []
    @State private var folders: [String] = []
    @State private var selectedFolder: String = "すべて"
    @State private var isLoading = false
    @State private var isExporting = false
    @State private var statusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedNotes: Set<String> = []
    @State private var exportProgress: (current: Int, total: Int) = (0, 0)

    private let notesService = sharedNotesService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: loadNotes) {
                    Label("メモを読み込む", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading || isExporting)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("読み込み中... (\(notes.count)件)")
                        .foregroundStyle(.secondary)
                }

                Text("\(filteredNotes.count)件のメモ")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("フォルダ:")
                        Picker("", selection: $selectedFolder) {
                            Text("すべて").tag("すべて")
                            ForEach(folders, id: \.self) { folder in
                                Text(folder).tag(folder)
                            }
                        }
                        .frame(maxWidth: 200)
                    }

                    HStack {
                        Button("すべて選択") {
                            selectedNotes = Set(filteredNotes.map(\.id))
                        }
                        Button("選択解除") {
                            selectedNotes.removeAll()
                        }
                        Spacer()
                        Text("\(selectedNotes.count)件選択中")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    List(filteredNotes, selection: $selectedNotes) { note in
                        HStack {
                            Image(systemName: selectedNotes.contains(note.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedNotes.contains(note.id) ? .blue : .secondary)
                                .onTapGesture {
                                    if selectedNotes.contains(note.id) {
                                        selectedNotes.remove(note.id)
                                    } else {
                                        selectedNotes.insert(note.id)
                                    }
                                }
                            VStack(alignment: .leading) {
                                Text(note.title)
                                    .lineLimit(1)
                                if !note.folder.isEmpty {
                                    Text(note.folder)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(note.id)
                    }
                }
                .frame(minWidth: 280)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text("JSONバンドル エクスポート")
                        .font(.headline)

                    Text("メモのメタデータ（作成日、更新日、フォルダ、HTML本文）を含むJSONファイルとして書き出します。「インポート」機能で復元できます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if isExporting {
                        VStack(spacing: 4) {
                            ProgressView(
                                value: Double(exportProgress.current),
                                total: Double(max(exportProgress.total, 1))
                            )
                            Text("本文を取得中... \(exportProgress.current)/\(exportProgress.total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .foregroundStyle(.green)
                            .font(.callout)
                    }

                    Button(action: performExport) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(
                                isExporting ? "エクスポート中..." : "JSONバンドルを保存",
                                systemImage: "square.and.arrow.down"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedNotes.isEmpty || isExporting)
                }
                .frame(width: 240)
                .padding(.vertical)
            }
            .padding(.horizontal)
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            loadNotes()
        }
    }

    private var filteredNotes: [NoteItem] {
        if selectedFolder == "すべて" { return notes }
        return notes.filter { $0.folder == selectedFolder }
    }

    private func loadNotes() {
        isLoading = true
        statusMessage = ""
        notes = []
        folders = []
        selectedNotes = []

        Task {
            do {
                try await notesService.fetchNotesMetadataIncremental(
                    onFolders: { fetchedFolders in
                        Task { @MainActor in
                            folders = fetchedFolders
                        }
                    },
                    onFolderLoaded: { folderNotes, _, _ in
                        Task { @MainActor in
                            notes.append(contentsOf: folderNotes)
                            selectedNotes.formUnion(folderNotes.map(\.id))
                        }
                    }
                )
                await MainActor.run {
                    isLoading = false
                }
            } catch is CancellationError {
                // ignored
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }

    private func performExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "JSONバンドルの保存先フォルダを選択してください"

        guard panel.runModal() == .OK, let outputDir = panel.url else { return }
        guard !selectedNotes.isEmpty else { return }

        isExporting = true
        statusMessage = ""
        exportProgress = (0, selectedNotes.count)

        Task {
            do {
                let fullNotes = try await notesService.fetchBodiesForExport(
                    selectedIds: selectedNotes,
                    folderNames: folders,
                    onProgress: { current, total in
                        Task { @MainActor in
                            exportProgress = (current, total)
                        }
                    }
                )

                let count = try ExportService.export(
                    notes: fullNotes,
                    format: .json,
                    to: outputDir,
                    preserveFolders: false
                )
                await MainActor.run {
                    statusMessage = "\(count)件のメモをJSONバンドルに保存しました"
                    isExporting = false
                }
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
