import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

/// How NSTextView copes with pretty JSON coloured per token. Off unless RACCOON_MEASURE=1:
/// `RACCOON_MEASURE=1 swift test --filter TextViewMeasurementTests` prints what
/// design/environment-facts.md records.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RACCOON_MEASURE"] == "1"), .serialized)
struct TextViewMeasurementTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    /// Pretty-printed JSON of about `megabytes`, the shape a list endpoint returns.
    static func json(megabytes: Int) -> String {
        let item = { (n: Int) in
            "  {\n    \"id\": \(n),\n    \"name\": \"Item number \(n)\",\n    \"price\": 12.50,\n    \"tags\": [\n      \"alpha\",\n      \"beta\"\n    ],\n    \"active\": true,\n    \"note\": null\n  }"
        }
        var items: [String] = []
        var size = 2
        while size < megabytes * 1_048_576 {
            items.append(item(items.count))
            size += items.last!.utf8.count + 2
        }
        return "[\n" + items.joined(separator: ",\n") + "\n]"
    }

    func coloured(_ text: String) -> NSAttributedString {
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: theme.color(.text),
        ])
        for range in Highlighter.ranges(text, kind: .json) {
            string.addAttribute(.foregroundColor, value: theme.color(range.token), range: range.range)
        }
        return string
    }

    func time(_ body: () -> Void) -> Duration {
        let start = ContinuousClock.now
        body()
        return ContinuousClock.now - start
    }

    @Test(arguments: [(1, true, 2), (5, true, 2), (20, true, 2), (20, false, 2), (5, true, 1), (20, true, 1), (20, false, 1)])
    func `open, scroll and switch a JSON body`(megabytes: Int, isColoured: Bool, textKit: Int) throws {
        let text = Self.json(megabytes: megabytes)
        let other = Self.json(megabytes: 1)
        var body = NSAttributedString()
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: theme.color(.text)]
        let highlight = time { body = isColoured ? coloured(text) : NSAttributedString(string: text, attributes: plain) }
        let otherBody = coloured(other)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let textView = NSTextView(usingTextLayoutManager: textKit == 2)
        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        // Touching layoutManager on a TextKit 2 view falls it back to TextKit 1.
        if textKit == 1 { textView.layoutManager?.allowsNonContiguousLayout = true }
        textView.isEditable = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let ms = { (d: Duration) in String(format: "%.0f ms", Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000) }
        let report = { (step: String, d: Duration) in print("MEASURE \(megabytes) MB \(isColoured ? "coloured" : "plain") TextKit \(textKit) \(step): \(ms(d))") }
        report("highlight (\(text.utf8.count) bytes)", highlight)
        // Opening and switching swap in a whole NSTextStorage.
        let swap = { (storage: NSTextStorage) in
            if textKit == 2, let content = textView.textLayoutManager?.textContentManager as? NSTextContentStorage {
                content.textStorage = storage
            } else {
                textView.layoutManager?.replaceTextStorage(storage)
            }
        }

        // Replacing the characters of a large coloured storage in place took minutes and never
        // finished at 1 MB, so the view's storage is swapped whole.
        report("open", time {
            swap(NSTextStorage(attributedString: body))
            window.displayIfNeeded()
        })
        report("scroll to end", time {
            textView.scrollToEndOfDocument(nil)
            window.displayIfNeeded()
        })
        report("scroll to middle", time {
            textView.scrollRangeToVisible(NSRange(location: text.utf16.count / 2, length: 0))
            window.displayIfNeeded()
        })
        let away = NSTextStorage(attributedString: otherBody)
        let back = NSTextStorage(attributedString: body)
        report("switch away", time {
            swap(away)
            window.displayIfNeeded()
        })
        defer { print("MEASURE \(megabytes) MB ran on TextKit \(textView.textLayoutManager != nil ? 2 : 1)") }
        report("switch back", time {
            swap(back)
            window.displayIfNeeded()
        })
    }
}
