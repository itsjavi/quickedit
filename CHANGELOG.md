# Changelog

Notable changes in each QuickEdit release, written from its commit messages by `scripts/changelog.sh`.

## 0.3.1 (2026-10-27)

### Features

- **editor:** hide the status bar (03701de)
- **documents:** reload files changed on disk safely (75e90a8)
- **icon:** dark page on the light icon, larger artwork (ad06d5a)

### Performance

- **editor:** lay out the whole file so fast scrolls don't wait (8d64bc8)
- **editor:** smooth fast scrolling (fa2223e)

## 0.3.0 (2026-10-14)

### Features

- **folders:** Material Icon Theme icons for files and folders (7f886fc)
- **syntax:** 29 more languages for 0.3.0 (TASK-37) (e5790c8)
- **types:** declare C#, Kotlin, Lua, SCSS/Less, Vue, Svelte, GraphQL, Protobuf, HCL, Zig, Dart, PowerShell, shaders, CMake, Xcode text files, Nix and SpiceDB (08ce61a)

### Fixes

- **editor:** wrapped lines fit beside the line numbers; sidebar names use the sidebar's width (f28465a)
- **documents:** typing after a save marks the file edited again; tabs show a dot for unsaved files (d22c766)

### Performance

- **folders:** cheaper new tabs (611a1ba)
- large files stay fast to open and edit (8619053)
- **folders:** file changes reload only what changed, in tabs on screen (7ef35d7)

## 0.2.0 (2026-10-13)

### Features

- **folders:** open folders with a file tree, Quick Open and file operations (6cbf753)
- **core:** folder listing and index, .gitignore rules and Quick Open fuzzy matcher (d165fb9)
- **web:** website at itsjavi.com/quickedit with Pages deployment and social card (0832d30)
- **quicklook:** view-based text preview so Finder's preview pane shows it (c2eadae)
- **editor:** code folding from the syntax package's fold regions (642e42e)
- **syntax:** Lumiose .stsx/.sjsx highlighting and fold ranges API (5b651d8)
- **editor:** folding infrastructure (hidden ranges, gutter arrows, commands) (238db55)
- **quicklook:** YAML, TOML, CSS and Lumiose previews, and text thumbnails (b9fd790)
- **settings:** File Types tab to make QuickEdit the default editor (d0a3521)
- **types:** declare Lumiose .stsx and .sjsx components (1243bee)
- taller icon motif, README screenshots, faster highlighting input (60987c2)
- **csv:** Table mode for CSV/TSV files (c7d86db)
- **syntax:** tree-sitter highlighting for 31 languages (277dc41)
- **core:** CSV/TSV parsing with exact cell ranges and minimal table edits (2ae2cf1)
- **types:** document types and imported UTIs for every supported file type (0eabf4c)
- **editor:** safe editing and a focus-safe Test build (bfc8301)
- **quicklook:** text preview extension for TypeScript .ts files (751f4d5)
- voice notes in Markdown files and the neutral page icon (ffe3eba)
- **preview:** Markdown and HTML preview with editor, split and preview modes (160e880)
- **core:** text safety modules for encodings, line endings, indentation, editorconfig, risky characters and plists (d2828f1)
- **app:** document windows with tabs, editor, line numbers and status bar (2a41fbd)

### Fixes

- **types:** import the Godot types so Macs without Godot recognise .gd, .tscn, .tres, .godot, .gdshader (eaf3540)
- **folding:** only one-character moves step over a fold; jumps into it open it (537f744)
- **editor:** keep the editor font and colours after Table edits in empty files (fdab059)
