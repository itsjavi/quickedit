import AppKit

/// Code folding (TASK-19). Folds hide character ranges at the layout level only: the text, undo and the file never
/// change. Any edit touching a fold, and any selection that lands inside one, unfolds it first.
extension EditorViewController {
    private var folded: [NSRange] { editorLayoutManager.foldedRanges }

    /// Regions the language can fold, as the ranges they hide.
    var foldableRegions: [NSRange] { colorizer.foldRegions() }

    /// The 0-based line where `region` starts (the line of its opening token).
    func startLine(of region: NSRange) -> Int {
        lineIndex.line(of: max(0, region.location - 1), in: textView.string as NSString)
    }

    // MARK: Commands

    /// Folds the innermost unfolded region around the caret.
    @objc func fold(_ sender: Any?) {
        let caret = textView.selectedRange().location
        let candidates = foldableRegions.filter { region in
            NSLocationInRange(caret, NSRange(location: region.location - 1, length: region.length + 2)) && !isFolded(region)
        }
        guard let innermost = candidates.min(by: { $0.length < $1.length }) else { return }
        setFolded(folded + [innermost], keepCaretAt: innermost.location)
    }

    /// Unfolds the folds that start on the caret's line (or contain the caret).
    @objc func unfold(_ sender: Any?) {
        let text = textView.string as NSString
        let line = text.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
        setFolded(folded.filter { NSIntersectionRange($0, line).length == 0 && !NSLocationInRange(line.location, $0) })
    }

    @objc func foldAll(_ sender: Any?) {
        let regions = foldableRegions
        guard !regions.isEmpty else { return }
        setFolded(regions, keepCaretAt: textView.selectedRange().location)
    }

    @objc func unfoldAll(_ sender: Any?) {
        setFolded([])
    }

    /// The gutter's arrow for the region starting on `line`.
    func toggleFold(atLine line: Int) {
        guard let region = foldableRegions.filter({ startLine(of: $0) == line }).max(by: { $0.length < $1.length }) else { return }
        if isFolded(region) {
            setFolded(folded.filter { !NSEqualRanges($0, region) && NSIntersectionRange($0, region).length == 0 })
        } else {
            setFolded(folded + [region], keepCaretAt: textView.selectedRange().location)
        }
    }

    /// Gutter markers: one per line that starts a foldable region.
    /// Fold markers (start line → folded) of the regions starting in `range` (the visible text), or in all of it.
    func foldMarkers(in range: NSRange? = nil) -> [Int: Bool] {
        var markers: [Int: Bool] = [:]
        for region in range.map(colorizer.foldRegions(startingIn:)) ?? foldableRegions {
            let line = startLine(of: region)
            markers[line] = (markers[line] ?? false) || isFolded(region)
        }
        return markers
    }

    func isFolded(_ region: NSRange) -> Bool {
        folded.contains { NSEqualRanges($0, region) }
    }

    private func setFolded(_ ranges: [NSRange], keepCaretAt caret: Int? = nil) {
        var unique: [NSRange] = []
        for range in ranges where range.length > 0 && !unique.contains(where: { NSEqualRanges($0, range) }) { unique.append(range) }
        editorLayoutManager.setFoldedRanges(unique)
        // Keep the caret visible: inside a fold it moves to just before the ⋯.
        let selection = textView.selectedRange()
        if let fold = unique.first(where: { selection.location > $0.location && selection.location < NSMaxRange($0) }) {
            textView.setSelectedRange(NSRange(location: caret.map { min($0, fold.location) } ?? fold.location, length: 0))
        }
        ruler?.needsDisplay = true
        textView.needsDisplay = true
        scheduleFullLayout()
    }

    // MARK: Keeping folds right while editing

    /// Called from `didProcessEditing` for every character edit: edits touching a fold unfold it; folds after the
    /// edit move with it.
    func adjustFolds(editedRange: NSRange, changeInLength delta: Int) {
        guard !folded.isEmpty else { return }
        let old = NSRange(location: editedRange.location, length: editedRange.length - delta)
        var kept: [NSRange] = []
        var removed = false
        var start = editedRange.location
        for fold in folded {
            if NSMaxRange(old) < fold.location {
                kept.append(NSRange(location: fold.location + delta, length: fold.length))
            } else if old.location > NSMaxRange(fold) {
                kept.append(fold)
            } else {
                removed = true  // the edit touches or overlaps the fold
                start = min(start, fold.location)
            }
        }
        editorLayoutManager.replaceFoldedRangesSilently(kept)
        guard removed else { return }
        // The unfolded text's glyphs were generated hidden: regenerate them once the edit is processed.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let length = self.textView.textStorage?.length else { return }
                self.editorLayoutManager.invalidateFoldLayout(NSRange(location: min(start, length), length: length - min(start, length)))
                self.ruler?.needsDisplay = true
            }
        }
    }

    /// A selection moving into a fold: arrow keys step over the ⋯; anything else (clicks, find, Go to Line,
    /// selecting across) unfolds what it lands in.
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges oldRanges: [NSValue], toCharacterRanges newRanges: [NSValue]) -> [NSValue] {
        guard !folded.isEmpty, newRanges.count == 1, let new = newRanges.first?.rangeValue else { return newRanges }
        let old = oldRanges.first?.rangeValue
        guard let fold = folded.first(where: { NSIntersectionRange($0, new).length > 0 || (new.location > $0.location && new.location < NSMaxRange($0)) }) else {
            return newRanges
        }
        // A one-character step from the edge of a fold is an arrow key: step over the ⋯ instead of opening it.
        if new.length == 0, let old, old.length == 0, abs(new.location - old.location) <= 2 {
            if old.location == fold.location, new.location > fold.location { return [NSValue(range: NSRange(location: NSMaxRange(fold), length: 0))] }
            if old.location == NSMaxRange(fold), new.location < NSMaxRange(fold) { return [NSValue(range: NSRange(location: fold.location, length: 0))] }
        }
        let remaining = folded.filter { NSIntersectionRange($0, new).length == 0 && !(new.location > $0.location && new.location < NSMaxRange($0)) }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.editorLayoutManager.setFoldedRanges(remaining)
                self?.ruler?.needsDisplay = true
                self?.textView.scrollRangeToVisible(new)
            }
        }
        return newRanges
    }

    @objc func validateFoldingItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(unfoldAll(_:)): !folded.isEmpty
        default: !foldableRegions.isEmpty
        }
    }
}
