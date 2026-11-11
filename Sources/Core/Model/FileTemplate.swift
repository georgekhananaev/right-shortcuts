import Foundation

/// A kind of file the New File submenu can create.
public struct FileTemplate: Codable, Identifiable, Hashable, Sendable {
    public enum Source: Codable, Hashable, Sendable {
        /// Plain text content, written as UTF-8.
        case text(content: String)
        /// A file shipped in the app bundle's Templates folder.
        case bundled(resource: String)
        /// A file the user picked, stored in the shared container.
        case file(path: String)
    }

    public var id: String
    public var name: String
    public var fileExtension: String
    /// The file name without extension, like "Untitled".
    public var baseName: String
    public var symbol: String
    public var isEnabled: Bool
    public var source: Source
    public var makesExecutable: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        fileExtension: String,
        baseName: String = "Untitled",
        symbol: String = "doc",
        isEnabled: Bool = true,
        source: Source,
        makesExecutable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.baseName = baseName
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.source = source
        self.makesExecutable = makesExecutable
    }

    public var isBuiltin: Bool { id.hasPrefix(Self.builtinPrefix) }

    public var isTextBased: Bool {
        if case .text = source { true } else { false }
    }

    public var defaultFileName: String {
        FileNaming.fileName(base: baseName, pathExtension: fileExtension)
    }

    static let builtinPrefix = "builtin."
}

extension FileTemplate {
    /// Templates that ship with the app, in their default order.
    public static let builtins: [FileTemplate] = [
        builtin("text", "Text Document", "txt", symbol: "doc.text", content: ""),
        builtin("markdown", "Markdown", "md", symbol: "number", content: "# Untitled\n\n"),
        builtin("rtf", "Rich Text Document", "rtf", symbol: "doc.richtext", content: richTextContent),
        builtin("word", "Word Document", "docx", symbol: "doc.text.fill", resource: "Blank.docx"),
        builtin("excel", "Excel Spreadsheet", "xlsx", symbol: "tablecells", resource: "Blank.xlsx"),
        builtin("powerpoint", "PowerPoint Presentation", "pptx", symbol: "play.rectangle", resource: "Blank.pptx"),
        builtin("json", "JSON", "json", symbol: "curlybraces", content: "{\n  \n}\n"),
        builtin("shell", "Shell Script", "sh", symbol: "terminal", content: "#!/bin/zsh\n\n", executable: true),
        builtin("python", "Python Script", "py", symbol: "chevron.left.forwardslash.chevron.right",
                content: "#!/usr/bin/env python3\n\n", enabled: false),
        builtin("html", "HTML Page", "html", symbol: "globe", content: htmlContent, enabled: false),
        builtin("css", "CSS Stylesheet", "css", symbol: "paintbrush", content: "", enabled: false),
        builtin("javascript", "JavaScript", "js", symbol: "curlybraces.square", content: "", enabled: false),
        builtin("typescript", "TypeScript", "ts", symbol: "curlybraces.square.fill", content: "", enabled: false),
        builtin("swift", "Swift", "swift", symbol: "swift", content: "import Foundation\n\n", enabled: false),
        builtin("yaml", "YAML", "yaml", symbol: "list.bullet.indent", content: "", enabled: false),
        builtin("xml", "XML", "xml", symbol: "chevron.left.slash.chevron.right",
                content: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n", enabled: false),
        builtin("csv", "CSV", "csv", symbol: "tablecells.badge.ellipsis", content: "", enabled: false),
    ]

    private static func builtin(
        _ key: String,
        _ name: String,
        _ fileExtension: String,
        symbol: String,
        content: String? = nil,
        resource: String? = nil,
        executable: Bool = false,
        enabled: Bool = true
    ) -> FileTemplate {
        let source: Source = resource.map { .bundled(resource: $0) } ?? .text(content: content ?? "")
        return FileTemplate(
            id: builtinPrefix + key,
            name: name,
            fileExtension: fileExtension,
            symbol: symbol,
            isEnabled: enabled,
            source: source,
            makesExecutable: executable
        )
    }

    private static let richTextContent = #"""
    {\rtf1\ansi\ansicpg1252\cocoartf2822
    {\fonttbl\f0\fswiss\fcharset0 Helvetica;}
    \pard\tx720\pardirnatural\partightenfactor0
    \f0\fs26 \cf0 }
    """#

    private static let htmlContent = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Untitled</title>
    </head>
    <body>

    </body>
    </html>

    """
}
