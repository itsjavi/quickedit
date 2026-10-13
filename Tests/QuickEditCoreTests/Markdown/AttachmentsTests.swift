import Foundation
import QuickEditCore
import Testing

@Suite struct AttachmentsTests {
    @Test func assetsFolderIsNamedAfterTheFile() {
        let folder = Attachments.assetsFolder(forDocument: URL(fileURLWithPath: "/tmp/notes/docs.md"))
        #expect(folder.path == "/tmp/notes/docs.md.assets")
    }

    @Test func destinationIsRelativeAndEncoded() {
        let document = URL(fileURLWithPath: "/tmp/notes/my docs.md")
        let clip = URL(fileURLWithPath: "/private/tmp/notes/my docs.md.assets/voice-1.m4a")
        #expect(Attachments.destination(for: clip, fromDocument: document) == "my%20docs.md.assets/voice-1.m4a")
    }

    @Test func voiceLinkUsesTheEmbedSyntax() {
        #expect(Attachments.markdownLink(name: "Voice note", destination: "a.md.assets/v.m4a", kind: .audio) == "+[Voice note](a.md.assets/v.m4a)")
    }
}

@Suite struct MarkdownRendererTests {
    @Test func frontMatterBecomesAYAMLBlock() {
        let html = MarkdownRenderer.html(from: "---\ntitle: x\n---\n# Hi\n")
        #expect(html.contains("<pre class=\"front-matter\"><code class=\"language-yaml\">title: x</code></pre>"))
        #expect(html.contains("data-sourcepos=\"4:1-4:4\""))
    }

    @Test func audioEmbedsBecomePlayers() {
        let html = MarkdownRenderer.html(from: "+[Voice](a.md.assets/v.m4a)\n", options: .init(transcribeLinks: true))
        #expect(html.contains("<audio controls"))
        #expect(html.contains("quickedit-action:transcribe"))
    }

    @Test func rawHTMLScriptsAreFiltered() {
        let html = MarkdownRenderer.html(from: "<script>alert(1)</script>\n")
        #expect(!html.contains("<script>"))
    }
}
