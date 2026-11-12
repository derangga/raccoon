import Foundation
import RaccoonDomain
import Testing

/// Text is written with the selection in it: `‸` is a caret, `«` and `»` hold a selection.
struct DocsEditTests {
    static func parse(_ marked: String) -> (text: String, selection: NSRange) {
        var text = ""
        var (from, to) = (-1, -1)
        for ch in marked {
            switch ch {
            case "‸": (from, to) = (text.utf16.count, text.utf16.count)
            case "«": from = text.utf16.count
            case "»": to = text.utf16.count
            default: text.append(ch)
            }
        }
        return (text, NSRange(location: from, length: to - from))
    }

    static func show(_ text: String, _ selection: NSRange) -> String {
        var u = Array(text.utf16)
        if selection.length == 0 {
            u.insert(contentsOf: Array("‸".utf16), at: selection.location)
        } else {
            u.insert(contentsOf: Array("»".utf16), at: NSMaxRange(selection))
            u.insert(contentsOf: Array("«".utf16), at: selection.location)
        }
        return String(decoding: u, as: UTF16.self)
    }

    static func run(_ command: DocsEdit.Command, _ marked: String) -> String? {
        let (text, selection) = parse(marked)
        return DocsEdit.apply(command, to: text, selection: selection).map { show($0.text, $0.selection) }
    }

    @Test(arguments: [
        // wrap a selection, with the selection kept on the same text
        (DocsEdit.Command.toggle(.bold), "a «b» c", "a **«b»** c"),
        (.toggle(.italic), "a «b» c", "a *«b»* c"),
        (.toggle(.strikethrough), "a «b» c", "a ~~«b»~~ c"),
        (.toggle(.code), "a «b» c", "a `«b»` c"),
        // blanks at the ends of the selection stay outside the marks
        (.toggle(.bold), "«b »", "**«b»** "),
        // unwrap: the selection inside the style, or covering it with its marks
        (.toggle(.bold), "a **«b»** c", "a «b» c"),
        (.toggle(.bold), "a «**b**» c", "a «b» c"),
        (.toggle(.strikethrough), "~~«x»~~", "«x»"),
        (.toggle(.bold), "a **b‸c** d", "a b‸c d"),
        (.toggle(.bold), "## a **«b»** c", "## a «b» c"),
        (.toggle(.bold), "## a **b‸c** d", "## a b‸c d"),
        (.toggle(.bold), "## a «b»", "## a **«b»**"),
        // no selection: the word at the caret, then the empty pair
        (.toggle(.bold), "a b‸c d", "a **b‸c** d"),
        (.toggle(.italic), "word‸", "*word‸*"),
        (.toggle(.code), "‸word", "`‸word`"),
        (.toggle(.bold), "a ‸ b", "a **‸** b"),
        (.toggle(.bold), "‸", "**‸**"),
        (.toggle(.strikethrough), "‸", "~~‸~~"),
    ])
    func `inline toggles wrap and unwrap`(command: DocsEdit.Command, input: String, output: String) {
        #expect(Self.run(command, input) == output)
    }

    @Test(arguments: [
        (DocsEdit.Block.heading(2), "a‸", "## a‸"),
        (.heading(2), "# a‸", "## a‸"),
        (.heading(2), "## a‸", "a‸"),
        (.heading(3), "#### a‸", "### a‸"),
        (.paragraph, "## a‸", "a‸"),
        (.paragraph, "- a‸", "a‸"),
        (.quote, "- a‸", "> a‸"),
        (.bullet, "1. a‸", "- a‸"),
        (.bullet, "‸", "- ‸"),
        (.heading(1), "  a‸", "  # a‸"),
        // every line the selection touches
        (.bullet, "«a\nb»", "- «a\n- b»"),
        (.numbered, "«a\nb\nc»", "1. «a\n2. b\n3. c»"),
        (.numbered, "«- a\n> b»", "1. «a\n2. b»"),
        (.bullet, "«- a\n- b»", "«a\nb»"),
        (.bullet, "«- a\nb»", "- «a\n- b»"),
        (.quote, "«a\n\nb»", "> «a\n\n> b»"),
        (.quote, "«a\n»b", "> «a\n»b"),
        // a block of code: fences around the lines, and gone again from inside
        (.codeBlock, "«a\nb»", "```\n«a\nb»\n```"),
        (.codeBlock, "a‸", "```\na‸\n```"),
        (.codeBlock, "‸", "```\n‸\n```"),
        (.codeBlock, "```\na‸\n```", "a‸"),
        (.codeBlock, "x\n```json\na‸\n```\ny", "x\na‸\ny"),
        (.codeBlock, "```\na‸", "a‸"),
    ])
    func `block styles set, replace and remove a line mark`(block: DocsEdit.Block, input: String, output: String) {
        #expect(Self.run(.block(block), input) == output)
    }

    @Test(arguments: [
        (DocsEdit.Block.paragraph, "a‸"),
        (.heading(0), "a‸"),
        (.heading(4), "a‸"),
    ])
    func `a block style that changes nothing is nil`(block: DocsEdit.Block, input: String) {
        #expect(Self.run(.block(block), input) == nil)
    }

    @Test(arguments: [
        ("u.io", "a «b» c", "a [«b»](u.io) c"),
        ("u.io", "x‸", "x[«u.io»](u.io)"),
        (" u.io ", "x‸", "x[«u.io»](u.io)"),
        ("a.io/x y(1)", "a «b» c", "a [«b»](a.io/x%20y%281%29) c"),
        ("a.io/x y(1)", "[a‸](x.io)", "[a‸](a.io/x%20y%281%29)"),
        ("a b", "x‸", "x[«a b»](a%20b)"),
        ("y.io", "[a‸](x.io)", "[a‸](y.io)"),
        ("y.io", "[«a»](x.io)", "[«a»](y.io)"),
        ("", "[a‸](x.io)", "a‸"),
        ("", "z [«ab»](x.io) z", "z «ab» z"),
    ])
    func `link wraps, edits the URL and removes the link`(url: String, input: String, output: String) {
        #expect(Self.run(.link(url: url), input) == output)
    }

    @Test(arguments: ["a «b» c", "x‸"])
    func `an empty URL outside a link is nil`(input: String) {
        #expect(Self.run(.link(url: ""), input) == nil)
    }

    @Test(arguments: [
        ("- a‸", "- a\n- ‸"),
        ("* a‸", "* a\n* ‸"),
        ("1. a‸", "1. a\n2. ‸"),
        ("9) a‸", "9) a\n10) ‸"),
        ("  - a‸", "  - a\n  - ‸"),
        ("- a‸b", "- a\n- ‸b"),
        ("x\n- a‸\ny", "x\n- a\n- ‸\ny"),
        // an empty item ends the list: no line break
        ("- ‸", "‸"),
        ("1. ‸", "‸"),
        ("x\n1) ‸", "x\n‸"),
    ])
    func `return continues a list and ends it on an empty item`(input: String, output: String) {
        #expect(Self.run(.newline, input) == output)
    }

    @Test(arguments: ["a‸", "> a‸", "# a‸", "«- a»", "-‸", "```\n- a‸\n```", "‸", "-a‸"])
    func `return elsewhere is nil`(input: String) {
        #expect(Self.run(.newline, input) == nil)
    }

    @Test(arguments: [
        ("## ‸a", "‸a"),
        ("# ‸", "‸"),
        ("- ‸a", "‸a"),
        ("3. ‸a", "‸a"),
        ("> ‸a", "‸a"),
        ("x\n> ‸a", "x\n‸a"),
        ("  - ‸a", "  ‸a"),
    ])
    func `delete at a line start removes its line mark`(input: String, output: String) {
        #expect(Self.run(.deleteBackward, input) == output)
    }

    @Test(arguments: ["a‸", "- a‸", "‸- a", "«## a»", "## a‸", "```\n# ‸a\n```", "‸", "#‸a"])
    func `delete elsewhere is nil`(input: String) {
        #expect(Self.run(.deleteBackward, input) == nil)
    }

    @Test func `a selection outside the text is nil`() {
        #expect(DocsEdit.apply(.toggle(.bold), to: "ab", selection: NSRange(location: 1, length: 5)) == nil)
        #expect(DocsEdit.apply(.toggle(.bold), to: "ab", selection: NSRange(location: NSNotFound, length: 0)) == nil)
    }

    @Test func `the selection stays on the same text past an emoji`() {
        #expect(Self.run(.toggle(.bold), "😀 «b»") == "😀 **«b»**")
    }

    @Test(arguments: [
        ("## a‸", DocsEdit.State(block: .heading(2), inline: [], link: nil)),
        ("#### a‸", .init(block: .heading(3), inline: [], link: nil)),
        ("- a‸", .init(block: .bullet, inline: [], link: nil)),
        ("1. a‸", .init(block: .numbered, inline: [], link: nil)),
        ("> a‸", .init(block: .quote, inline: [], link: nil)),
        ("```\nx‸\n```", .init(block: .codeBlock, inline: [], link: nil)),
        ("## a **b‸** c", .init(block: .heading(2), inline: [.bold], link: nil)),
        ("a **b‸** c", .init(block: .paragraph, inline: [.bold], link: nil)),
        ("a ~~«b»~~ `c`", .init(block: .paragraph, inline: [.strikethrough], link: nil)),
        ("«a **b**»", .init(block: .paragraph, inline: [], link: nil)),
        ("[a‸](x.io)", .init(block: .paragraph, inline: [], link: "x.io")),
        ("[a‸](x.io/y%20z%281%29)", .init(block: .paragraph, inline: [], link: "x.io/y%20z%281%29")),
        ("«a\n- b»", .init(block: .paragraph, inline: [], link: nil)),
        ("", .init(block: .paragraph, inline: [], link: nil)),
    ])
    func `state is what the toolbar shows`(input: String, state: DocsEdit.State) {
        let (text, selection) = Self.parse(input.isEmpty ? "‸" : input)
        #expect(DocsEdit.state(text, selection: selection) == state)
    }
}
