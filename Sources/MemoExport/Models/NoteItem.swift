import Foundation

struct NoteItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var htmlBody: String
    var plainText: String
    var folder: String
    var createdAt: Date
    var modifiedAt: Date

    var safeFileName: String {
        let name = title.isEmpty ? "Untitled" : title
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let safe = name.components(separatedBy: invalidChars).joined(separator: "_")
        let trimmed = String(safe.prefix(100))
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

struct NotesBundle: Codable {
    var version: String = "1.0"
    var exportDate: Date
    var appVersion: String = "1.0.0"
    var notes: [NoteItem]
}
