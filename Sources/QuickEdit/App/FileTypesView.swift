import AppKit
import SwiftUI

/// Settings › File Types: the supported types with a checkbox for "opens in QuickEdit".
struct FileTypesView: View {
    let associations: FileAssociations

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose which files open in QuickEdit when you double-click them in Finder.")
                .foregroundStyle(.secondary)
            List {
                ForEach(groups, id: \.0) { language, rows in
                    Section(language) {
                        ForEach(rows) { row in
                            FileTypeRow(row: row) { associations.setChecked($0, for: row.id) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 320)
            Text("Unchecking a type gives it back to the app that opened it before. Files without an extension (Dockerfile, Makefile) can't be associated: use Open With or drop them on QuickEdit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Select All") { associations.setAll(true) }
                Button("Select None") { associations.setAll(false) }
                Spacer()
                if let result = associations.lastResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                Button("Apply") { Task { await associations.apply() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!associations.hasChanges || associations.isApplying)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { associations.reload() }
    }

    private var groups: [(String, [FileAssociations.Row])] {
        var order: [String] = []
        var byLanguage: [String: [FileAssociations.Row]] = [:]
        for row in associations.rows {
            if byLanguage[row.language] == nil { order.append(row.language) }
            byLanguage[row.language, default: []].append(row)
        }
        return order.map { ($0, byLanguage[$0] ?? []) }
    }
}

private struct FileTypeRow: View {
    let row: FileAssociations.Row
    let setChecked: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: Binding(get: { row.isChecked }, set: { setChecked($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.extensions.map { "." + $0 }.joined(separator: "  ")).monospaced()
                    if let note = row.note {
                        Text(note).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if let app = row.currentApp {
                HStack(spacing: 4) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 16, height: 16)
                    Text(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(app.path)
            } else {
                Text("No app").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
