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
            id: "stsx", displayName: "Lumiose TSX",
            extensions: ["stsx"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .styled("tsx"), aliases: ["stsx"]
        ),
        Language(
            id: "sjsx", displayName: "Lumiose JSX",
            extensions: ["sjsx"], fileNames: [], fileNamePatterns: [], shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            // The TSX grammar: the JavaScript grammar rejects reserved words such as `class` and `for` as JSX
            // attribute names, which Lumiose components use.
            highlighting: .styled("tsx"), aliases: ["sjsx"]
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
            id: "c", displayName: "C",
            extensions: ["c", "h"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("c"), aliases: ["c", "h"]
        ),
        Language(
            id: "cpp", displayName: "C++",
            extensions: ["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "ipp", "inl", "tpp", "ixx", "cppm"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("cpp"), aliases: ["cpp", "c++", "cxx", "cc", "hpp"]
        ),
        Language(
            id: "objc", displayName: "Objective-C",
            extensions: ["m", "mm"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("objc"), aliases: ["objc", "objective-c", "objectivec", "obj-c", "objc++", "objective-c++"]
        ),
        Language(
            id: "csharp", displayName: "C#",
            extensions: ["cs", "csx"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("c_sharp"), aliases: ["cs", "csharp", "c#"]
        ),
        Language(
            id: "java", displayName: "Java",
            extensions: ["java"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("java"), aliases: ["java"]
        ),
        Language(
            id: "kotlin", displayName: "Kotlin",
            extensions: ["kt", "kts"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("kotlin"), aliases: ["kotlin", "kt", "kts"]
        ),
        Language(
            id: "php", displayName: "PHP",
            extensions: ["php", "phtml"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: ["php"],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("php"), aliases: ["php"]
        ),
        Language(
            id: "ruby", displayName: "Ruby",
            extensions: ["rb", "gemspec", "rake", "ru", "podspec", "rbw"], fileNames: ["Gemfile", "Rakefile", "Podfile", "Brewfile", "Guardfile", "Fastfile", "Appfile", "Matchfile", "Vagrantfile", "Dangerfile", "Capfile", "Berksfile", "Thorfile"], fileNamePatterns: [],
            shebangInterpreters: ["ruby"],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("ruby"), aliases: ["ruby", "rb"]
        ),
        Language(
            id: "lua", displayName: "Lua",
            extensions: ["lua"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: ["lua", "luajit"],
            lineComment: "--", blockComment: BlockComment(open: "--[[", close: "]]"), prefersTabs: false,
            highlighting: .grammar("lua"), aliases: ["lua"]
        ),
        Language(
            id: "scss", displayName: "SCSS",
            extensions: ["scss"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("scss"), aliases: ["scss"]
        ),
        Language(
            id: "less", displayName: "Less",
            extensions: ["less"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("scss"), aliases: ["less"]
        ),
        Language(
            id: "sass", displayName: "Sass",
            extensions: ["sass"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("sass"), aliases: ["sass"]
        ),
        Language(
            id: "vue", displayName: "Vue",
            extensions: ["vue"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: nil, blockComment: markupComment, prefersTabs: false,
            highlighting: .grammar("vue"), aliases: ["vue"]
        ),
        Language(
            id: "svelte", displayName: "Svelte",
            extensions: ["svelte"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: nil, blockComment: markupComment, prefersTabs: false,
            highlighting: .grammar("svelte"), aliases: ["svelte"]
        ),
        Language(
            id: "graphql", displayName: "GraphQL",
            extensions: ["graphql", "gql", "graphqls"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("graphql"), aliases: ["graphql", "gql"]
        ),
        Language(
            id: "proto", displayName: "Protocol Buffers",
            extensions: ["proto"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("proto"), aliases: ["proto", "protobuf"]
        ),
        Language(
            id: "terraform", displayName: "Terraform",
            extensions: ["tf", "tfvars"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "#", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("terraform"), aliases: ["terraform", "tf", "tfvars"]
        ),
        Language(
            id: "hcl", displayName: "HCL",
            extensions: ["hcl"], fileNames: [".terraformrc", "terraform.rc"], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "#", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("hcl"), aliases: ["hcl"]
        ),
        Language(
            id: "zig", displayName: "Zig",
            extensions: ["zig", "zon"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("zig"), aliases: ["zig"]
        ),
        Language(
            id: "dart", displayName: "Dart",
            extensions: ["dart"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("dart"), aliases: ["dart"]
        ),
        Language(
            id: "powershell", displayName: "PowerShell",
            extensions: ["ps1", "psm1", "psd1"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: ["pwsh", "powershell"],
            lineComment: "#", blockComment: BlockComment(open: "<#", close: "#>"), prefersTabs: false,
            highlighting: .grammar("powershell"), aliases: ["powershell", "ps1", "pwsh", "posh"]
        ),
        Language(
            id: "metal", displayName: "Metal",
            extensions: ["metal"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("cpp"), aliases: ["metal"]
        ),
        Language(
            id: "glsl", displayName: "GLSL",
            extensions: ["glsl", "vert", "frag", "geom", "comp", "tesc", "tese"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("glsl"), aliases: ["glsl"]
        ),
        Language(
            id: "cmake", displayName: "CMake",
            extensions: ["cmake"], fileNames: ["CMakeLists.txt"], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "#", blockComment: nil, prefersTabs: false,
            highlighting: .grammar("cmake"), aliases: ["cmake"]
        ),
        Language(
            id: "nix", displayName: "Nix",
            extensions: ["nix"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "#", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("nix"), aliases: ["nix"]
        ),
        Language(
            id: "spicedb", displayName: "SpiceDB Schema",
            extensions: ["zed"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .grammar("spicedb"), aliases: ["zed", "spicedb"]
        ),
        Language(
            id: "xcconfig", displayName: "Xcode Configuration",
            extensions: ["xcconfig"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: nil, prefersTabs: false,
            highlighting: .lexer(.xcconfig), aliases: ["xcconfig"]
        ),
        Language(
            id: "strings", displayName: "Strings",
            extensions: ["strings"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .lexer(.appleStrings), aliases: ["strings"]
        ),
        Language(
            id: "pbxproj", displayName: "Xcode Project",
            extensions: ["pbxproj"], fileNames: [], fileNamePatterns: [],
            shebangInterpreters: [],
            lineComment: "//", blockComment: cStyle, prefersTabs: false,
            highlighting: .lexer(.openStep), aliases: ["pbxproj"]
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
            extensions: ["yaml", "yml", "cff", "zaml"], fileNames: [".clang-format", ".clang-tidy", ".yamllint"],
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
    ///
    /// `content`, the start of the text (about 8 KB is plenty), refines ambiguous extensions: a `.h` header is
    /// Objective-C, C++ or C by what it declares. Without it `.h` is C. When `firstLine` is nil it's read from
    /// `content`.
    public static func detect(fileName: String, firstLine: String?, content: String? = nil) -> Language {
        let name = (fileName as NSString).lastPathComponent
        let lowercased = name.lowercased()
        if let language = index.byFileName[lowercased] {
            return language
        }
        for (pattern, language) in index.patterns where Glob.matches(pattern, lowercased) {
            return language
        }
        if let language = extensionLanguage(lowercased) {
            if lowercased.hasSuffix(".h"), let content {
                return headerLanguage(content)
            }
            return language
        }
        let firstLine = firstLine ?? content.map { String($0.prefix(while: { !$0.isNewline })) }
        if let interpreter = firstLine.flatMap(shebangInterpreter), let language = index.byInterpreter(interpreter) {
            return language
        }
        return plainText
    }

    /// Objective-C, C++ or C for a header's text.
    static func headerLanguage(_ content: String) -> Language {
        let text = String(content.prefix(8 * 1024))
        func found(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression]) != nil
        }
        let objectiveC = #"(?m)^\s*(@(interface|implementation|protocol|import|class|end)\b|#import\b|NS_ASSUME_NONNULL_BEGIN)"#
        let cpp =
            #"(?m)(^\s*((class|namespace)\b|template\s*<|using\s+namespace\b|(public|private|protected)\s*:)|std::|^\s*#include\s*<(iostream|string|vector|memory|map|unordered_map|functional|optional|utility|algorithm|array|cstdint|cstddef|cstdio|cstdlib|cstring|type_traits)>)"#
        if found(objectiveC), let language = index.byID["objc"] { return language }
        if found(cpp), let language = index.byID["cpp"] { return language }
        return index.byID["c"] ?? plainText
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
