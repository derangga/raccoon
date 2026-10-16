import RaccoonDomain
import Testing

struct RowsTests {
    let rows = [Row(name: "limit", value: "20"), Row(name: "since", value: "{{since}}", isEnabled: false)]

    @Test func `typing in the trailing empty row creates a row`() {
        #expect(Rows.setName("status", at: 2, in: rows) == rows + [Row(name: "status", value: "")])
        #expect(Rows.setValue("x", at: 2, in: rows) == rows + [Row(name: "", value: "x")])
    }

    @Test func `editing a row changes only that cell and keeps a Disabled Row disabled`() {
        #expect(Rows.setName("until", at: 1, in: rows) == [rows[0], Row(name: "until", value: "{{since}}", isEnabled: false)])
        #expect(Rows.setValue("50", at: 0, in: rows) == [Row(name: "limit", value: "50"), rows[1]])
    }

    @Test func `toggling a row flips isEnabled only`() {
        #expect(Rows.toggle(at: 0, in: rows) == [Row(name: "limit", value: "20", isEnabled: false), rows[1]])
        #expect(Rows.toggle(at: 1, in: rows) == [rows[0], Row(name: "since", value: "{{since}}")])
    }

    @Test func `the trailing empty row cannot be toggled or deleted`() {
        #expect(Rows.toggle(at: 2, in: rows) == rows)
        #expect(Rows.delete(at: 2, in: rows) == rows)
    }

    @Test func `deleting a row removes it and keeps the others in order`() {
        #expect(Rows.delete(at: 0, in: rows) == [rows[1]])
    }
}
