import Foundation

struct ParsedBookmarkItem: Equatable {
    var title: String
    var url: URL
    var notes: String?
    var createdAt: Date?
}

struct ParsedBookmarkFolder: Equatable {
    var name: String
    var createdAt: Date?
    var folders: [ParsedBookmarkFolder]
    var bookmarks: [ParsedBookmarkItem]
}

struct ParsedBookmarkDocument: Equatable {
    var folders: [ParsedBookmarkFolder]
    var rootBookmarks: [ParsedBookmarkItem]
}

/// Netscape Bookmark HTML (`NETSCAPE-Bookmark-file-1`) importer and exporter
/// compatible with Google Chrome and Apple Safari bookmark HTML files.
enum BookmarkHTMLCodec {
    static func exportHTML(
        folders: [BookmarkFolder],
        bookmarks: [BookmarkItem],
        now: Date = Date()
    ) -> String {
        let sortedFolders = folders.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.createdAt < $1.createdAt
        }
        let sortedBookmarks = bookmarks.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.createdAt < $1.createdAt
        }

        let validFolderIDs = Set(sortedFolders.map(\.id))
        var childrenByParent: [UUID?: [BookmarkFolder]] = [:]
        for folder in sortedFolders {
            let safeParentID = folder.parentFolderID.flatMap {
                validFolderIDs.contains($0) && $0 != folder.id ? $0 : nil
            }
            childrenByParent[safeParentID, default: []].append(folder)
        }

        var bookmarksByFolder: [UUID?: [BookmarkItem]] = [:]
        for bookmark in sortedBookmarks {
            let safeFolderID = bookmark.folderID.flatMap {
                validFolderIDs.contains($0) ? $0 : nil
            }
            bookmarksByFolder[safeFolderID, default: []].append(bookmark)
        }

        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This is an automatically generated file.",
            "     It will be read and overwritten.",
            "     DO NOT EDIT! -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]

        func appendContents(of parentFolderID: UUID?, indentLevel: Int, visited: inout Set<UUID>) {
            let indent = String(repeating: "    ", count: indentLevel)
            for folder in childrenByParent[parentFolderID] ?? [] {
                guard visited.insert(folder.id).inserted else { continue }
                let ts = Int(folder.createdAt.timeIntervalSince1970)
                lines.append("\(indent)<DT><H3 ADD_DATE=\"\(ts)\" LAST_MODIFIED=\"\(ts)\">\(escapeHTML(folder.name))</H3>")
                lines.append("\(indent)<DL><p>")
                appendContents(of: folder.id, indentLevel: indentLevel + 1, visited: &visited)
                lines.append("\(indent)</DL><p>")
            }

            for bookmark in bookmarksByFolder[parentFolderID] ?? [] {
                let ts = Int(bookmark.createdAt.timeIntervalSince1970)
                lines.append("\(indent)<DT><A HREF=\"\(escapeHTML(bookmark.url.absoluteString))\" ADD_DATE=\"\(ts)\">\(escapeHTML(bookmark.title))</A>")
                if let notes = bookmark.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !notes.isEmpty {
                    lines.append("\(indent)<DD>\(escapeHTML(notes))")
                }
            }
        }

        var visitedFolders = Set<UUID>()
        appendContents(of: nil, indentLevel: 1, visited: &visitedFolders)
        lines.append("</DL><p>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func parseHTML(_ html: String) -> ParsedBookmarkDocument {
        final class FolderNode {
            var name: String
            var createdAt: Date?
            var folders: [FolderNode] = []
            var bookmarks: [ParsedBookmarkItem] = []

            init(name: String, createdAt: Date? = nil) {
                self.name = name
                self.createdAt = createdAt
            }

            func freeze() -> ParsedBookmarkFolder {
                ParsedBookmarkFolder(
                    name: name,
                    createdAt: createdAt,
                    folders: folders.map { $0.freeze() },
                    bookmarks: bookmarks
                )
            }
        }

        let rootNode = FolderNode(name: "")
        // Each stack frame tracks the target folder plus whether an open <DL> belongs to it.
        var stack: [(node: FolderNode, hasExplicitDL: Bool)] = [(rootNode, false)]
        var pendingFolder: FolderNode?
        var lastBookmarkLocation: (node: FolderNode, index: Int)?

        // Matches:
        // 1. <H3 attrs>title</H3>
        // 2. <A attrs>title</A>
        // 3. <DD>notes (until next tag or newline)
        // 4. <DL ...> or </DL>
        let pattern = #"<H3\b([^>]*)>(.*?)</H3>|<A\b([^>]*)>(.*?)</A>|<DD\b[^>]*>([^<\r\n]*)|<(/?)DL\b[^>]*>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return ParsedBookmarkDocument(folders: [], rootBookmarks: [])
        }

        let nsString = html as NSString
        let matches = regex.matches(
            in: html,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )

        for match in matches {
            let h3AttrsRange = match.range(at: 1)
            let h3BodyRange = match.range(at: 2)
            let aAttrsRange = match.range(at: 3)
            let aBodyRange = match.range(at: 4)
            let ddRange = match.range(at: 5)
            let dlSlashRange = match.range(at: 6)

            if h3BodyRange.location != NSNotFound {
                lastBookmarkLocation = nil
                let rawAttrs = h3AttrsRange.location != NSNotFound
                    ? nsString.substring(with: h3AttrsRange)
                    : ""
                let rawName = nsString.substring(with: h3BodyRange)
                let decodedName = stripTagsAndDecodeHTML(rawName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let folderName = decodedName.isEmpty ? "Imported Folder" : decodedName
                let createdAt = attributeValue(named: "ADD_DATE", in: rawAttrs)
                    .flatMap(TimeInterval.init)
                    .map { Date(timeIntervalSince1970: $0) }
                let folder = FolderNode(name: folderName, createdAt: createdAt)
                pendingFolder = folder
                continue
            }

            if aBodyRange.location != NSNotFound {
                pendingFolder = nil
                let rawAttrs = aAttrsRange.location != NSNotFound
                    ? nsString.substring(with: aAttrsRange)
                    : ""
                guard let rawHref = attributeValue(named: "HREF", in: rawAttrs) else {
                    lastBookmarkLocation = nil
                    continue
                }
                let decodedHref = decodeHTMLEntities(rawHref)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: decodedHref), WebAppURL.isSafe(url) else {
                    lastBookmarkLocation = nil
                    continue
                }
                let rawTitle = nsString.substring(with: aBodyRange)
                let decodedTitle = stripTagsAndDecodeHTML(rawTitle)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = decodedTitle.isEmpty
                    ? WebAppURL.defaultDisplayName(for: url)
                    : decodedTitle
                let createdAt = attributeValue(named: "ADD_DATE", in: rawAttrs)
                    .flatMap(TimeInterval.init)
                    .map { Date(timeIntervalSince1970: $0) }
                let targetNode = stack.last?.node ?? rootNode
                targetNode.bookmarks.append(
                    ParsedBookmarkItem(
                        title: title,
                        url: url,
                        notes: nil,
                        createdAt: createdAt
                    )
                )
                lastBookmarkLocation = (targetNode, targetNode.bookmarks.count - 1)
                continue
            }

            if ddRange.location != NSNotFound {
                if let loc = lastBookmarkLocation {
                    let rawNotes = nsString.substring(with: ddRange)
                    let decoded = decodeHTMLEntities(rawNotes)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !decoded.isEmpty {
                        loc.node.bookmarks[loc.index].notes = decoded
                    }
                }
                continue
            }

            if dlSlashRange.location != NSNotFound {
                let isClosing = nsString.substring(with: dlSlashRange) == "/"
                if isClosing {
                    pendingFolder = nil
                    lastBookmarkLocation = nil
                    if stack.count > 1 {
                        stack.removeLast()
                    } else if stack.count == 1 && stack[0].hasExplicitDL {
                        stack[0].hasExplicitDL = false
                    }
                } else {
                    lastBookmarkLocation = nil
                    if let folder = pendingFolder {
                        pendingFolder = nil
                        (stack.last?.node ?? rootNode).folders.append(folder)
                        stack.append((folder, true))
                    } else if stack.count == 1 && !stack[0].hasExplicitDL {
                        stack[0].hasExplicitDL = true
                    } else {
                        // Nested anonymous <DL> inherits the current node.
                        let current = stack.last?.node ?? rootNode
                        stack.append((current, true))
                    }
                }
            }
        }

        // Handle rare edge case where an <H3> had no following <DL> block.
        if let trailing = pendingFolder {
            rootNode.folders.append(trailing)
        }

        return ParsedBookmarkDocument(
            folders: rootNode.folders.map { $0.freeze() },
            rootBookmarks: rootNode.bookmarks
        )
    }

    private static func escapeHTML(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            default: result.append(ch)
            }
        }
        return result
    }

    private static func stripTagsAndDecodeHTML(_ text: String) -> String {
        let noTags = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return decodeHTMLEntities(noTags)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        output.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&",
               let semicolon = text[index...].firstIndex(of: ";"),
               text.distance(from: index, to: semicolon) <= 12 {
                let entity = String(text[text.index(after: index)..<semicolon])
                if let replacement = resolveEntity(entity) {
                    output.append(replacement)
                    index = text.index(after: semicolon)
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }

    private static func resolveEntity(_ entity: String) -> Character? {
        switch entity.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39", "#039": return "'"
        case "nbsp": return " "
        default:
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                if let code = UInt32(entity.dropFirst(2), radix: 16),
                   let scalar = UnicodeScalar(code) {
                    return Character(scalar)
                }
            } else if entity.hasPrefix("#") {
                if let code = UInt32(entity.dropFirst(1), radix: 10),
                   let scalar = UnicodeScalar(code) {
                    return Character(scalar)
                }
            }
            return nil
        }
    }

    private static func attributeValue(named name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?i)\b"# + escapedName + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let ns = attributes as NSString
        guard let match = regex.firstMatch(
            in: attributes,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        ) else {
            return nil
        }
        for group in 1...3 {
            let range = match.range(at: group)
            if range.location != NSNotFound {
                return ns.substring(with: range)
            }
        }
        return nil
    }
}
