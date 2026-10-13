import Foundation

/// Every language QuickEdit knows, and detection from a file name, a `#!` line or a Markdown fence info string.
public enum LanguageRegistry {
    public static let plainText = Language(
        id: "plaintext", displayName: "Plain Text",
        extensions: ["txt", "text", "log"],
        fileNames: [
            "go.sum", "go.work.sum", "LICENSE", "LICENCE", "COPYING", "README", "AUTHORS", "NOTICE", "CHANGELOG",
            "CONTRIBUTORS",
        ],
        fileNamePatterns: [], shebangInterpreters: [],
        lineComment: nil, blockComment: nil, prefersTabs: false,
        highlighting: .none, aliases: ["text", "txt", "plain", "plaintext"]
    )

    public static let all: [Language] = [
        plainText,
        Language(
            id: "javascript", displayName: "JavaScript",
            extensions: ["js", "mjs", "cjs", "jsx"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: ["node", "nodejs", "bun"],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("javascript"), aliases: ["js", "javascript", "jsx", "mjs", "cjs", "node"]
        ),
        Language(
            id: "typescript", displayName: "TypeScript",
            extensions: ["ts", "mts", "cts"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: ["deno", "ts-node", "tsx"],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("typescript"), aliases: ["ts", "typescript", "mts", "cts"]
        ),
        Language(
            id: "tsx", displayName: "TSX",
            extensions: ["tsx"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("tsx"), aliases: ["tsx"]
        ),
        Language(
            id: "css", displayName: "CSS",
            extensions: ["css"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("css"), aliases: ["css"]
        ),
        Language(
            id: "html", displayName: "HTML",
            extensions: ["html", "htm", "xhtml", "shtml"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: nil, blockComment: markupComment, prefersTabs: false,
            highlighting: .grammar("html"), aliases: ["html", "htm", "xhtml"]
        ),
        Language(
            id: "markdown", displayName: "Markdown",
            extensions: ["md", "markdown", "mdx", "mdown", "mkd", "mkdn", "mdwn"], fileNames: [],
            fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: markupComment, prefersTabs: false,
            highlighting: .grammar("markdown"), aliases: ["md", "markdown", "mdx"]
        ),
        Language(
            id: "csv", displayName: "CSV",
            extensions: ["csv"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: nil, prefersTabs: false,
            highlighting: .delimited(0x2C), aliases: ["csv"]
        ),
        Language(
            id: "tsv", displayName: "TSV",
            extensions: ["tsv", "tab"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: nil, prefersTabs: true,
            highlighting: .delimited(0x09), aliases: ["tsv"]
        ),
        Language(
            id: "json", displayName: "JSON",
            extensions: ["json", "webmanifest", "xcstrings", "geojson", "jsonld", "har"],
            fileNames: ["Package.resolved", "composer.lock", "flake.lock", ".watchmanconfig"],
            fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: nil, prefersTabs: false,
            highlighting: .grammar("json"), aliases: ["json", "webmanifest", "geojson"]
        ),
        Language(
            id: "jsonc", displayName: "JSON with Comments",
            extensions: ["jsonc", "json5", "code-workspace"],
            fileNames: [
                "jsconfig.json", "devcontainer.json", ".devcontainer.json", ".babelrc", ".swcrc", ".jshintrc",
                ".eslintrc.json", "settings.json", "keybindings.json", "launch.json", "tasks.json",
                "extensions.json", "deno.json", "turbo.json", "biome.json",
            ],
            fileNamePatterns: ["tsconfig*.json", "jsconfig*.json"], shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("json"), aliases: ["jsonc", "json5"]
        ),
        Language(
            id: "jsonl", displayName: "JSON Lines",
            extensions: ["jsonl", "ndjson"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: nil, prefersTabs: false,
            highlighting: .grammar("json"), aliases: ["jsonl", "ndjson"]
        ),
        Language(
            id: "yaml", displayName: "YAML",
            extensions: ["yaml", "yml", "cff"], fileNames: [".clang-format", ".clang-tidy", ".yamllint"],
            fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("yaml"), aliases: ["yaml", "yml"]
        ),
        Language(
            id: "toml", displayName: "TOML",
            extensions: ["toml"], fileNames: ["Cargo.lock", "Pipfile", "poetry.lock", "uv.lock"],
            fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("toml"), aliases: ["toml"]
        ),
        Language(
            id: "go", displayName: "Go",
            extensions: ["go"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: true,
            highlighting: .grammar("go"), aliases: ["go", "golang"]
        ),
        Language(
            id: "gomod", displayName: "Go Module",
            extensions: [], fileNames: ["go.mod", "go.work"], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "//", blockComment: nil, prefersTabs: true,
            highlighting: .grammar("gomod"), aliases: ["gomod", "go.mod", "gowork"]
        ),
        Language(
            id: "rust", displayName: "Rust",
            extensions: ["rs"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("rust"), aliases: ["rust", "rs"]
        ),
        Language(
            id: "python", displayName: "Python",
            extensions: ["py", "pyi", "pyw"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: ["python", "python2", "python3", "pypy", "pypy3", "uv"],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("python"), aliases: ["python", "py", "python3", "py3", "gyp"]
        ),
        Language(
            id: "swift", displayName: "Swift",
            extensions: ["swift"], fileNames: [], fileNamePatterns: [], shebangInterpreters: ["swift"],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("swift"), aliases: ["swift"]
        ),
        Language(
            id: "gdscript", displayName: "GDScript",
            extensions: ["gd"], fileNames: [], fileNamePatterns: [], shebangInterpreters: ["godot"],
            lineComment: "#", blockComment: nil, prefersTabs: true,
            highlighting: .grammar("gdscript"), aliases: ["gdscript", "gd"]
        ),
        Language(
            id: "godot-resource", displayName: "Godot Resource",
            extensions: ["tscn", "tres", "godot", "import", "gdextension"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: ";", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("godot_resource"), aliases: ["tscn", "tres", "godot", "gdresource"]
        ),
        Language(
            id: "gdshader", displayName: "Godot Shader",
            extensions: ["gdshader", "gdshaderinc"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: true,
            highlighting: .grammar("gdshader"), aliases: ["gdshader", "gdshaderinc"]
        ),
        Language(
            id: "dockerfile", displayName: "Dockerfile",
            extensions: ["dockerfile", "containerfile"], fileNames: ["Dockerfile", "Containerfile"],
            fileNamePatterns: ["Dockerfile.*", "Containerfile.*", "*.dockerfile"], shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("dockerfile"), aliases: ["dockerfile", "docker", "containerfile"]
        ),
        Language(
            id: "xml", displayName: "XML",
            extensions: [
                "xml", "plist", "entitlements", "xcprivacy", "svg", "xsd", "xsl", "xslt", "xib", "storyboard",
                "xcscheme", "xcworkspacedata", "rss", "atom", "xaml", "csproj", "fsproj", "vbproj", "vcxproj",
                "props", "targets", "nuspec", "resx", "xliff", "xlf", "gpx", "kml", "wsdl",
            ],
            fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: markupComment, prefersTabs: false,
            highlighting: .grammar("xml"), aliases: ["xml", "plist", "svg", "xsd", "xsl", "xslt"]
        ),
        Language(
            id: "dtd", displayName: "DTD",
            extensions: ["dtd"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: markupComment, prefersTabs: false,
            highlighting: .grammar("dtd"), aliases: ["dtd"]
        ),
        Language(
            id: "ini", displayName: "INI",
            extensions: ["ini", "cfg", "conf", "properties", "desktop", "service"],
            fileNames: [
                ".editorconfig", ".gitconfig", ".gitmodules", ".npmrc", ".pypirc", ".flake8", ".pylintrc",
                ".coveragerc",
            ],
            fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("ini"),
            aliases: ["ini", "cfg", "conf", "editorconfig", "gitconfig", "properties", "dosini"]
        ),
        Language(
            id: "shell", displayName: "Shell Script",
            extensions: ["sh", "bash", "zsh", "ksh", "command"],
            fileNames: [
                ".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".bash_aliases", ".zshrc", ".zshenv",
                ".zprofile", ".zlogin", ".zlogout", ".profile", ".kshrc", ".envrc", "PKGBUILD", "APKBUILD",
            ],
            fileNamePatterns: [], shebangInterpreters: ["sh", "bash", "zsh", "ksh", "dash", "ash", "mksh"],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("bash"), aliases: ["sh", "bash", "zsh", "shell", "shellscript", "ksh"]
        ),
        Language(
            id: "makefile", displayName: "Makefile",
            extensions: ["mk", "mak"], fileNames: ["Makefile", "GNUmakefile"],
            fileNamePatterns: ["Makefile.*"], shebangInterpreters: ["make"],
            lineComment: "#", blockComment: nil, prefersTabs: true,
            highlighting: .grammar("make"), aliases: ["make", "makefile", "mk"]
        ),
        Language(
            id: "sql", displayName: "SQL",
            extensions: ["sql", "psql", "pgsql", "ddl"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "--", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("sql"),
            aliases: ["sql", "postgres", "postgresql", "pgsql", "psql", "mysql", "sqlite", "plsql"]
        ),
        Language(
            id: "dotenv", displayName: "Environment",
            extensions: ["env"], fileNames: [".env"], fileNamePatterns: [".env.*"], shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("bash"), aliases: ["dotenv", "env"]
        ),
        Language(
            id: "ignore", displayName: "Ignore List",
            extensions: ["gitignore"],
            fileNames: [
                ".gitignore", ".dockerignore", ".npmignore", ".eslintignore", ".prettierignore", ".stylelintignore",
                ".vscodeignore", ".gcloudignore", ".ignore", ".rgignore", ".fdignore", ".slugignore", ".cfignore",
                ".helmignore", ".vercelignore",
            ],
            fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("gitignore"), aliases: ["gitignore", "ignore", "dockerignore"]
        ),
        Language(
            id: "gitattributes", displayName: "Git Attributes",
            extensions: ["gitattributes"], fileNames: [".gitattributes"], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("gitattributes"), aliases: ["gitattributes"]
        ),
        Language(
            id: "diff", displayName: "Diff",
            extensions: ["diff", "patch", "rej"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: nil, blockComment: nil, prefersTabs: false,
            highlighting: .grammar("diff"), aliases: ["diff", "patch", "udiff"]
        ),
    ]

    public static func language(id: String) -> Language? {
        index.byID[id]
    }

    /// Detects a file's language: exact file name, then file name pattern, then extension, then the `#!`
    /// interpreter on the first line; plain text when nothing matches. `fileName` may be a full path.
    public static func detect(fileName: String, firstLine: String?) -> Language {
        let name = (fileName as NSString).lastPathComponent
        let lowercased = name.lowercased()
        if let language = index.byFileName[lowercased] {
            return language
        }
        for (pattern, language) in index.patterns where Glob.matches(pattern, lowercased) {
            return language
        }
        if let language = extensionLanguage(lowercased) {
            return language
        }
        if let interpreter = firstLine.flatMap(shebangInterpreter), let language = index.byInterpreter(interpreter) {
            return language
        }
        return plainText
    }

    /// The language for a Markdown fenced code info string (```` ```ts ````, ```` ```{.python} ````,
    /// ```` ```yml title="x" ````), matched against aliases, ids and extensions.
    public static func language(forFenceInfo info: String) -> Language? {
        var word = Substring(info.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        word = word.drop(while: { $0 == "{" || $0 == "." })
        word = word.prefix(while: { !$0.isWhitespace && $0 != "," && $0 != "{" && $0 != "}" && $0 != ":" })
        guard !word.isEmpty else { return nil }
        let key = String(word)
        return index.byAlias[key] ?? index.byID[key] ?? index.byExtension[key]
    }

    // MARK: - Private

    private static let cStyle = BlockComment(open: "/*", close: "*/")
    private static let markupComment = BlockComment(open: "<!--", close: "-->")

    private struct Index {
        var byID: [String: Language] = [:]
        var byFileName: [String: Language] = [:]
        var byExtension: [String: Language] = [:]
        var byAlias: [String: Language] = [:]
        var interpreters: [String: Language] = [:]
        var patterns: [(String, Language)] = []

        func byInterpreter(_ interpreter: String) -> Language? {
            if let language = interpreters[interpreter] {
                return language
            }
            // python3.12 → python, pypy3 → pypy
            let trimmed = interpreter.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-"))
            return trimmed.isEmpty ? nil : interpreters[trimmed]
        }
    }

    private static let index: Index = {
        var index = Index()
        for language in all {
            index.byID[language.id] = language
            for name in language.fileNames { index.byFileName[name.lowercased()] = language }
            for ext in language.extensions { index.byExtension[ext] = language }
            for alias in language.aliases { index.byAlias[alias] = language }
            for interpreter in language.shebangInterpreters { index.interpreters[interpreter] = language }
            for pattern in language.fileNamePatterns { index.patterns.append((pattern.lowercased(), language)) }
        }
        return index
    }()

    /// The longest matching extension, so "x.d.ts" and multi-dot names still resolve by their last part.
    private static func extensionLanguage(_ lowercasedName: String) -> Language? {
        var rest = Substring(lowercasedName)
        // A leading dot is part of the name (".bashrc"), not an extension separator.
        if rest.hasPrefix(".") { rest = rest.dropFirst() }
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        var candidate = rest[rest.index(after: dot)...]
        while true {
            if let language = index.byExtension[String(candidate)] {
                return language
            }
            guard let next = candidate.firstIndex(of: ".") else { return nil }
            candidate = candidate[candidate.index(after: next)...]
        }
    }

    /// "#!/usr/bin/env -S uv run" → "uv"; "#!/bin/bash -e" → "bash".
    static func shebangInterpreter(_ line: String) -> String? {
        guard line.hasPrefix("#!") else { return nil }
        var words = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !words.isEmpty else { return nil }
        var program = (words.removeFirst() as NSString).lastPathComponent
        if program == "env" {
            var skipNext = false
            program = ""
            for word in words {
                if skipNext {
                    skipNext = false
                } else if word == "-u" || word == "--unset" || word == "-C" || word == "--chdir" {
                    skipNext = true
                } else if word.hasPrefix("-") || word.contains("=") {
                    continue
                } else {
                    program = (word as NSString).lastPathComponent
                    break
                }
            }
        }
        program = program.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return program.isEmpty ? nil : program
    }
}

/// Minimal glob matching for (lowercased) file names: `*` matches any run, `?` one character.
enum Glob {
    static func matches(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern.unicodeScalars)
        let n = Array(name.unicodeScalars)
        var pi = 0, ni = 0
        var star = -1, starMatch = 0
        while ni < n.count {
            if pi < p.count, p[pi] == "?" || p[pi] == n[ni] {
                pi += 1
                ni += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi
                starMatch = ni
                pi += 1
            } else if star >= 0 {
                pi = star + 1
                starMatch += 1
                ni = starMatch
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
