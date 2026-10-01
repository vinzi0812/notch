import AppKit
import SwiftUI

/// An icon by name: an SF Symbol, or one of our own glyphs (names starting "glyph:") for things SF
/// Symbols has no symbol for, like a calculator. Glyphs are template images, so like a symbol they
/// take the color of wherever they're shown: the dimmed tab bar, an accent tile, a menu.
struct NotchIcon: View {
    let name: String
    /// A glyph's side; symbols size with the font like any other.
    var size: CGFloat = 14

    static let calculator = "glyph:calculator"

    var body: some View {
        if let glyph = Self.glyph(name) {
            Image(nsImage: glyph)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
        }
    }

    static func isGlyph(_ name: String) -> Bool { name.hasPrefix("glyph:") }

    static func glyph(_ name: String) -> NSImage? {
        switch name {
        case calculator: CalculatorGlyph.image
        default: nil
        }
    }
}

/// A calculator in the manner of SF Symbols: a rounded body, a display, and two rows of keys. Drawn
/// as vectors into a template image, so it's crisp at any size and tints like a symbol.
enum CalculatorGlyph {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: true) { rect in
            let s = rect.width
            NSColor.black.set()
            // Body: an outline, like the line weight of a regular symbol.
            let body = NSRect(x: s * 0.17, y: s * 0.05, width: s * 0.66, height: s * 0.90)
            let outline = NSBezierPath(roundedRect: body.insetBy(dx: s * 0.045, dy: s * 0.045), xRadius: s * 0.12, yRadius: s * 0.12)
            outline.lineWidth = s * 0.105
            outline.stroke()
            // Display
            let display = NSRect(x: body.minX + s * 0.15, y: body.minY + s * 0.15, width: body.width - s * 0.30, height: s * 0.17)
            NSBezierPath(roundedRect: display, xRadius: s * 0.04, yRadius: s * 0.04).fill()
            // Keys: three columns, three rows
            let key = s * 0.12
            let columns = 3, rows = 3
            let gapX = (display.width - key * CGFloat(columns)) / CGFloat(columns - 1)
            let top = display.maxY + s * 0.09
            let gapY = (body.maxY - s * 0.15 - top - key * CGFloat(rows)) / CGFloat(rows - 1)
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = display.minX + CGFloat(column) * (key + gapX)
                    let y = top + CGFloat(row) * (key + gapY)
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: key, height: key), xRadius: key * 0.3, yRadius: key * 0.3).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
