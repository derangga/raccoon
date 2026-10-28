import AppKit
import RaccoonDomain

extension NSAttributedString.Key {
    /// A Path Variable's range in the URL field: `[fill, border]`. Paint only, so the text, the caret
    /// and the selection are those of any other text; WavyLayoutManager and PathTokenUnderlay draw it.
    nonisolated static let pathToken = NSAttributedString.Key("RaccoonPathToken")
}

/// The `:name` token (design-system §6 URL bar): a rounded 4 pt token filled `backgroundRecessed`
/// with a 0.5 pt `border` hairline, the text in `textSecondary`.
enum PathTokenStyle {
    static func apply(to text: NSMutableAttributedString, theme: ThemeEnvironment) {
        text.removeAttribute(.pathToken, range: NSRange(location: 0, length: text.length))
        for token in PathVariables.tokens(in: text.string) where NSMaxRange(token.range) <= text.length {
            text.addAttributes([
                .pathToken: [theme.color(.backgroundRecessed), theme.color(.border)],
                .foregroundColor: theme.color(.textSecondary),
            ], range: token.range)
        }
    }

    /// Fills and outlines every `.pathToken` run in `glyphs`, one per line fragment, the glyph
    /// bounds outset 1 pt, with the text container's origin at `origin`.
    nonisolated static func draw(_ manager: NSLayoutManager, glyphs: NSRange, at origin: NSPoint) {
        guard let storage = manager.textStorage else { return }
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.pathToken, in: characters) { value, range, _ in
            guard let colors = value as? [NSColor], colors.count == 2 else { return }
            let run = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            manager.enumerateLineFragments(forGlyphRange: run) { _, _, container, line, _ in
                let box = manager.boundingRect(forGlyphRange: NSIntersectionRange(run, line), in: container)
                // The hairline is centred on the edge, so it is drawn half a point inside it.
                let rect = box.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1, dy: -1).insetBy(dx: 0.25, dy: 0.25)
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                path.lineWidth = 0.5
                colors[0].setFill()
                path.fill()
                colors[1].setStroke()
                path.stroke()
            }
        }
    }
}

/// The tokens of a field at rest, drawn in a view under it: a field draws its own text, so
/// anything over it would hide the text. While the field is edited its editor draws them.
/// The view is `outset` taller than the field either side, for the token's 1 pt margin.
final class PathTokenUnderlay: NSView {
    static let outset: CGFloat = 2
    private weak var field: NSTextField?

    init(field: NSTextField) {
        self.field = field
        super.init(frame: field.frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The field's string laid out where its cell draws it, in this view.
    var layout: TextLayout? {
        guard let field else { return nil }
        let atRest = TextLayout.atRest(field, space: self)
        return TextLayout(storage: atRest.storage, manager: atRest.manager,
                          origin: NSPoint(x: atRest.origin.x, y: atRest.origin.y + Self.outset), space: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let field, let cell = field.cell, let layout else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cell.drawingRect(forBounds: field.bounds).offsetBy(dx: 0, dy: Self.outset).insetBy(dx: 0, dy: -Self.outset)).addClip()
        PathTokenStyle.draw(layout.manager, glyphs: layout.manager.glyphRange(for: layout.manager.textContainers[0]), at: layout.origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}
