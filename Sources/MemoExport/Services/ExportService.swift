import Foundation

struct ExportService {

    enum ExportError: LocalizedError {
        case directoryCreationFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let path):
                return "フォルダの作成に失敗しました: \(path)"
            case .writeFailed(let msg):
                return "ファイルの書き込みに失敗しました: \(msg)"
            }
        }
    }

    /// Export result with count and per-note errors.
    struct Result {
        let count: Int
        let errors: [String]
    }

    static func export(
        notes: [NoteItem],
        format: ExportFormat,
        to directory: URL,
        preserveFolders: Bool
    ) throws -> Int {
        let result = exportWithErrors(notes: notes, format: format, to: directory, preserveFolders: preserveFolders)
        return result.count
    }

    /// Export notes, skipping individual failures and collecting errors.
    static func exportWithErrors(
        notes: [NoteItem],
        format: ExportFormat,
        to directory: URL,
        preserveFolders: Bool
    ) -> Result {
        let fm = FileManager.default
        var count = 0
        var errors: [String] = []

        switch format {
        case .json:
            do {
                let c = try exportJSON(notes: notes, to: directory)
                return Result(count: c, errors: [])
            } catch {
                return Result(count: 0, errors: ["JSON書き出しエラー: \(error.localizedDescription)"])
            }
        case .text, .markdown:
            for note in notes {
                let subDir: URL
                if preserveFolders && !note.folder.isEmpty {
                    subDir = directory.appendingPathComponent(note.folder)
                } else {
                    subDir = directory
                }

                if !fm.fileExists(atPath: subDir.path) {
                    do {
                        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
                    } catch {
                        errors.append("「\(note.title)」: フォルダ作成失敗 - \(error.localizedDescription)")
                        continue
                    }
                }

                let content: String
                switch format {
                case .text:
                    content = note.plainText.isEmpty
                        ? HTMLConverter.toPlainText(note.htmlBody)
                        : note.plainText
                case .markdown:
                    content = HTMLConverter.toMarkdown(note.htmlBody)
                default:
                    content = ""
                }

                let fileName = uniqueFileName(
                    base: note.safeFileName,
                    ext: format.fileExtension,
                    in: subDir
                )
                let filePath = subDir.appendingPathComponent(fileName)

                do {
                    try content.write(to: filePath, atomically: true, encoding: .utf8)
                    count += 1
                } catch {
                    errors.append("「\(note.title)」: 書き込み失敗 - \(error.localizedDescription)")
                }
            }
            return Result(count: count, errors: errors)
        }
    }

    private static func exportJSON(notes: [NoteItem], to directory: URL) throws -> Int {
        let bundle = NotesBundle(
            exportDate: Date(),
            notes: notes
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(bundle)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }

        let fileName = "MemoExport_\(dateString()).json"
        let filePath = directory.appendingPathComponent(fileName)

        do {
            try data.write(to: filePath, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }

        return notes.count
    }

    private static func uniqueFileName(base: String, ext: String, in directory: URL) -> String {
        let fm = FileManager.default
        var name = "\(base).\(ext)"
        var counter = 1

        while fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(base)_\(counter).\(ext)"
            counter += 1
        }

        return name
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
