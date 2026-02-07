import SwiftUI

struct NoteDetailView: View {
    let note: NoteItem

    @State private var displayMode: DisplayMode = .plainText

    enum DisplayMode: String, CaseIterable {
        case plainText = "テキスト"
        case markdown = "Markdown"
        case html = "HTML"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 16) {
                    Label(note.folder, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("作成: \(note.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("更新: \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("表示", selection: $displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                Text(displayContent)
                    .textSelection(.enabled)
                    .font(displayMode == .html ? .system(.body, design: .monospaced) : .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private var displayContent: String {
        switch displayMode {
        case .plainText:
            return note.plainText.isEmpty
                ? HTMLConverter.toPlainText(note.htmlBody)
                : note.plainText
        case .markdown:
            return HTMLConverter.toMarkdown(note.htmlBody)
        case .html:
            return note.htmlBody
        }
    }
}
