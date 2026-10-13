import AppKit
import Observation
import QuickEditSyntax
import UniformTypeIdentifiers

/// Which app macOS opens each supported file type with, and making QuickEdit (or the previous app) the default.
@Observable final class FileAssociations {
    struct Row: Identifiable, Equatable {
        let type: UTType
        let extensions: [String]
        let language: String
        /// The app that opens this type today (nil: none).
        var currentApp: URL?
        var isChecked: Bool
        var id: String { type.identifier }

        var note: String? {
            // .ts and .mts are also video formats to macOS.
            type.conforms(to: .audiovisualContent) ? "macOS also uses this type for video files: they would open in QuickEdit too." : nil
        }
    }

    private(set) var rows: [Row] = []
    private(set) var isApplying = false
    private(set) var lastResult: String?

    /// Agent builds never touch the user's real defaults: they record what they would change.
    private let isDryRun = AppVariant.name == "test"
    private(set) var dryRunChanges: [String] = []

    private static let previousAppsKey = "previousDefaultApps"
    private var appURL: URL { Bundle.main.bundleURL }

    /// Rows for every extension the registry knows, one per file type, grouped by language.
    func reload() {
        var seen = Set<String>()
        var result: [Row] = []
        for language in LanguageRegistry.all.sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) {
            var byType: [String: (UTType, [String])] = [:]
            var order: [String] = []
            for ext in language.extensions {
                guard let type = UTType(filenameExtension: ext), !type.isDynamic, !seen.contains(type.identifier) else { continue }
                if byType[type.identifier] == nil { order.append(type.identifier) }
                byType[type.identifier, default: (type, [])].1.append(ext)
            }
            for identifier in order {
                seen.insert(identifier)
                guard let (type, extensions) = byType[identifier] else { continue }
                let current = NSWorkspace.shared.urlForApplication(toOpen: type)
                result.append(Row(type: type, extensions: extensions, language: language.displayName,
                                  currentApp: current, isChecked: isQuickEdit(current)))
            }
        }
        rows = result
    }

    func isQuickEdit(_ url: URL?) -> Bool {
        guard let url else { return false }
        return Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    func setChecked(_ checked: Bool, for id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isChecked = checked
    }

    func setAll(_ checked: Bool) {
        for index in rows.indices { rows[index].isChecked = checked }
    }

    var hasChanges: Bool { rows.contains { $0.isChecked != isQuickEdit($0.currentApp) } }

    /// Makes QuickEdit the default for checked types; gives unchecked ones back to the app they had before.
    func apply() async {
        isApplying = true
        defer { isApplying = false }
        var previous = UserDefaults.standard.dictionary(forKey: Self.previousAppsKey) as? [String: String] ?? [:]
        var changed = 0
        var failures: [String] = []
        for row in rows where row.isChecked != isQuickEdit(row.currentApp) {
            let target: URL?
            if row.isChecked {
                if let current = row.currentApp { previous[row.id] = current.path }
                target = appURL
            } else {
                target = previous[row.id].map { URL(fileURLWithPath: $0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                    ?? NSWorkspace.shared.urlsForApplications(toOpen: row.type).first { !isQuickEdit($0) }
            }
            guard let target else {
                failures.append(".\(row.extensions.joined(separator: ", ."))")
                continue
            }
            if isDryRun {
                dryRunChanges.append("\(row.id) -> \(target.lastPathComponent)")
                changed += 1
                continue
            }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: target, toOpen: row.type)
                changed += 1
            } catch {
                failures.append(".\(row.extensions.joined(separator: ", .")): \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(previous, forKey: Self.previousAppsKey)
        lastResult = failures.isEmpty
            ? (changed == 1 ? "Changed 1 file type." : "Changed \(changed) file types.")
            : "Changed \(changed); couldn't change \(failures.joined(separator: "; "))."
        if !isDryRun { reload() }
    }
}
