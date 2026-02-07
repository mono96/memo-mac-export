import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case text = "テキスト (.txt)"
    case markdown = "Markdown (.md)"
    case json = "JSONバンドル (.json)"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .json: return "json"
        }
    }
}
