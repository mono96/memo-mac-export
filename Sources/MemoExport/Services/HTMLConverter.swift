import Foundation

struct HTMLConverter {

    static func toPlainText(_ html: String) -> String {
        var text = html
        // Replace <br> variants with newline
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        // Replace </p>, </div>, </li> with newline
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        // Replace </tr> with newline
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)
        // Strip all HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode HTML entities
        text = decodeHTMLEntities(text)
        // Clean up multiple blank lines
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func toMarkdown(_ html: String) -> String {
        var md = html

        // Headers
        for level in (1...6).reversed() {
            let tag = "h\(level)"
            let prefix = String(repeating: "#", count: level)
            let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
            md = md.replacingOccurrences(
                of: pattern,
                with: "\n\(prefix) $1\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Bold
        md = md.replacingOccurrences(
            of: "<(b|strong)[^>]*>(.*?)</(b|strong)>",
            with: "**$2**",
            options: [.regularExpression, .caseInsensitive]
        )

        // Italic
        md = md.replacingOccurrences(
            of: "<(i|em)[^>]*>(.*?)</(i|em)>",
            with: "*$2*",
            options: [.regularExpression, .caseInsensitive]
        )

        // Underline (no direct MD equivalent, use emphasis)
        md = md.replacingOccurrences(
            of: "<u[^>]*>(.*?)</u>",
            with: "_$1_",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strikethrough
        md = md.replacingOccurrences(
            of: "<(s|strike|del)[^>]*>(.*?)</(s|strike|del)>",
            with: "~~$2~~",
            options: [.regularExpression, .caseInsensitive]
        )

        // Links
        md = md.replacingOccurrences(
            of: "<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>",
            with: "[$2]($1)",
            options: [.regularExpression, .caseInsensitive]
        )

        // Images
        md = md.replacingOccurrences(
            of: "<img[^>]*src=\"([^\"]*)\"[^>]*alt=\"([^\"]*)\"[^>]*/?>",
            with: "![$2]($1)",
            options: [.regularExpression, .caseInsensitive]
        )
        md = md.replacingOccurrences(
            of: "<img[^>]*src=\"([^\"]*)\"[^>]*/?>",
            with: "![]($1)",
            options: [.regularExpression, .caseInsensitive]
        )

        // Unordered list items
        md = md.replacingOccurrences(
            of: "<li[^>]*>(.*?)</li>",
            with: "- $1",
            options: [.regularExpression, .caseInsensitive]
        )

        // Ordered list - simplify to unordered for now
        md = md.replacingOccurrences(
            of: "</?[ou]l[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Blockquote
        md = md.replacingOccurrences(
            of: "<blockquote[^>]*>(.*?)</blockquote>",
            with: "\n> $1\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Code blocks
        md = md.replacingOccurrences(
            of: "<pre[^>]*><code[^>]*>(.*?)</code></pre>",
            with: "\n```\n$1\n```\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Inline code
        md = md.replacingOccurrences(
            of: "<code[^>]*>(.*?)</code>",
            with: "`$1`",
            options: [.regularExpression, .caseInsensitive]
        )

        // Horizontal rule
        md = md.replacingOccurrences(
            of: "<hr[^>]*/?>",
            with: "\n---\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Line breaks
        md = md.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "  \n",
            options: .regularExpression
        )

        // Paragraphs and divs
        md = md.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        md = md.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        md = md.replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)

        // Strip remaining HTML tags
        md = md.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        md = decodeHTMLEntities(md)

        // Clean up whitespace
        md = md.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&ndash;", "–"),
            ("&mdash;", "—"),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
            ("&hellip;", "…"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let codeStr = nsString.substring(with: match.range(at: 1))
                if let code = UInt32(codeStr), let scalar = Unicode.Scalar(code) {
                    result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
                }
            }
        }
        return result
    }
}
