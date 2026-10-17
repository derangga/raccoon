import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

/// Whether hiding Folded regions in the layout keeps a 5 MB Pretty body inside the 129 ms
/// step budget. Off unless RACCOON_MEASURE=1:
/// `RACCOON_MEASURE=1 swift test --filter FoldMeasurementTests` prints what
/// design/environment-facts.md records.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RACCOON_MEASURE"] == "1"), .serialized)
struct FoldMeasurementTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    /// Spike: hidden ranges as UTF-16 offsets, whole lines, sorted and disjoint. A hidden line
    /// keeps its own line fragment, with null glyphs and zero height; zero-advance line breaks
    /// merge the region into one line, which CoreText typesets for minutes at 1 MB.
    final class Hider: NSObject, NSLayoutManagerDelegate {
        var hidden: [Range<Int>] = []

        func region(containing index: Int) -> Range<Int>? {
            var (low, high) = (0, hidden.count)
            while low < high {
                let mid = (low + high) / 2
                if hidden[mid].upperBound <= index { low = mid + 1 } else { high = mid }
            }
            return low < hidden.count && hidden[low].contains(index) ? hidden[low] : nil
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
            font: NSFont, forGlyphRange range: NSRange
        ) -> Int {
            // One search per call, then a walk: a search per glyph is seconds at 5 MB.
            let first = characterIndexes[0], last = characterIndexes[range.length - 1]
            var (low, high) = (0, hidden.count)
            while low < high {
                let mid = (low + high) / 2
                if hidden[mid].upperBound <= first { low = mid + 1 } else { high = mid }
            }
            guard low < hidden.count, hidden[low].lowerBound <= last else { return 0 }
            var changed = Array(UnsafeBufferPointer(start: properties, count: range.length))
            var r = low
            for i in 0..<range.length {
                let index = characterIndexes[i]
                while r < hidden.count, hidden[r].upperBound <= index { r += 1 }
                guard r < hidden.count else { break }
                if hidden[r].contains(index), !changed[i].contains(.controlCharacter) { changed[i] = .null }
            }
            layoutManager.setGlyphs(glyphs, properties: changed, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
            return range.length
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager, shouldSetLineFragmentRect rect: UnsafeMutablePointer<NSRect>,
            lineFragmentUsedRect used: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
            in container: NSTextContainer, forGlyphRange range: NSRange
        ) -> Bool {
            guard region(containing: layoutManager.characterIndexForGlyph(at: range.location)) != nil else { return false }
            rect.pointee.size.height = 0
            used.pointee.size.height = 0
            baselineOffset.pointee = 0
            return true
        }
    }

    /// Spike: open line, close line and hidden range by indentation.
    static func regions(_ text: String) -> [(open: Int, close: Int, hidden: Range<Int>)] {
        let units = Array(text.utf16)
        var starts = [0]
        for (i, unit) in units.enumerated() where unit == 10 { starts.append(i + 1) }
        let indent = starts.map { start in
            var i = start
            while i < units.count, units[i] == 32 { i += 1 }
            return i - start
        }
        var stack: [Int] = []
        var found: [(open: Int, close: Int, hidden: Range<Int>)] = []
        for line in starts.indices {
            while let top = stack.last, indent[top] >= indent[line] {
                stack.removeLast()
                if top + 1 < line, indent[top + 1] > indent[top] {
                    found.append((top, line, starts[top + 1] ..< (line + 1 < starts.count ? starts[line + 1] : units.count)))
                }
            }
            stack.append(line)
        }
        return found.sorted { $0.open < $1.open }
    }

    /// The folded regions not inside another, as the layout needs them.
    static func outermost(_ folded: [(open: Int, close: Int, hidden: Range<Int>)]) -> [Range<Int>] {
        var kept: [(open: Int, close: Int, hidden: Range<Int>)] = []
        for region in folded where kept.last.map({ region.open >= $0.close }) ?? true { kept.append(region) }
        return kept.map(\.hidden)
    }

    @Test(arguments: [1, 5])
    func `fold, unfold and scroll a JSON body`(megabytes: Int) throws {
        let text = TextViewMeasurementTests.json(megabytes: megabytes)
        let body = TextViewMeasurementTests().coloured(text)
        var regions: [(open: Int, close: Int, hidden: Range<Int>)] = []
        let found = Self.time { regions = Self.regions(text) }

        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        layout.addTextContainer(container)
        let hider = Hider()
        layout.delegate = hider
        var storage = NSTextStorage()
        storage.addLayoutManager(layout)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), textContainer: container)
        textView.isEditable = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = []
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let report = { (step: String, d: Duration) in
            let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            print("MEASURE fold \(megabytes) MB \(step): \(String(format: "%.0f ms", ms))")
        }
        report("find \(regions.count) regions in \(text.utf16.count) UTF-16", found)
        let length = text.utf16.count
        let apply = { (folded: [Range<Int>]) in
            hider.hidden = folded
            let all = NSRange(location: 0, length: length)
            layout.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
            textView.sizeToFit()
            window.displayIfNeeded()
        }
        report("open", Self.time {
            storage = NSTextStorage(attributedString: body)
            layout.replaceTextStorage(storage)
            window.displayIfNeeded()
        })
        let root = regions[0]
        report("fold root", Self.time { apply(Self.outermost([root])) })
        print("MEASURE fold \(megabytes) MB root folded: view height \(textView.frame.height), used \(layout.usedRect(for: container).height)")
        report("  ensure layout of the whole root", Self.time {
            layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: length))
            textView.sizeToFit()
            window.displayIfNeeded()
        })
        print("MEASURE fold \(megabytes) MB root folded after layout: view height \(textView.frame.height), used \(layout.usedRect(for: container).height)")
        report("unfold root", Self.time { apply([]) })
        // The second item, folded: its close line must sit on its open line.
        let item = regions[1]
        report("fold one item", Self.time { apply([item.hidden]) })
        let top = { (index: Int) in layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: index), effectiveRange: nil) }
        print("MEASURE fold \(megabytes) MB one item: open line \(top(item.hidden.lowerBound - 1)), first hidden \(top(item.hidden.lowerBound)), last hidden \(top(item.hidden.upperBound - 1)), next line \(top(item.hidden.upperBound))")
        report("fold all", Self.time { apply(Self.outermost(regions)) })
        report("unfold root, items stay folded", Self.time { apply(Self.outermost(Array(regions.dropFirst()))) })
        report("  scroll to middle", Self.time {
            textView.scrollRangeToVisible(NSRange(location: length / 2, length: 0))
            window.displayIfNeeded()
        })
        report("  scroll to end", Self.time {
            textView.scrollToEndOfDocument(nil)
            window.displayIfNeeded()
        })
        report("unfold all", Self.time { apply([]) })
        report("  scroll to middle", Self.time {
            textView.scrollRangeToVisible(NSRange(location: length / 2, length: 0))
            window.displayIfNeeded()
        })
        report("  scroll to end", Self.time {
            textView.scrollToEndOfDocument(nil)
            window.displayIfNeeded()
        })
        report("fold root at the end", Self.time { apply(Self.outermost([root])) })
        #expect(storage.length == length)
    }

    /// What ships: `FoldRegion.find`, `FoldedText` and `ResponseViewer.cut`, swapped in whole.
    @Test(arguments: [1, 5, 20])
    func `swap in a folded display storage`(megabytes: Int) throws {
        let text = TextViewMeasurementTests.json(megabytes: megabytes)
        let body = TextViewMeasurementTests().coloured(text)
        var regions: [FoldRegion] = []
        let found = Self.time { regions = FoldRegion.find(text, lines: LineIndex(text)) }
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        layout.addTextContainer(container)
        var storage = NSTextStorage()
        storage.addLayoutManager(layout)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), textContainer: container)
        textView.isEditable = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = []
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let report = { (step: String, d: Duration) in
            let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            print("MEASURE swap \(megabytes) MB \(step): \(String(format: "%.0f ms", ms))")
        }
        report("find \(regions.count) regions", found)
        let marker = NSAttributedString(string: FoldedText.marker, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
        let apply = { (folded: [FoldRegion]) in
            storage = ResponseViewer.cut(body, FoldedText(regions: regions, folds: FoldSet(folding: folded)).folded, marker: marker)
            layout.replaceTextStorage(storage)
            textView.sizeToFit()
            window.displayIfNeeded()
        }
        report("open", Self.time { apply([]) })
        textView.scrollToEndOfDocument(nil)
        report("fold root at the end", Self.time { apply([regions[0]]) })
        print("MEASURE swap \(megabytes) MB root folded: view height \(textView.frame.height), text \(storage.string.prefix(12).debugDescription)")
        report("fold all", Self.time { apply(regions) })
        report("unfold root, items stay folded", Self.time { apply(Array(regions.dropFirst())) })
        report("  scroll to middle", Self.time {
            textView.scrollRangeToVisible(NSRange(location: storage.length / 2, length: 0))
            window.displayIfNeeded()
        })
        report("  scroll to end", Self.time {
            textView.scrollToEndOfDocument(nil)
            window.displayIfNeeded()
        })
        report("unfold all", Self.time { apply([]) })
        report("fold one item", Self.time { apply([regions[1]]) })
        report("fold one item at the end", Self.time { apply([regions[regions.count - 1]]) })
        report("fold 63 items", Self.time { apply(Array(regions.dropFirst().prefix(63))) })
    }

    static func time(_ body: () -> Void) -> Duration {
        let start = ContinuousClock.now
        body()
        return ContinuousClock.now - start
    }
}
