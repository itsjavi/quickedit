import AppKit

/// Comment syntax of the current language, for Toggle Comment.
struct CommentStyle: Equatable {
    var line: String?
    var block: (open: String, close: String)?

    static let none = CommentStyle()

    static func == (lhs: CommentStyle, rhs: CommentStyle) -> Bool {
        lhs.line == rhs.line && lhs.block?.open == rhs.block?.open && lhs.block?.close == rhs.block?.close
    }
}

/// Line commands (Edit › Lines, Toggle Comment). Each is one undoable change that keeps line endings as they are.
extension EditorTextView {
    private struct Line {
        var content: String
        var terminator: String
    }

    private static let lineCommands: Set<Selector> = [
        #selector(moveLineUp(_:)), #selector(moveLineDown(_:)), #selector(duplicateLine(_:)), #selector(deleteLine(_:)),
        #selector(joinLines(_:)), #selector(sortLines(_:)), #selector(toggleComment(_:)),
        #selector(indentSelectedLines(_:)), #selector(outdentSelectedLines(_:)),
    ]

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let action = menuItem.action, Self.lineCommands.contains(action) {
            if action == #selector(toggleComment(_:)) { return isEditable && (commentStyle.line != nil || commentStyle.block != nil) }
            return isEditable
        }
        return super.validateMenuItem(menuItem)
    }

    /// The selected lines' range including their line endings, and each line split into content and ending.
    private func selectedBlock() -> (range: NSRange, lines: [Line]) {
        let text = string as NSString
        let affected = lines(in: selectedRange())
        let range = NSRange(location: affected.first?.full.location ?? 0, length: (affected.last.map { NSMaxRange($0.full) } ?? 0) - (affected.first?.full.location ?? 0))
        let parts = affected.map { line in
            Line(content: text.substring(with: line.content),
                 terminator: text.substring(with: NSRange(location: NSMaxRange(line.content), length: NSMaxRange(line.full) - NSMaxRange(line.content))))
        }
        return (range, parts)
    }

    private func lineAt(_ location: Int) -> (range: NSRange, line: Line) {
        let text = string as NSString
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return (NSRange(location: start, length: end - start),
                Line(content: text.substring(with: NSRange(location: start, length: contentsEnd - start)),
                     terminator: text.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))))
    }

    /// Reorders line contents while every line ending stays in its position, so a last line without one stays last.
    private func joinKeepingTerminators(_ contents: [String], _ terminators: [String]) -> String {
        zip(contents, terminators).map { $0 + $1 }.joined()
    }

    private func commit(_ range: NSRange, _ replacement: String, actionName: String, select selection: NSRange) {
        replace(range, with: replacement)
        undoManager?.setActionName(actionName)
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    @objc func moveLineUp(_ sender: Any?) {
        let block = selectedBlock()
        guard block.range.location > 0 else { return }
        let previous = lineAt(block.range.location - 1)
        let region = NSRange(location: previous.range.location, length: NSMaxRange(block.range) - previous.range.location)
        let all = [previous.line] + block.lines
        let contents = block.lines.map(\.content) + [previous.line.content]
        let replacement = joinKeepingTerminators(contents, all.map(\.terminator))
        let selection = selectedRange()
        let shift = (previous.line.content as NSString).length + (previous.line.terminator as NSString).length
        commit(region, replacement, actionName: "Move Line Up", select: NSRange(location: selection.location - shift, length: selection.length))
    }

    @objc func moveLineDown(_ sender: Any?) {
        let block = selectedBlock()
        let text = string as NSString
        // Nothing below, or only the empty line after a final line break.
        guard NSMaxRange(block.range) < text.length, block.lines.last?.terminator.isEmpty == false else { return }
        let next = lineAt(NSMaxRange(block.range))
        let region = NSRange(location: block.range.location, length: NSMaxRange(next.range) - block.range.location)
        let all = block.lines + [next.line]
        let contents = [next.line.content] + block.lines.map(\.content)
        let replacement = joinKeepingTerminators(contents, all.map(\.terminator))
        let selection = selectedRange()
        let shift = (next.line.content as NSString).length + (all[0].terminator as NSString).length
        commit(region, replacement, actionName: "Move Line Down", select: NSRange(location: selection.location + shift, length: selection.length))
    }

    @objc func duplicateLine(_ sender: Any?) {
        let block = selectedBlock()
        let selection = selectedRange()
        let blockText = (string as NSString).substring(with: block.range)
        if block.lines.last?.terminator.isEmpty == false {
            commit(NSRange(location: NSMaxRange(block.range), length: 0), blockText, actionName: "Duplicate Line",
                   select: NSRange(location: selection.location + block.range.length, length: selection.length))
        } else {
            // The last line has no line ending: add one between the copies.
            let insertion = lineEnding.rawValue + blockText
            commit(NSRange(location: NSMaxRange(block.range), length: 0), insertion, actionName: "Duplicate Line",
                   select: NSRange(location: selection.location + (insertion as NSString).length, length: selection.length))
        }
    }

    @objc func deleteLine(_ sender: Any?) {
        let block = selectedBlock()
        var range = block.range
        if block.lines.last?.terminator.isEmpty != false, range.location > 0 {
            // Deleting the last line also removes the line ending before it.
            let previous = lineAt(range.location - 1)
            let terminatorLength = (previous.line.terminator as NSString).length
            range = NSRange(location: range.location - terminatorLength, length: range.length + terminatorLength)
        }
        commit(range, "", actionName: "Delete Line", select: NSRange(location: min(range.location, (string as NSString).length - range.length), length: 0))
    }

    @objc func joinLines(_ sender: Any?) {
        var block = selectedBlock()
        if block.lines.count == 1 {
            // Join the caret's line with the next one.
            guard NSMaxRange(block.range) < (string as NSString).length else { return }
            let next = lineAt(NSMaxRange(block.range))
            block = (NSRange(location: block.range.location, length: NSMaxRange(next.range) - block.range.location), block.lines + [next.line])
        }
        var joined = block.lines[0].content
        for line in block.lines.dropFirst() {
            let trimmed = line.content.drop { $0 == " " || $0 == "\t" }
            if trimmed.isEmpty { continue }
            joined = joined.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression) + " " + trimmed
        }
        let replacement = joined + (block.lines.last?.terminator ?? "")
        commit(block.range, replacement, actionName: "Join Lines",
               select: NSRange(location: block.range.location + (joined as NSString).length, length: 0))
    }

    @objc func sortLines(_ sender: Any?) {
        let block = selectedBlock()
        guard block.lines.count > 1 else { return }
        let sorted = block.lines.map(\.content).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let replacement = joinKeepingTerminators(sorted, block.lines.map(\.terminator))
        commit(block.range, replacement, actionName: "Sort Lines",
               select: NSRange(location: block.range.location, length: (replacement as NSString).length - (block.lines.last!.terminator as NSString).length))
    }

    @objc func toggleComment(_ sender: Any?) {
        if let token = commentStyle.line {
            toggleLineComment(token)
        } else if let block = commentStyle.block {
            toggleBlockComment(open: block.open, close: block.close)
        }
    }

    private func toggleLineComment(_ token: String) {
        let block = selectedBlock()
        let nonEmpty = block.lines.filter { !$0.content.allSatisfy { $0 == " " || $0 == "\t" } }
        guard !nonEmpty.isEmpty else { return }
        let isCommented = nonEmpty.allSatisfy { $0.content.drop { $0 == " " || $0 == "\t" }.hasPrefix(token) }
        // Comment markers line up at the smallest indentation of the selected lines.
        let indent = nonEmpty.map { $0.content.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let contents = block.lines.map { line -> String in
            if line.content.allSatisfy({ $0 == " " || $0 == "\t" }) { return line.content }
            if isCommented {
                let leading = line.content.prefix { $0 == " " || $0 == "\t" }
                var rest = line.content.dropFirst(leading.count).dropFirst(token.count)
                if rest.first == " " { rest = rest.dropFirst() }
                return String(leading + rest)
            }
            let index = line.content.index(line.content.startIndex, offsetBy: indent)
            return String(line.content[..<index]) + token + " " + String(line.content[index...])
        }
        let replacement = joinKeepingTerminators(contents, block.lines.map(\.terminator))
        let selection = selectedRange()
        let delta = (replacement as NSString).length - block.range.length
        let newSelection = block.lines.count == 1 && selection.length == 0
            ? NSRange(location: max(block.range.location, selection.location + delta), length: 0)
            : NSRange(location: block.range.location, length: (replacement as NSString).length - ((block.lines.last?.terminator ?? "") as NSString).length)
        commit(block.range, replacement, actionName: isCommented ? "Uncomment" : "Comment", select: newSelection)
    }

    private func toggleBlockComment(open: String, close: String) {
        var range = selectedRange()
        let text = string as NSString
        if range.length == 0 {
            let line = lineAt(range.location)
            let content = line.line.content
            let leading = content.prefix { $0 == " " || $0 == "\t" }.utf16.count
            range = NSRange(location: line.range.location + leading, length: (content as NSString).length - leading)
        }
        let selected = text.substring(with: range)
        let trimmed = selected.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(open), trimmed.hasSuffix(close), (trimmed as NSString).length >= (open as NSString).length + (close as NSString).length {
            var inner = String(trimmed.dropFirst(open.count).dropLast(close.count))
            if inner.hasPrefix(" ") { inner.removeFirst() }
            if inner.hasSuffix(" ") { inner.removeLast() }
            commit(range, inner, actionName: "Uncomment", select: NSRange(location: range.location, length: (inner as NSString).length))
        } else {
            let wrapped = open + " " + selected + " " + close
            commit(range, wrapped, actionName: "Comment", select: NSRange(location: range.location, length: (wrapped as NSString).length))
        }
    }
}
