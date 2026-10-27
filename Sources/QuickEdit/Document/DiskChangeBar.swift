import SwiftUI

/// The bar above the editor when the file changed on disk and the window can't simply reload it: it has unsaved
/// edits, or the file is gone. It never takes focus or blocks typing (decision-3).
struct DiskChangeBar: View {
    static let height: CGFloat = 30

    let state: EditorState
    weak var document: TextDocument?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            switch state.diskChange {
            case .modified:
                Button("Keep My Edits") { document?.keepEditsOverDiskChange() }
                    .help("Keep editing this version. Saving replaces the file on disk.")
                Button("Reload") { document?.reloadFromDisk() }
                    .help("Show the file on disk instead. Undo brings your edits back.")
            case .deleted:
                Button("Save") { document?.save(nil) }
                    .help("Write this text back to the file.")
            case nil:
                EmptyView()
            }
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var message: String {
        switch state.diskChange {
        case .modified: "This file changed on disk. Your unsaved edits are still here."
        case .deleted: "This file was deleted or moved on disk. The text is still here."
        case nil: ""
        }
    }
}
