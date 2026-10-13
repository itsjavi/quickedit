import Foundation
import Testing

@testable import QuickEditSyntax

@Suite("Language detection")
struct DetectionTests {
    private func detect(_ name: String, _ firstLine: String? = nil) -> String {
        LanguageRegistry.detect(fileName: name, firstLine: firstLine).id
    }

    @Test("exact file names", arguments: [
        ("Dockerfile", "dockerfile"), ("dockerfile", "dockerfile"), ("Containerfile", "dockerfile"),
        ("Makefile", "makefile"), ("makefile", "makefile"), ("GNUmakefile", "makefile"),
        (".env", "dotenv"), ("go.mod", "gomod"), ("go.work", "gomod"), ("go.sum", "plaintext"),
        ("Package.resolved", "json"), ("Cargo.lock", "toml"), (".gitignore", "ignore"), (".dockerignore", "ignore"),
        (".gitattributes", "gitattributes"), (".editorconfig", "ini"), (".gitconfig", "ini"), (".npmrc", "ini"),
        (".zshrc", "shell"), (".bashrc", "shell"), (".bash_profile", "shell"), (".zprofile", "shell"),
        (".profile", "shell"), ("jsconfig.json", "jsonc"), ("devcontainer.json", "jsonc"), ("LICENSE", "plaintext"),
        ("README", "plaintext"), ("PKGBUILD", "shell"),
    ])
    func fileNames(name: String, expected: String) {
        #expect(detect(name) == expected)
    }

    @Test("file name patterns", arguments: [
        (".env.local", "dotenv"), (".env.production", "dotenv"), ("tsconfig.json", "jsonc"),
        ("tsconfig.base.json", "jsonc"), ("tsconfig.app.json", "jsonc"), ("jsconfig.node.json", "jsonc"),
        ("Dockerfile.dev", "dockerfile"), ("api.dockerfile", "dockerfile"), ("App.Dockerfile", "dockerfile"),
        ("Containerfile.prod", "dockerfile"), ("Makefile.am", "makefile"),
    ])
    func patterns(name: String, expected: String) {
        #expect(detect(name) == expected)
    }

    @Test("extensions", arguments: [
        ("app.js", "javascript"), ("a.mjs", "javascript"), ("a.cjs", "javascript"), ("a.jsx", "javascript"),
        ("a.ts", "typescript"), ("a.mts", "typescript"), ("a.cts", "typescript"), ("types.d.ts", "typescript"),
        ("a.tsx", "tsx"), ("a.css", "css"), ("a.html", "html"), ("a.htm", "html"), ("a.xhtml", "html"),
        ("a.md", "markdown"), ("a.markdown", "markdown"), ("a.mdx", "markdown"), ("a.csv", "csv"), ("a.tsv", "tsv"),
        ("a.json", "json"), ("site.webmanifest", "json"), ("Localizable.xcstrings", "json"), ("a.jsonc", "jsonc"),
        ("a.json5", "jsonc"), ("a.jsonl", "jsonl"), ("a.ndjson", "jsonl"), ("a.yaml", "yaml"), ("a.yml", "yaml"),
        ("a.toml", "toml"), ("a.go", "go"), ("a.rs", "rust"), ("a.py", "python"), ("a.pyi", "python"),
        ("a.pyw", "python"), ("a.swift", "swift"), ("a.gd", "gdscript"), ("a.tscn", "godot-resource"),
        ("a.tres", "godot-resource"), ("project.godot", "godot-resource"), ("icon.png.import", "godot-resource"),
        ("a.gdshader", "gdshader"), ("a.xml", "xml"), ("Info.plist", "xml"), ("App.entitlements", "xml"),
        ("PrivacyInfo.xcprivacy", "xml"), ("a.svg", "xml"), ("a.xsd", "xml"), ("a.xsl", "xml"), ("a.xslt", "xml"),
        ("Main.xib", "xml"), ("Main.storyboard", "xml"), ("a.dtd", "dtd"), ("a.ini", "ini"), ("a.cfg", "ini"),
        ("a.conf", "ini"), ("a.properties", "ini"), ("a.sh", "shell"), ("a.bash", "shell"), ("a.zsh", "shell"),
        ("a.mk", "makefile"), ("a.sql", "sql"), ("a.diff", "diff"), ("a.patch", "diff"), ("a.txt", "plaintext"),
        ("a.log", "plaintext"), ("A.JS", "javascript"), ("NOTES.MD", "markdown"), ("prod.env", "dotenv"),
    ])
    func extensions(name: String, expected: String) {
        #expect(detect(name) == expected)
    }

    @Test("shebangs", arguments: [
        ("#!/bin/sh", "shell"), ("#!/bin/bash -e", "shell"), ("#!/usr/bin/env bash", "shell"),
        ("#!/usr/bin/env zsh", "shell"), ("#!/usr/bin/env python3", "python"), ("#!/usr/bin/python3.12", "python"),
        ("#!/usr/bin/env node", "javascript"), ("#!/usr/bin/env -S deno run", "typescript"),
        ("#!/usr/bin/env -S uv run --script", "python"), ("#!/usr/bin/swift", "swift"),
        ("#!/usr/bin/make -f", "makefile"), ("#!/usr/bin/env -i PATH=/bin bash", "shell"),
    ])
    func shebangs(line: String, expected: String) {
        #expect(detect("script", line) == expected)
    }

    @Test("precedence and fallback")
    func precedence() {
        // The name and extension win over the shebang.
        #expect(detect("run.py", "#!/bin/bash") == "python")
        #expect(detect("notes.txt", "#!/bin/bash") == "plaintext")
        #expect(detect("Makefile", "#!/usr/bin/env python3") == "makefile")
        // Unknown names, extensions and interpreters fall back to plain text.
        #expect(detect("archive.tar.gz") == "plaintext")
        #expect(detect("unknown") == "plaintext")
        #expect(detect("unknown", "#!/usr/bin/env ruby") == "plaintext")
        #expect(detect("unknown", "not a shebang") == "plaintext")
        #expect(detect("") == "plaintext")
        // Paths are reduced to their last component.
        #expect(detect("/Users/me/project/Dockerfile") == "dockerfile")
        #expect(detect("/tmp/.env.test") == "dotenv")
    }

    @Test("fence info strings", arguments: [
        ("ts", "typescript"), ("typescript", "typescript"), ("js", "javascript"), ("jsx", "javascript"),
        ("tsx", "tsx"), ("bash", "shell"), ("sh", "shell"), ("shell", "shell"), ("zsh", "shell"), ("yml", "yaml"),
        ("yaml", "yaml"), ("json", "json"), ("jsonc", "jsonc"), ("py", "python"), ("python", "python"),
        ("rust", "rust"), ("rs", "rust"), ("go", "go"), ("swift", "swift"), ("html", "html"), ("css", "css"),
        ("md", "markdown"), ("diff", "diff"), ("patch", "diff"), ("dockerfile", "dockerfile"), ("sql", "sql"),
        ("toml", "toml"), ("ini", "ini"), ("xml", "xml"), ("gdscript", "gdscript"), ("make", "makefile"),
        ("text", "plaintext"), ("TS", "typescript"), ("  python  ", "python"), ("ts title=\"a.ts\"", "typescript"),
        ("{.python .numberLines}", "python"), ("js,linenos", "javascript"), ("csv", "csv"), ("dotenv", "dotenv"),
    ])
    func fenceInfo(info: String, expected: String) {
        #expect(LanguageRegistry.language(forFenceInfo: info)?.id == expected)
    }

    @Test("unknown fence info")
    func unknownFenceInfo() {
        #expect(LanguageRegistry.language(forFenceInfo: "") == nil)
        #expect(LanguageRegistry.language(forFenceInfo: "elixir") == nil)
        #expect(LanguageRegistry.language(forFenceInfo: "c++") == nil)
    }

    @Test("registry is consistent")
    func registry() {
        let ids = LanguageRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids")
        var extensions: [String: String] = [:]
        var names: [String: String] = [:]
        for language in LanguageRegistry.all {
            #expect(LanguageRegistry.language(id: language.id) == language)
            for ext in language.extensions {
                #expect(ext == ext.lowercased() && !ext.hasPrefix("."), "\(language.id): \(ext)")
                #expect(extensions.updateValue(language.id, forKey: ext) == nil, "extension \(ext) mapped twice")
            }
            for name in language.fileNames {
                #expect(names.updateValue(language.id, forKey: name.lowercased()) == nil, "file name \(name) mapped twice")
            }
        }
        #expect(LanguageRegistry.language(id: "plaintext") == LanguageRegistry.plainText)
        #expect(LanguageRegistry.language(id: "nope") == nil)
    }

    @Test("comment tokens and indentation preferences")
    func metadata() {
        func language(_ id: String) -> Language { LanguageRegistry.language(id: id)! }
        #expect(language("typescript").lineComment == "//")
        #expect(language("typescript").blockComment == BlockComment(open: "/*", close: "*/"))
        #expect(language("python").lineComment == "#")
        #expect(language("python").blockComment == nil)
        #expect(language("html").lineComment == nil)
        #expect(language("html").blockComment == BlockComment(open: "<!--", close: "-->"))
        #expect(language("css").lineComment == nil)
        #expect(language("sql").lineComment == "--")
        #expect(language("json").lineComment == nil)
        #expect(language("jsonc").lineComment == "//")
        #expect(language("godot-resource").lineComment == ";")
        #expect(language("makefile").prefersTabs)
        #expect(language("go").prefersTabs)
        #expect(!language("python").prefersTabs)
        #expect(language("dotenv").displayName == "Environment")
        #expect(language("dotenv").hasHighlighting)
        #expect(!LanguageRegistry.plainText.hasHighlighting)
        #expect(language("csv").hasHighlighting)
    }

    @Test("glob matching")
    func glob() {
        #expect(Glob.matches("tsconfig*.json", "tsconfig.json"))
        #expect(Glob.matches("tsconfig*.json", "tsconfig.app.json"))
        #expect(!Glob.matches("tsconfig*.json", "tsconfig.json5"))
        #expect(Glob.matches(".env.*", ".env.local"))
        #expect(!Glob.matches(".env.*", ".env"))
        #expect(Glob.matches("a?c", "abc"))
        #expect(!Glob.matches("a?c", "ac"))
        #expect(Glob.matches("*", ""))
    }
}
