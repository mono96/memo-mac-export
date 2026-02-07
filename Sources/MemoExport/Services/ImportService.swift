import Foundation

struct ImportService {

    enum ImportError: LocalizedError {
        case fileNotFound(String)
        case invalidFormat(String)
        case importFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "ファイルが見つかりません: \(path)"
            case .invalidFormat(let msg):
                return "無効なファイル形式: \(msg)"
            case .importFailed(let msg):
                return "インポート失敗: \(msg)"
            }
        }
    }

    static func loadBundle(from url: URL) throws -> NotesBundle {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.fileNotFound(url.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileNotFound(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let bundle = try decoder.decode(NotesBundle.self, from: data)
            return bundle
        } catch {
            throw ImportError.invalidFormat(error.localizedDescription)
        }
    }

    static func importNotes(
        bundle: NotesBundle,
        targetFolder: String,
        notesService: NotesService,
        onProgress: @escaping (Int, Int) -> Void
    ) async throws -> Int {
        var imported = 0
        let total = bundle.notes.count

        for (index, note) in bundle.notes.enumerated() {
            let folder = targetFolder.isEmpty ? note.folder : targetFolder
            let effectiveFolder = folder.isEmpty ? "インポート済み" : folder

            let body = note.htmlBody.isEmpty
                ? "<div>\(escapeHTML(note.plainText))</div>"
                : note.htmlBody

            do {
                try await notesService.createNote(
                    title: note.title,
                    body: body,
                    folderName: effectiveFolder
                )
                imported += 1
            } catch {
                throw ImportError.importFailed(
                    "「\(note.title)」のインポートに失敗: \(error.localizedDescription)"
                )
            }

            onProgress(index + 1, total)
        }

        return imported
    }

    private static func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
