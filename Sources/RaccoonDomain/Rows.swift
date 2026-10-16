/// The edits a key/value table makes. Index `rows.count` is the trailing empty row: typing in
/// it creates a row, and it cannot be toggled or deleted.
public enum Rows {
    public static func setName(_ name: String, at index: Int, in rows: [Row]) -> [Row] {
        var rows = rows
        if index == rows.count { rows.append(Row(name: "", value: "")) }
        rows[index].name = name
        return rows
    }

    public static func setValue(_ value: String, at index: Int, in rows: [Row]) -> [Row] {
        var rows = rows
        if index == rows.count { rows.append(Row(name: "", value: "")) }
        rows[index].value = value
        return rows
    }

    public static func toggle(at index: Int, in rows: [Row]) -> [Row] {
        guard rows.indices.contains(index) else { return rows }
        var rows = rows
        rows[index].isEnabled.toggle()
        return rows
    }

    public static func delete(at index: Int, in rows: [Row]) -> [Row] {
        guard rows.indices.contains(index) else { return rows }
        var rows = rows
        rows.remove(at: index)
        return rows
    }
}
