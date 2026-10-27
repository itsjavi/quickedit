#!/usr/bin/env swift
// Draws QuickEdit's Icon Composer icon: the layer PNGs (AppIcon.icon/Assets/*.png, on a 1024 pt canvas) and the
// icon.json that stacks them over a gradient fill with Liquid Glass, in light and dark. macOS derives the tinted and
// clear styles from these; check all six with Icon Composer's `ictool --rendition` (Default, Dark, Tinted*, Clear*).
// Usage: swift scripts/make-icon.swift [--concept 1-4] [Resources/AppIcon.icon]   (or `make icon`)
//
// The concepts live here so each one stays reproducible; `defaultConcept` is the shipped icon.
//   1. Spark braces: white `{ }` with a yellow lightning bolt between them, on electric violet.
//   2. Code pane: a dark editor pane with syntax-colored, indented code and a bright caret, on sunset orange.
//   3. Dash page: a forward-leaning page with a coral `</>` tag and speed streaks behind it, on white (light)
//      or black (dark), so the icon follows the system appearance.
//   4. Code page: an upright source file with a folded corner, the coral `</>` and faint indented code lines,
//      on the same neutral white/black field.
//
// Unlike NoteMD's script, this one also writes icon.json, because each concept has its own fill and layers.
// A tweak made in Icon Composer is overwritten by the next redraw: port it into the constants below.
import AppKit

let defaultConcept = 3

var arguments = Array(CommandLine.arguments.dropFirst())
var conceptNumber = defaultConcept
if let i = arguments.firstIndex(of: "--concept") {
    guard i + 1 < arguments.count, let n = Int(arguments[i + 1]), (1...4).contains(n) else {
        FileHandle.standardError.write(Data("usage: make-icon.swift [--concept 1-4] [AppIcon.icon]\n".utf8))
        exit(64)
    }
    conceptNumber = n
    arguments.removeSubrange(i...(i + 1))
}
let output = arguments.first ?? "Resources/AppIcon.icon"

// MARK: - Drawing helpers

let canvas: CGFloat = 1024
// Artwork fills the middle ~82% of the canvas, bold like the system apps' icons, leaving the mask's corners, the
// glass edge and the shadow a little room.
let artFraction: CGFloat = 0.82
let art = NSRect(x: canvas * (1 - artFraction) / 2, y: canvas * (1 - artFraction) / 2,
                 width: canvas * artFraction, height: canvas * artFraction)
let unit = art.width

func color(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

/// One layer on a transparent canvas. Draw flat shapes only: the system adds glass, highlights and shadows.
func layer(_ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Fills a path with a gentle top-to-bottom two-stop gradient. AppKit's origin is bottom-left.
func gradientFill(_ path: NSBezierPath, _ top: String, _ bottom: String, alpha: CGFloat = 1) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [color(top, alpha), color(bottom, alpha)])!.draw(in: path.bounds, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

/// The filled outline of a stroked centerline, so strokes can take a gradient like any other shape.
func outline(_ centerline: NSBezierPath, width: CGFloat) -> NSBezierPath {
    NSBezierPath(cgPath: centerline.cgPath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round,
                                                miterLimit: 10))
}

/// A closed polygon with every corner rounded by `radius`.
func roundedPolygon(_ points: [NSPoint], radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let last = points[points.count - 1]
    path.move(to: NSPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
    for (i, point) in points.enumerated() {
        path.appendArc(from: point, to: points[(i + 1) % points.count], radius: radius)
    }
    path.close()
    return path
}

func pill(_ r: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
}

/// Mirrors a path left-to-right around the vertical line x = `axis`.
func mirrored(_ path: NSBezierPath, axis: CGFloat) -> NSBezierPath {
    let t = AffineTransform(m11: -1, m12: 0, m21: 0, m22: 1, tX: 2 * axis, tY: 0)
    let copy = path.copy() as! NSBezierPath
    copy.transform(using: t)
    return copy
}

/// Leans a path forward (italic) by `slant` per unit of height, around the horizontal line y = `axis`.
func leaned(_ path: NSBezierPath, slant: CGFloat, axis: CGFloat) -> NSBezierPath {
    let t = AffineTransform(m11: 1, m12: 0, m21: slant, m22: 1, tX: -slant * axis, tY: 0)
    let copy = path.copy() as! NSBezierPath
    copy.transform(using: t)
    return copy
}

/// A lightning bolt filling `r`: a top bar slanting down-left, a shelf, then a long spike to the bottom tip.
func boltPath(in r: NSRect, radius: CGFloat) -> NSBezierPath {
    let shape: [(CGFloat, CGFloat)] = [
        (0.30, 1.00), (0.80, 1.00), (0.56, 0.60), (0.92, 0.60), (0.24, 0.00), (0.40, 0.44), (0.08, 0.44),
    ]
    return roundedPolygon(shape.map { NSPoint(x: r.minX + r.width * $0.0, y: r.minY + r.height * $0.1) },
                          radius: radius)
}

/// Centerline of a `{` that fills `r` (mirror it for `}`); stroke it with round caps and joins.
func braceCenterline(in r: NSRect) -> NSBezierPath {
    let stem = r.midX
    let curl = r.width / 2  // radius of the end curls and of the nub's two halves
    let k: CGFloat = 0.552 * curl  // cubic handle length for a quarter circle
    let m = r.midY
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.maxX, y: r.maxY))
    p.curve(to: NSPoint(x: stem, y: r.maxY - curl), controlPoint1: NSPoint(x: r.maxX - k, y: r.maxY),
            controlPoint2: NSPoint(x: stem, y: r.maxY - curl + k))
    p.line(to: NSPoint(x: stem, y: m + curl))
    p.curve(to: NSPoint(x: r.minX, y: m), controlPoint1: NSPoint(x: stem, y: m + curl - k),
            controlPoint2: NSPoint(x: r.minX + k, y: m))
    p.curve(to: NSPoint(x: stem, y: m - curl), controlPoint1: NSPoint(x: r.minX + k, y: m),
            controlPoint2: NSPoint(x: stem, y: m - curl + k))
    p.line(to: NSPoint(x: stem, y: r.minY + curl))
    p.curve(to: NSPoint(x: r.maxX, y: r.minY), controlPoint1: NSPoint(x: stem, y: r.minY + curl - k),
            controlPoint2: NSPoint(x: r.maxX - k, y: r.minY))
    return p
}

// MARK: - Concepts

struct Concept {
    /// Background gradient stops, top-left to bottom-right, as hex.
    let fill: [String]
    let darkFill: [String]
    /// Listed front to back, as in icon.json: the first layer is drawn on top.
    let layers: [(name: String, draw: () -> Void)]
    /// Per-appearance colors that replace a layer's own (top-to-bottom gradient stops), keyed by layer name.
    /// The layer's PNG then only supplies its shape.
    var layerFills: [String: (light: [String], dark: [String])] = [:]
}

/// 1. Spark braces: code (`{ }`) plus speed (a bolt), the whole app in one glyph that survives 16 pt.
func sparkBraces() -> Concept {
    let braceSize = NSSize(width: unit * 0.22, height: unit * 0.80)
    let braceStroke = unit * 0.09
    let braceGap = unit * 0.46  // between the two braces' centerline boxes, where the bolt sits
    let boltSize = NSSize(width: unit * 0.42, height: unit * 0.68)
    let white = ("#FFFFFF", "#DCD5FF"), yellow = ("#FFE96B", "#FFB31F")

    let left = NSRect(x: art.midX - braceGap / 2 - braceSize.width, y: art.midY - braceSize.height / 2,
                      width: braceSize.width, height: braceSize.height)
    let right = left.offsetBy(dx: braceSize.width + braceGap, dy: 0)
    let bolt = NSRect(x: art.midX - boltSize.width / 2, y: art.midY - boltSize.height / 2,
                      width: boltSize.width, height: boltSize.height)
    return Concept(
        fill: ["#7C5CFF", "#2A1484"], darkFill: ["#4A33B5", "#140A44"],
        layers: [
            ("bolt", { gradientFill(boltPath(in: bolt, radius: unit * 0.02), yellow.0, yellow.1) }),
            ("braces", {
                let shape = outline(braceCenterline(in: left), width: braceStroke)
                shape.append(mirrored(outline(braceCenterline(in: right), width: braceStroke), axis: right.midX))
                gradientFill(shape, white.0, white.1)
            }),
        ]
    )
}

/// 2. Code pane: what the window shows, indented syntax-colored code with the caret mid-edit.
func codePane() -> Concept {
    let paneSize = NSSize(width: unit * 1.0, height: unit * 0.78)
    let paneRadius = paneSize.height * 0.16
    let inset = unit * 0.11
    let indent = unit * 0.11
    let lineHeight = unit * 0.085
    let lineGap = unit * 0.075
    let tokenGap = unit * 0.035
    // One row per line of code: indent level and (width, color) tokens.
    let rows: [(Int, [(CGFloat, String)])] = [
        (0, [(0.18, "#FF6FB1"), (0.28, "#ECEEFA"), (0.12, "#62D8FF")]),
        (1, [(0.14, "#62D8FF"), (0.36, "#FFD65C")]),
        (1, [(0.30, "#86E58F")]),
        (0, [(0.16, "#ECEEFA")]),
    ]
    let caretRow = 2
    let caretSize = NSSize(width: unit * 0.05, height: lineHeight * 1.8)

    let pane = NSRect(x: art.midX - paneSize.width / 2, y: art.midY - paneSize.height / 2,
                      width: paneSize.width, height: paneSize.height)
    let blockHeight = CGFloat(rows.count) * lineHeight + CGFloat(rows.count - 1) * lineGap
    let top = pane.midY + blockHeight / 2
    func rowY(_ i: Int) -> CGFloat { top - CGFloat(i) * (lineHeight + lineGap) - lineHeight }
    func rowEnd(_ i: Int) -> CGFloat {
        let (level, tokens) = rows[i]
        return pane.minX + inset + CGFloat(level) * indent
            + tokens.reduce(0) { $0 + unit * $1.0 } + CGFloat(tokens.count - 1) * tokenGap
    }
    let caret = NSRect(x: rowEnd(caretRow) + tokenGap, y: rowY(caretRow) + lineHeight / 2 - caretSize.height / 2,
                       width: caretSize.width, height: caretSize.height)
    return Concept(
        fill: ["#FF9A3D", "#E8336B"], darkFill: ["#C9652F", "#93264F"],
        layers: [
            ("caret", {
                let bar = NSBezierPath(roundedRect: caret, xRadius: caret.width * 0.3, yRadius: caret.width * 0.3)
                gradientFill(bar, "#FFFFFF", "#E6F8FF")
            }),
            ("code", {
                for (i, (level, tokens)) in rows.enumerated() {
                    var x = pane.minX + inset + CGFloat(level) * indent
                    for (width, hex) in tokens {
                        color(hex).setFill()
                        pill(NSRect(x: x, y: rowY(i), width: unit * width, height: lineHeight)).fill()
                        x += unit * width + tokenGap
                    }
                }
            }),
            ("pane", {
                gradientFill(NSBezierPath(roundedRect: pane, xRadius: paneRadius, yRadius: paneRadius),
                             "#30344D", "#1B1E30")
            }),
        ]
    )
}

// Shared by concepts 3 and 4: a neutral field, white in light mode and black in dark mode, with a coral `</>`.
// icon.json inverts the page against the field: charcoal on white, near-white on black.
let neutralFill = (light: ["#FFFFFF", "#ECEDF1"], dark: ["#2A2B30", "#050506"])
let paper = (light: ["#3B3E46", "#1A1B20"], dark: ["#FFFFFF", "#DDE1E8"])
let coral = ("#FF7A45", "#F2386E")

/// Centerline of a `</>` tag filling `r` (the slash overshoots a little); stroke it with round caps and joins.
func tagCenterline(in r: NSRect) -> NSBezierPath {
    let chevron = r.width * 0.26
    let lean = r.width * 0.10
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.minX + chevron, y: r.maxY))
    p.line(to: NSPoint(x: r.minX, y: r.midY))
    p.line(to: NSPoint(x: r.minX + chevron, y: r.minY))
    p.move(to: NSPoint(x: r.maxX - chevron, y: r.maxY))
    p.line(to: NSPoint(x: r.maxX, y: r.midY))
    p.line(to: NSPoint(x: r.maxX - chevron, y: r.minY))
    p.move(to: NSPoint(x: r.midX - lean, y: r.minY - r.height * 0.06))
    p.line(to: NSPoint(x: r.midX + lean, y: r.maxY + r.height * 0.06))
    return p
}

/// 3. Dash page: a file whipping forward with a `</>` tag, speed streaks trailing behind it.
func dashPage() -> Concept {
    let pageSize = NSSize(width: unit * 0.60, height: unit * 0.84)
    let pageRadius = pageSize.width * 0.14
    let slant: CGFloat = 0.16
    let tagSize = NSSize(width: unit * 0.42, height: unit * 0.31)
    let tagStroke = unit * 0.085
    let streakHeight = unit * 0.08
    let streaks: [(y: CGFloat, length: CGFloat)] = [(0.70, 0.32), (0.50, 0.44), (0.30, 0.26)]  // y in page heights
    let streak = ("#FFA27A", "#FF6F6A")  // coral-peach: reads on both the white and the black field

    // A little left of the right edge, so page and streaks sit centred as a whole.
    let page = NSRect(x: art.maxX - pageSize.width - unit * 0.09, y: art.midY - pageSize.height / 2,
                      width: pageSize.width, height: pageSize.height)
    let tag = NSRect(x: page.midX - tagSize.width / 2, y: page.midY - tagSize.height / 2,
                     width: tagSize.width, height: tagSize.height)
    return Concept(
        fill: neutralFill.light, darkFill: neutralFill.dark,
        layers: [
            ("tag", {
                gradientFill(leaned(outline(tagCenterline(in: tag), width: tagStroke), slant: slant, axis: page.midY),
                             coral.0, coral.1)
            }),
            ("page", {
                let shape = NSBezierPath(roundedRect: page, xRadius: pageRadius, yRadius: pageRadius)
                gradientFill(leaned(shape, slant: slant, axis: page.midY), paper.dark[0], paper.dark[1])
            }),
            ("streaks", {
                for s in streaks {
                    let y = page.minY + page.height * s.y - streakHeight / 2
                    // Tuck each streak's right end under the leaning page's left edge.
                    let edge = page.minX + slant * (y + streakHeight / 2 - page.midY) + unit * 0.06
                    gradientFill(pill(NSRect(x: edge - unit * s.length, y: y, width: unit * s.length,
                                             height: streakHeight)), streak.0, streak.1)
                }
            }),
        ],
        layerFills: ["page": paper]
    )
}

/// 4. Code page: an upright source file (folded corner) with the `</>` tag over a few indented code lines.
func codePage() -> Concept {
    let pageSize = NSSize(width: unit * 0.74, height: unit * 0.94)
    let pageRadius = unit * 0.07
    let foldSize = unit * 0.22
    let tagSize = NSSize(width: unit * 0.38, height: unit * 0.25)
    let tagStroke = unit * 0.08
    let tagToCode = unit * 0.10
    let lineHeight = unit * 0.05
    let lineGap = unit * 0.05
    let lines: [(indent: CGFloat, width: CGFloat)] = [(0, 0.40), (0.08, 0.32), (0, 0.20)]  // in units
    let ink = "#A3AAB6"  // faint grey code: present on the charcoal (light) and the white (dark) page
    let fold = (light: ["#5A5E68", "#41444C"], dark: ["#DADDE3", "#BFC5CE"])

    let page = NSRect(x: art.midX - pageSize.width / 2, y: art.midY - pageSize.height / 2,
                      width: pageSize.width, height: pageSize.height)
    // Tag and code form one block, centered a little low because the fold takes the top-right corner.
    let codeHeight = CGFloat(lines.count) * lineHeight + CGFloat(lines.count - 1) * lineGap
    let blockTop = page.midY - unit * 0.03 + (tagSize.height + tagStroke + tagToCode + codeHeight) / 2
    let tag = NSRect(x: page.midX - tagSize.width / 2, y: blockTop - tagStroke / 2 - tagSize.height,
                     width: tagSize.width, height: tagSize.height)
    let lineLeft = tag.minX - tagStroke / 2
    let firstLineTop = tag.minY - tagStroke / 2 - tagToCode
    return Concept(
        fill: neutralFill.light, darkFill: neutralFill.dark,
        layers: [
            ("tag", { gradientFill(outline(tagCenterline(in: tag), width: tagStroke), coral.0, coral.1) }),
            ("code", {
                color(ink).setFill()
                for (i, line) in lines.enumerated() {
                    let y = firstLineTop - lineHeight - CGFloat(i) * (lineHeight + lineGap)
                    pill(NSRect(x: lineLeft + unit * line.indent, y: y, width: unit * line.width,
                                height: lineHeight)).fill()
                }
            }),
            ("fold", {
                let corner = [NSPoint(x: page.maxX - foldSize, y: page.maxY),
                              NSPoint(x: page.maxX - foldSize, y: page.maxY - foldSize),
                              NSPoint(x: page.maxX, y: page.maxY - foldSize)]
                gradientFill(roundedPolygon(corner, radius: pageRadius * 0.4), fold.dark[0], fold.dark[1])
            }),
            ("page", {
                // The top-right corner is cut off where the fold turns over.
                let outlinePoints = [NSPoint(x: page.minX, y: page.minY), NSPoint(x: page.maxX, y: page.minY),
                                     NSPoint(x: page.maxX, y: page.maxY - foldSize),
                                     NSPoint(x: page.maxX - foldSize, y: page.maxY), NSPoint(x: page.minX, y: page.maxY)]
                gradientFill(roundedPolygon(outlinePoints, radius: pageRadius), paper.dark[0], paper.dark[1])
            }),
        ],
        layerFills: ["page": paper, "fold": fold]
    )
}

// MARK: - Output

let concept = [sparkBraces, codePane, dashPage, codePage][conceptNumber - 1]()

// icon.json is built as lines in the shape and formatting Icon Composer and oxfmt produce (keys sorted,
// 2-space indent), so a redraw doesn't churn the diff.

func indented(_ lines: [String], by spaces: Int) -> [String] {
    lines.map { String(repeating: " ", count: spaces) + $0 }
}

/// Appends a comma to the last line, for every entry but the last of an object or array.
func comma(_ lines: [String]) -> [String] {
    lines.dropLast() + [lines.last! + ","]
}

/// A `"fill-specializations"` entry: `light` for every appearance, `dark` for the dark one. Points are 0–1, y down.
func fillSpecializations(light: [String], dark: [String], from start: String, to stop: String) -> [String] {
    func value(_ stops: [String]) -> [String] {
        let colors = stops.map { hex -> String in
            let c = color(hex)
            return String(format: "\"extended-srgb:%.5f,%.5f,%.5f,1.00000\"", c.redComponent, c.greenComponent,
                          c.blueComponent)
        }
        return ["\"value\": {", "  \"linear-gradient\": ["] + indented(comma(Array(colors.dropLast())), by: 4)
            + ["    " + colors.last!, "  ],", "  \"orientation\": {", "    \"start\": \(start),",
               "    \"stop\": \(stop)", "  }", "}"]
    }
    return ["\"fill-specializations\": [", "  {"] + indented(value(light), by: 4) + ["  },", "  {",
            "    \"appearance\": \"dark\","] + indented(value(dark), by: 4) + ["  }", "]"]
}

let diagonal = (from: "{ \"x\": 0.2, \"y\": 0 }", to: "{ \"x\": 0.8, \"y\": 1 }")
let vertical = (from: "{ \"x\": 0.5, \"y\": 0 }", to: "{ \"x\": 0.5, \"y\": 1 }")

let layerEntries: [[String]] = concept.layers.map { layer in
    let fields = "\"glass\": true, \"image-name\": \"\(layer.name).png\", \"name\": \"\(layer.name)\""
    guard let fill = concept.layerFills[layer.name] else { return ["{ \(fields) }"] }
    return ["{"] + indented(comma(fillSpecializations(light: fill.light, dark: fill.dark, from: vertical.from,
                                                      to: vertical.to)), by: 2)
        + indented(["\"glass\": true,", "\"image-name\": \"\(layer.name).png\",", "\"name\": \"\(layer.name)\""], by: 2)
        + ["}"]
}

let manifestLines: [String] = ["{"]
    + indented(comma(fillSpecializations(light: concept.fill, dark: concept.darkFill, from: diagonal.from,
                                         to: diagonal.to)), by: 2)
    + ["  \"groups\": [", "    {", "      \"layers\": ["]
    + indented(layerEntries.dropLast().flatMap(comma) + layerEntries.last!, by: 8)
    + [
        "      ],",
        "      \"lighting\": \"individual\",",
        "      \"shadow\": { \"kind\": \"neutral\", \"opacity\": 0.35 },",
        "      \"specular\": true,",
        "      \"translucency\": { \"enabled\": true, \"value\": 0.2 }",
        "    }",
        "  ],",
        "  \"supported-platforms\": {",
        "    \"squares\": [\"macOS\"]",
        "  }",
        "}",
    ]
let manifest = manifestLines.joined(separator: "\n") + "\n"

let icon = URL(fileURLWithPath: output)
let assets = icon.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: assets)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
for (name, draw) in concept.layers {
    try layer(draw).representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent("\(name).png"))
}
try manifest.write(to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote concept \(conceptNumber) (\(concept.layers.count) layers) to \(icon.path)")
