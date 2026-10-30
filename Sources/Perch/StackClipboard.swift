import AppKit
import PerchCore

@MainActor
enum StackClipboard {
    static func copy(_ stack: PRStack, name: String, to pasteboard: NSPasteboard) throws {
        let heading = "PR Stack for \(name)\n"
        let text = NSMutableAttributedString(
            string: heading,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        var plainText = heading
        for request in stack.pullRequests {
            text.append(NSAttributedString(string: "\n"))
            text.append(NSAttributedString(string: request.title, attributes: [
                .font: font,
                .link: request.url,
            ]))
            plainText.append("\n")
            plainText.append(request.title)
            plainText.append(" — ")
            plainText.append(request.url.absoluteString)
        }

        let range = NSRange(location: 0, length: text.length)
        let html = try text.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ])
        let rtf = try text.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf,
        ])
        let item = NSPasteboardItem()
        item.setData(html, forType: .html)
        item.setData(rtf, forType: .rtf)
        item.setString(plainText, forType: .string)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw NSError(domain: "Perch", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not copy the stack to the clipboard.",
            ])
        }
    }
}
