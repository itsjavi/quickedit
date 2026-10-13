import Foundation
import Testing

@testable import QuickEditSyntax

/// Fixtures for the languages added in 0.3.0 (TASK-37).
@Suite("More languages")
struct MoreLanguagesTests {
    static let fixtures: [Fixture] = [
        Fixture(
            language: "c",
            source: """
                #include <stdio.h>
                #define MAX 10
                /* comment */
                typedef struct { int x; } Point;
                static int add(int a, int b) {
                    return a + b; // sum
                }
                int main(void) { printf("%d\\n", add(1, 2)); return NULL == 0; }
                """,
            expectations: [
                .init("#include", .keyword), .init("<stdio.h>", .string), .init("#define", .keyword),
                .init("/* comment */", .comment), .init("typedef", .keyword), .init("struct", .keyword),
                .init("int", .type), .init("add", .function), .init("return", .keyword), .init("// sum", .comment),
                .init("\"%d", .string), .init("1", after: "add(", .number), .init("printf", .function),
                .init("x", after: "int ", .property),
            ]),
        Fixture(
            language: "cpp",
            source: """
                #include <vector>
                namespace app {
                template <typename T>
                class Box : public Base {
                public:
                    explicit Box(T value) : value_(value) {}
                    auto get() const -> T { return value_; }
                private:
                    T value_;
                };
                }
                int main() { std::vector<int> v{1, 2}; auto s = R"(raw)"; return v.size() > 0 ? 0 : 1; }
                """,
            expectations: [
                .init("namespace", .keyword), .init("template", .keyword), .init("typename", .keyword),
                .init("class", .keyword), .init("public", .keyword), .init("Box", .type), .init("const", .keyword),
                .init("return", .keyword), .init("std", .namespace), .init("auto", .type), .init("size", .function),
                .init("1", after: "{", .number), .init("private", .keyword),
            ]),
        Fixture(
            language: "objc",
            source: """
                #import <Foundation/Foundation.h>
                @interface Greeter : NSObject
                @property (nonatomic, copy) NSString *name;
                - (void)greet;
                @end

                @implementation Greeter
                - (void)greet {
                    NSLog(@"Hello %@", self.name); // say hi
                }
                @end
                """,
            expectations: [
                .init("#import", .keyword), .init("@interface", .keyword), .init("Greeter", .type),
                .init("NSObject", .type), .init("@property", .keyword), .init("\"Hello %@\"", .string),
                .init("// say hi", .comment), .init("@end", .keyword), .init("self", .variableBuiltin),
                .init("NSLog", .function),
            ]),
        Fixture(
            language: "csharp",
            source: """
                using System;
                namespace App;
                // comment
                public sealed class Greeter : IGreeter
                {
                    private readonly string _name = "x";
                    public int Count { get; set; } = 42;
                    public async Task<string> Greet(string who) => await Task.FromResult($"Hi {who}");
                }
                """,
            expectations: [
                .init("using", .keyword), .init("namespace", .keyword), .init("// comment", .comment),
                .init("public", .keyword), .init("class", .keyword), .init("Greeter", .type), .init("string", .type),
                .init("\"x\"", .string), .init("42", .number), .init("Greet", after: "Task<string> ", .function), .init("get", .keyword),
                .init("async", .keyword),
            ]),
        Fixture(
            language: "java",
            source: """
                package app;
                import java.util.List;
                /** Docs. */
                public class Main extends Base implements Runnable {
                    private static final int MAX = 10;
                    @Override
                    public void run() { System.out.println("hi" + MAX + true + null); }
                }
                """,
            expectations: [
                .init("package", .keyword), .init("import", .keyword), .init("/** Docs. */", .comment),
                .init("class", .keyword), .init("Main", .type), .init("MAX", .constant), .init("10", .number),
                .init("Override", .attribute), .init("run", .function),
                .init("\"hi\"", .string), .init("true", .constant), .init("null", .constant), .init("void", .type),
            ]),
        Fixture(
            language: "kotlin",
            source: """
                package app
                import kotlinx.coroutines.flow.Flow
                // comment
                data class User(val name: String, var age: Int = 0)
                fun greet(user: User): String {
                    val list = listOf(1, 2)
                    return "Hello ${user.name}" + list.size
                }
                """,
            expectations: [
                .init("import", .keyword), .init("// comment", .comment),
                .init("data", .keyword), .init("class", .keyword), .init("User", .type), .init("val", .keyword),
                .init("String", .type), .init("0", after: "Int = ", .number), .init("fun", .keyword), .init("greet", .function),
                .init("listOf", .function), .init("\"Hello ", .string), .init("return", .keyword),
            ]),
        Fixture(
            language: "php",
            source: """
                <!DOCTYPE html>
                <p>Hi</p>
                <?php
                namespace App;
                // comment
                function greet(string $name): string {
                    return "Hello {$name}" . PHP_EOL;
                }
                class User { public function __construct(private int $id = 1) {} }
                echo greet('world');
                ?>
                """,
            expectations: [
                .init("<?php", .tag), .init("namespace", .keyword), .init("// comment", .comment),
                .init("function", .keyword), .init("greet", .function), .init("$name", .variable),
                .init("return", .keyword), .init("class", .keyword), .init("User", .type), .init("1", .number),
                .init("'world'", .string), .init("echo", .keyword), .init("p", after: "<", .tag),
            ]),
        Fixture(
            language: "ruby",
            source: """
                # comment
                require "json"
                module App
                  class Greeter < Base
                    attr_reader :name
                    def initialize(name = "x")
                      @name = name
                    end
                    def greet = puts("Hello #{@name}", 42, nil, true)
                  end
                end
                """,
            expectations: [
                .init("# comment", .comment), .init("require", .function), .init("\"json\"", .string),
                .init("module", .keyword), .init("App", .type), .init("class", .keyword), .init(":name", .constant),
                .init("def", .keyword), .init("initialize", .function), .init("@name", .property), .init("end", .keyword),
                .init("42", .number), .init("nil", .constant), .init("true", .constant),
            ]),
        Fixture(
            language: "lua",
            source: """
                -- comment
                local M = {}
                function M.greet(name)
                  if name == nil then return "hi" end
                  for i = 1, 10 do print(i) end
                  return string.format("Hello %s", name)
                end
                return M
                """,
            expectations: [
                .init("-- comment", .comment), .init("local", .keyword), .init("function", .keyword),
                .init("greet", .function), .init("if", .keyword), .init("nil", .constant), .init("\"hi\"", .string),
                .init("1", after: "i = ", .number), .init("print", .function), .init("end", .keyword),
            ]),
        Fixture(
            language: "scss",
            source: """
                // comment
                $gap: 4px;
                @mixin card($radius) { border-radius: $radius; }
                .card {
                  @include card(2px);
                  &:hover { color: darken(#fff, 10%); }
                  .title { margin: $gap * 2; }
                }
                """,
            expectations: [
                .init("// comment", .comment), .init("$gap", .variable), .init("4", .number), .init("@mixin", .keyword),
                .init("@include", .keyword), .init("card", after: ".", .property), .init("hover", .attribute),
                .init("color", .property), .init("darken", .function), .init("border-radius", .property),
            ]),
        Fixture(
            language: "less",
            source: """
                // comment
                .card {
                  color: red;
                  .title { margin: 0 auto; }
                }
                """,
            expectations: [
                .init("// comment", .comment), .init("card", .property), .init("color", .property),
                .init("title", .property), .init("0", .number),
            ]),
        Fixture(
            language: "sass",
            source: """
                // comment
                $gap: 4px
                .card
                  color: red
                  margin: $gap
                @mixin round($r)
                  border-radius: $r
                """,
            expectations: [
                .init("// comment", .comment), .init("card", .type), .init("color", .property),
                .init("@mixin", .keyword), .init("border-radius", .property),
            ]),
        Fixture(
            language: "vue",
            source: """
                <template>
                  <div :class="{ active: isActive }" @click="toggle">{{ message.toUpperCase() }}</div>
                </template>

                <script setup lang="ts">
                const message: string = "hi";
                </script>

                <style scoped>
                .active { color: red; }
                </style>
                """,
            expectations: [
                .init("template", .tag), .init("div", .tag), .init("message", after: "{{ ", .variable),
                .init("toUpperCase", .function), .init("const", .keyword), .init("string", .type),
                .init("color", .property), .init("setup", .attribute), .init("{{", .stringSpecial),
            ]),
        Fixture(
            language: "svelte",
            source: """
                <script lang="ts">
                  let count: number = 0;
                </script>

                {#if count > 0}
                  <p class="x">{count}</p>
                {/if}

                <style>
                  p { color: red; }
                </style>
                """,
            expectations: [
                .init("let", .keyword), .init("number", .type), .init("if", after: "{#", .keyword), .init("p", after: "<", .tag),
                .init("class", .attribute), .init("color", .property), .init("script", .tag),
            ]),
        Fixture(
            language: "graphql",
            source: """
                # comment
                query GetUser($id: ID!) {
                  user(id: $id) @include(if: true) { name ...Fields }
                }
                type User implements Node { id: ID! name: String }
                enum Role { ADMIN USER }
                """,
            expectations: [
                .init("# comment", .comment), .init("query", .keyword), .init("GetUser", .function),
                .init("$id", .parameter), .init("ID", .type), .init("user", .property), .init("@", .attribute),
                .init("true", .constant), .init("type", .keyword), .init("User", after: "type ", .type),
                .init("ADMIN", .constant),
            ]),
        Fixture(
            language: "proto",
            source: """
                syntax = "proto3";
                package app.v1;
                // comment
                message User {
                  string name = 1;
                  repeated int32 ids = 2;
                }
                service Users { rpc Get(User) returns (User); }
                """,
            expectations: [
                .init("syntax", .keyword), .init("\"proto3\"", .constant), .init("package", .keyword),
                .init("// comment", .comment), .init("message", .keyword), .init("User", .type), .init("string", .type),
                .init("1", after: "name = ", .number), .init("repeated", .keyword), .init("service", .keyword), .init("rpc", .keyword),
            ]),
        Fixture(
            language: "terraform",
            source: """
                # comment
                resource "aws_s3_bucket" "logs" {
                  bucket = "my-logs-${var.env}"
                  count  = 2
                  tags   = { Name = "logs" }
                }
                variable "env" { default = true }
                """,
            expectations: [
                .init("# comment", .comment), .init("resource", .type), .init("\"aws_s3_bucket\"", .string),
                .init("bucket", after: "{\n  ", .property), .init("var", .variableBuiltin), .init("2", .number),
                .init("true", .constant), .init("${", .stringSpecial),
            ]),
        Fixture(
            language: "hcl",
            source: """
                // comment
                job "web" {
                  count = 3
                  env = upper("x")
                }
                """,
            expectations: [
                .init("// comment", .comment), .init("job", .type), .init("count", .property), .init("3", .number),
                .init("upper", .function), .init("\"x\"", .string),
            ]),
        Fixture(
            language: "zig",
            source: """
                const std = @import("std");
                // comment
                pub fn main() !void {
                    const x: u32 = 42;
                    std.debug.print("{d}\\n", .{x});
                }
                """,
            expectations: [
                .init("const", .keyword), .init("@import", .keyword), .init("\"std\"", .string),
                .init("// comment", .comment), .init("pub", .keyword), .init("fn", .keyword), .init("main", .function),
                .init("u32", .type), .init("42", .number), .init("print", .function),
            ]),
        Fixture(
            language: "dart",
            source: """
                import 'package:flutter/material.dart';
                // comment
                class Counter extends StatelessWidget {
                  final int count = 0;
                  @override
                  Widget build(BuildContext context) => Text('Count: $count');
                }
                """,
            expectations: [
                .init("import", .keyword), .init("'package:flutter/material.dart'", .string),
                .init("// comment", .comment), .init("class", .keyword), .init("Counter", .type), .init("final", .keyword),
                .init("0", .number), .init("build", .function), .init("Widget", .type),
            ]),
        Fixture(
            language: "powershell",
            source: """
                # comment
                function Get-Greeting {
                    param([string]$Name = "World")
                    if ($Name -eq "") { return $null }
                    Write-Output "Hello $Name"
                }
                $items = @(1, 2, 3)
                """,
            expectations: [
                .init("# comment", .comment), .init("function", .keyword), .init("Get-Greeting", .function),
                .init("param", .keyword), .init("$Name", .variable), .init("\"World\"", .string), .init("if", .keyword),
                .init("return", .keyword), .init("Write-Output", .function),
            ]),
        Fixture(
            language: "metal",
            source: """
                #include <metal_stdlib>
                using namespace metal;
                // comment
                struct VertexOut { float4 position [[position]]; };
                float4 tint(float4 color) { return color * 2.0; }
                """,
            expectations: [
                .init("#include", .keyword), .init("using", .keyword), .init("namespace", .keyword),
                .init("// comment", .comment), .init("struct", .keyword), .init("VertexOut", .type),
                .init("float4", .type), .init("tint", .function), .init("return", .keyword), .init("2.0", .number),
            ]),
        Fixture(
            language: "glsl",
            source: """
                #version 330 core
                // comment
                uniform vec4 color;
                in vec2 uv;
                out vec4 fragColor;
                void main() {
                    fragColor = texture(tex, uv) * color + vec4(0.5);
                    gl_Position = vec4(1.0);
                }
                """,
            expectations: [
                .init("#version", .keyword), .init("// comment", .comment), .init("uniform", .keyword),
                .init("vec4", .type), .init("in", .keyword), .init("main", .function), .init("texture", .function),
                .init("0.5", .number), .init("gl_Position", .variableBuiltin),
            ]),
        Fixture(
            language: "cmake",
            source: """
                # comment
                cmake_minimum_required(VERSION 3.20)
                project(QuickEdit LANGUAGES CXX)
                set(SOURCES main.cpp "util.cpp")
                if(APPLE)
                  add_executable(app ${SOURCES})
                endif()
                """,
            expectations: [
                .init("# comment", .comment), .init("cmake_minimum_required", .function), .init("VERSION", .constant),
                .init("\"util.cpp\"", .string), .init("if", .keyword), .init("endif", .keyword),
                .init("add_executable", .function), .init("SOURCES", after: "${", .variable),
            ]),
        Fixture(
            language: "nix",
            source: """
                # comment
                { pkgs ? import <nixpkgs> {} }:
                let
                  version = "1.0";
                in pkgs.stdenv.mkDerivation {
                  pname = "app";
                  inherit version;
                  doCheck = true;
                }
                """,
            expectations: [
                .init("# comment", .comment), .init("let", .keyword), .init("in", after: "\n", .keyword),
                .init("\"1.0\"", .string), .init("inherit", .keyword), .init("true", .constant),
                .init("<nixpkgs>", .string), .init("mkDerivation", .function),
            ]),
        Fixture(
            language: "spicedb",
            source: """
                // comment
                definition user {}

                definition document {
                    relation viewer: user | user:*
                    permission view = viewer + owner->view
                }

                caveat is_weekday(day string) { day != "saturday" }
                """,
            expectations: [
                .init("// comment", .comment), .init("definition", .keyword), .init("user", after: "definition ", .type),
                .init("relation", .keyword), .init("permission", .keyword), .init("caveat", .keyword),
            ]),
    ]

    @Test("fixtures highlight with the expected kinds", arguments: fixtures)
    func fixture(_ fixture: Fixture) {
        HighlightTests().fixture(fixture)
    }

    @Test("Xcode .xcconfig")
    func xcconfig() {
        let h = Highlighted(
            """
            // Base settings
            #include "Shared.xcconfig"
            #include? "Local.xcconfig"
            SWIFT_VERSION = 6.0
            OTHER_LDFLAGS[sdk=iphoneos*][arch=*] = $(inherited) -ObjC // linker
            ENABLE_TESTABILITY = YES
            PRODUCT_NAME = $(TARGET_NAME:c99extidentifier)
            """, language: "xcconfig")
        #expect(h.kind(of: "// Base settings") == .comment, "\(h.dump)")
        #expect(h.kind(of: "#include") == .keyword)
        #expect(h.kind(of: "#include?") == .keyword)
        #expect(h.kind(of: "\"Shared.xcconfig\"") == .string)
        #expect(h.kind(of: "SWIFT_VERSION") == .property)
        #expect(h.kind(of: "6.0") == .number)
        #expect(h.kind(of: "[sdk=iphoneos*]") == .attribute)
        #expect(h.kind(of: "=", after: "[arch=*] ") == .operator)
        #expect(h.kind(of: "$(inherited)") == .variableBuiltin)
        #expect(h.kind(of: "// linker") == .comment)
        #expect(h.kind(of: "YES") == .constant)
        #expect(h.kind(of: "$(TARGET_NAME:c99extidentifier)") == .variable)
    }

    @Test("Apple .strings")
    func appleStrings() {
        let h = Highlighted(
            """
            /* Localizable.strings
               App */
            // Greeting
            "greeting" = "Hello, %@! You have %1$d new\\nmessages.";
            "quote" = "Say \\"hi\\"";
            plainKey = "100%% done";
            """, language: "strings")
        #expect(h.kind(of: "/* Localizable.strings\n   App */") == .comment, "\(h.dump)")
        #expect(h.kind(of: "// Greeting") == .comment)
        #expect(h.kind(of: "\"greeting\"") == .property)
        #expect(h.kind(of: "=") == .operator)
        #expect(h.kind(of: "\"Hello, ") == .string)
        #expect(h.kind(of: "%@") == .stringSpecial)
        #expect(h.kind(of: "%1$d") == .stringSpecial)
        #expect(h.kind(of: "\\n") == .stringSpecial)
        #expect(h.kind(of: "\\\"", after: "Say ") == .stringSpecial)
        #expect(h.kind(of: ";") == .punctuation)
        #expect(h.kind(of: "plainKey") == .property)
        #expect(h.kind(of: "%%") == .stringSpecial)
    }

    @Test("Xcode .pbxproj")
    func pbxproj() {
        let h = Highlighted(
            """
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tobjects = {
            /* Begin PBXBuildFile section */
            \t\tA1B2C3D4E5F6A7B8C9D0E1F2 /* main.swift in Sources */ = {isa = PBXBuildFile; fileRef = 0123456789ABCDEF01234567 /* main.swift */; };
            \t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Development";
            \t\tENABLE_BITCODE = NO;
            \t\tpath = Sources/App.swift;
            \t};
            }
            """, language: "pbxproj")
        #expect(h.kind(of: "// !$*UTF8*$!") == .comment, "\(h.dump)")
        #expect(h.kind(of: "archiveVersion") == .property)
        #expect(h.kind(of: "1", after: "archiveVersion = ") == .number)
        #expect(h.kind(of: "/* Begin PBXBuildFile section */") == .comment)
        #expect(h.kind(of: "A1B2C3D4E5F6A7B8C9D0E1F2") == .constant)
        #expect(h.kind(of: "/* main.swift in Sources */") == .comment)
        #expect(h.kind(of: "isa") == .property)
        #expect(h.kind(of: "PBXBuildFile", after: "isa = ") == .type)
        #expect(h.kind(of: "\"CODE_SIGN_IDENTITY[sdk=iphoneos*]\"") == .property)
        #expect(h.kind(of: "\"Apple Development\"") == .string)
        #expect(h.kind(of: "NO") == .constant)
        #expect(h.kind(of: "{") == .punctuation)
    }

    @Test("lexer state follows multi-line comments and strings across edits")
    func lexerEdits() {
        let language = LanguageRegistry.language(id: "strings")!
        let highlighter = SyntaxHighlighter(language: language)
        let text = NSMutableString(string: "\"a\" = \"b\";\n\"c\" = \"d\";\n\"e\" = \"f\";\n")
        highlighter.setText(text)
        _ = highlighter.tokens(in: NSRange(location: 0, length: text.length))
        // Open a block comment on the first line: everything after it becomes a comment.
        text.insert("/* ", at: 0)
        let changed = highlighter.applyEdit(replacing: NSRange(location: 0, length: 0), with: 3, in: text)
        #expect(changed.last?.upperBound == text.length)
        let tokens = highlighter.tokens(in: NSRange(location: 0, length: text.length))
        #expect(tokens.map(\.kind) == [.comment])
        #expect(tokens.first?.range == NSRange(location: 0, length: text.length))
        let fresh = SyntaxHighlighter(language: language)
        fresh.setText(text.copy() as! NSString)
        #expect(tokens == fresh.tokens(in: NSRange(location: 0, length: text.length)))
    }

    @Test(".h headers by content", arguments: [
        ("#import <Foundation/Foundation.h>\n@interface A : NSObject\n@end\n", "objc"),
        ("NS_ASSUME_NONNULL_BEGIN\n@protocol P\n@end\n", "objc"),
        ("#pragma once\n#include <vector>\nnamespace app {\nclass A {};\n}\n", "cpp"),
        ("template <typename T>\nT max(T a, T b);\n", "cpp"),
        ("struct A {\npublic:\n  int x;\n};\n", "cpp"),
        ("void f(std::string s);\n", "cpp"),
        ("#ifndef A_H\n#define A_H\n#include <string.h>\n#ifdef __cplusplus\nextern \"C\" {\n#endif\nint classify(int x);\n", "c"),
        ("/* class Foo is not C++ here */\nint x;\n", "c"),
    ])
    func headers(content: String, expected: String) {
        #expect(LanguageRegistry.detect(fileName: "a.h", firstLine: nil, content: content).id == expected)
    }

    @Test("detection")
    func detection() {
        func detect(_ name: String) -> String { LanguageRegistry.detect(fileName: name, firstLine: nil).id }
        let cases: [(String, String)] = [
            ("a.c", "c"), ("a.h", "c"), ("a.cpp", "cpp"), ("a.cc", "cpp"), ("a.cxx", "cpp"), ("a.hpp", "cpp"),
            ("a.hh", "cpp"), ("a.hxx", "cpp"), ("a.ipp", "cpp"), ("a.inl", "cpp"), ("a.m", "objc"), ("a.mm", "objc"),
            ("a.cs", "csharp"), ("a.csx", "csharp"), ("A.java", "java"), ("a.kt", "kotlin"),
            ("build.gradle.kts", "kotlin"), ("a.php", "php"), ("a.rb", "ruby"), ("app.gemspec", "ruby"),
            ("Gemfile", "ruby"), ("Rakefile", "ruby"), ("Podfile", "ruby"), ("Brewfile", "ruby"), ("a.lua", "lua"),
            ("a.scss", "scss"), ("a.sass", "sass"), ("a.less", "less"), ("App.vue", "vue"),
            ("App.svelte", "svelte"), ("a.graphql", "graphql"), ("a.gql", "graphql"), ("a.proto", "proto"),
            ("main.tf", "terraform"), ("prod.tfvars", "terraform"), ("a.hcl", "hcl"), ("a.zig", "zig"),
            ("a.dart", "dart"), ("a.ps1", "powershell"), ("a.psm1", "powershell"), ("a.metal", "metal"),
            ("a.glsl", "glsl"), ("a.vert", "glsl"), ("a.frag", "glsl"), ("CMakeLists.txt", "cmake"),
            ("a.cmake", "cmake"), ("Base.xcconfig", "xcconfig"), ("Localizable.strings", "strings"),
            ("project.pbxproj", "pbxproj"), ("default.nix", "nix"), ("schema.zed", "spicedb"),
            ("schema.zaml", "yaml"),
        ]
        for (name, expected) in cases {
            #expect(detect(name) == expected, "\(name)")
        }
        #expect(LanguageRegistry.detect(fileName: "x", firstLine: "#!/usr/bin/env ruby").id == "ruby")
        #expect(LanguageRegistry.detect(fileName: "x", firstLine: "#!/usr/bin/env pwsh").id == "powershell")
        #expect(LanguageRegistry.detect(fileName: "x", firstLine: nil, content: "#!/usr/bin/env php\n<?php").id == "php")
        #expect(LanguageRegistry.language(forFenceInfo: "c++")?.id == "cpp")
        #expect(LanguageRegistry.language(forFenceInfo: "objective-c")?.id == "objc")
        #expect(LanguageRegistry.language(forFenceInfo: "c#")?.id == "csharp")
    }

    @Test("folds in the new languages")
    func folds() {
        let samples: [(String, String, [ClosedRange<Int>])] = [
            ("c", "int f(void) {\n  return 1;\n}\n", [0...2]),
            ("cpp", "namespace a {\nint x;\n}\n", [0...2]),
            ("objc", "@interface A : NSObject\n- (void)f;\n@end\n", [0...2]),
            ("csharp", "class A\n{\n    void F() {\n        G();\n    }\n}\n", [1...5, 2...4]),
            ("java", "class A {\n  void f() {\n    g();\n  }\n}\n", [0...4, 1...3]),
            ("kotlin", "class A {\n  fun f() {\n    g()\n  }\n}\n", [0...4, 1...3]),
            ("php", "<?php\nfunction f() {\n  return 1;\n}\n", [1...3]),
            ("ruby", "def f\n  1\nend\n", [0...2]),
            ("lua", "function f()\n  return 1\nend\n", [0...2]),
            ("scss", ".a {\n  .b {\n    c: d;\n  }\n}\n", [0...4, 1...3]),
            ("graphql", "query {\n  a\n}\n", [0...2]),
            ("proto", "message A {\n  string b = 1;\n}\n", [0...2]),
            ("terraform", "resource \"a\" \"b\" {\n  c = 1\n}\n", [0...2]),
            ("zig", "fn f() void {\n    g();\n}\n", [0...2]),
            ("dart", "class A {\n  int b = 0;\n}\n", [0...2]),
            ("cmake", "function(f)\n  message(x)\nendfunction()\n", [0...2]),
            ("nix", "{\n  a = 1;\n}\n", [0...2]),
            ("vue", "<template>\n  <p>x</p>\n</template>\n", [0...2]),
            ("svelte", "{#if a}\n  <p>x</p>\n{/if}\n", [0...2]),
        ]
        for (language, source, expected) in samples {
            let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: language)!)
            highlighter.setText(source as NSString)
            let lines = highlighter.foldRanges().map { $0.startLine...$0.endLine }
            #expect(lines == expected, "\(language): \(lines)")
        }
    }
}
