import AppKit
import QuickEditCore

/// Voice notes in Markdown files (decision-4): clips go to `<file name>.assets/` next to the document and are
/// linked at the caret with NoteMD's `+[label](clip.m4a)` embed syntax; the transcript is quoted below the link.
extension EditorViewController {
    static let recordingLabel = "Recording voice note…"

    var canRecordVoiceNote: Bool { state.previewKind == .markdown && !state.isReadOnly }

    @objc func recordVoiceNote(_ sender: Any?) {
        guard canRecordVoiceNote else { return }
        let recorder = state.voiceRecorder
        if recorder.isRecording {
            state.showsVoiceRecorder = true
            return
        }
        guard let documentURL = document.fileURL else {
            presentSaveFirst()
            return
        }
        let folder = Attachments.assetsFolder(forDocument: documentURL)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            presentError(error)
            return
        }
        let clip = Attachments.uniqueURL(in: folder, fileName: Attachments.timestampedName(prefix: "voice", pathExtension: "m4a"))
        let destination = Attachments.destination(for: clip, fromDocument: documentURL)
        let offset = textView.selectedRange().location
        state.showsVoiceRecorder = true
        recorder.start(saving: clip) { [weak self] event in
            guard let self else { return }
            if case .started = event {} else { state.showsVoiceRecorder = false }
            switch event {
            case .started:
                let placeholder = Attachments.markdownLink(name: Self.recordingLabel, destination: destination, kind: .audio)
                insert(Attachments.ownLine(placeholder, in: textView.string, at: offset), at: offset, actionName: "Record Voice Note")
            case .finished:
                let label = Attachments.escapeLabel("Voice note " + Date().formatted(date: .abbreviated, time: .shortened))
                if let ranges = Attachments.embedRanges(linkingFileNamed: clip.lastPathComponent, in: textView.string) {
                    textView.replace(ranges.label, with: label)
                } else {
                    let end = (textView.string as NSString).length
                    let link = Attachments.markdownLink(name: label, destination: destination, kind: .audio)
                    insert(Attachments.ownLine(link, in: textView.string, at: end), at: end, actionName: "Record Voice Note")
                }
                beginTranscription(source: destination)
            case .cancelled:
                if let ranges = Attachments.embedRanges(linkingFileNamed: clip.lastPathComponent, in: textView.string) {
                    textView.replace(Attachments.removalRange(of: ranges.embed, in: textView.string), with: "")
                }
                // Leave no empty assets folder behind.
                if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
    }

    /// Shows the transcription sheet for the clip linked as `source`.
    func beginTranscription(source: String) {
        guard let directory = document.fileURL?.deletingLastPathComponent(),
              let audio = Attachments.fileURL(forDestination: source, relativeTo: directory)
        else { return }
        state.transcribeURL = audio
        state.transcribeSource = source
    }

    /// Quotes `transcript` on its own line below the line linking `source`.
    func insertTranscript(_ transcript: String, forSource source: String) {
        let offset = Attachments.endOfLine(linking: source, in: textView.string)
        insert(Attachments.ownLine(Attachments.quote(transcript), in: textView.string, at: offset), at: offset, actionName: "Insert Transcript")
    }

    private func insert(_ text: String, at offset: Int, actionName: String) {
        let location = min(max(offset, 0), (textView.string as NSString).length)
        textView.replace(NSRange(location: location, length: 0), with: text)
        textView.undoManager?.setActionName(actionName)
    }

    private func presentSaveFirst() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Save this file before recording a voice note."
        alert.informativeText = "Voice notes are stored in a folder next to the file, so it needs a name and a place first."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.document.save(nil) }
        }
    }
}
