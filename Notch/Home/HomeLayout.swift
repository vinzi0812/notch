import Foundation

/// How much of the Home grid a widget covers, like iOS widget sizes.
enum WidgetSize: String, CaseIterable, Codable, Identifiable {
    case small, wide, tall, large

    var id: String { rawValue }

    var columns: Int { self == .wide || self == .large ? 2 : 1 }
    var rows: Int { self == .tall || self == .large ? 2 : 1 }

    var title: String {
        switch self {
        case .small: "Small"
        case .wide: "Wide"
        case .tall: "Tall"
        case .large: "Large"
        }
    }
}

/// Something that can sit on Home. One of each at most.
enum HomeWidgetKind: String, CaseIterable, Codable, Identifiable {
    case battery, timer, calendar, cpu, gpu, memory, temperature, devices, notes, calculator

    var id: String { rawValue }

    /// The feature it belongs to; hiding that feature hides the widget too.
    var feature: NotchFeature {
        switch self {
        case .battery: .battery
        case .timer: .timer
        case .calendar: .calendar
        case .cpu, .gpu, .memory, .temperature: .systemStats
        case .devices: .devices
        case .notes: .notes
        case .calculator: .calculator
        }
    }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .timer: "Timer"
        case .calendar: "Calendar"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .temperature: "Temperature"
        case .devices: "Devices"
        case .notes: "Notes"
        case .calculator: "Calculator"
        }
    }

    /// For narrow widgets, where "Temperature" would be cut off.
    var shortTitle: String { self == .temperature ? "Temp" : title }

    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .timer: "timer"
        case .calendar: "calendar"
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .temperature: "thermometer.medium"
        case .devices: "airpods.pro"
        case .notes: "note.text"
        case .calculator: NotchIcon.calculator   // our own glyph: SF Symbols has no calculator
        }
    }
}

struct HomeWidget: Codable, Equatable, Identifiable {
    var kind: HomeWidgetKind
    var size: WidgetSize

    var id: HomeWidgetKind { kind }
}

/// Home's widgets as an ordered list with sizes. Positions aren't stored: they're worked out by
/// packing the list into however many columns the notch has, so one layout suits every width.
struct HomeLayout: Codable, Equatable {
    var widgets: [HomeWidget]

    static let rows = 2

    /// Fills five columns exactly: the timer's full view, the calendar, and small vitals around them.
    static let `default` = HomeLayout(widgets: [
        HomeWidget(kind: .timer, size: .large),
        HomeWidget(kind: .calendar, size: .wide),
        HomeWidget(kind: .battery, size: .small),
        HomeWidget(kind: .cpu, size: .small),
        HomeWidget(kind: .gpu, size: .small),
        HomeWidget(kind: .memory, size: .small),
        HomeWidget(kind: .temperature, size: .small),
    ])

    /// Columns for a notch of this width, keeping cells about 100 pt wide: 4, 5 or 6 for the
    /// Compact, Standard and Wide settings.
    static func columns(forWidth width: CGFloat) -> Int {
        width >= 600 ? 6 : width >= 520 ? 5 : 4
    }

    struct Placement: Equatable {
        let widget: HomeWidget
        var column: Int
        var row: Int
        /// The cells it covers. Its size's own span, unless `filled` grew it into a gap.
        var columnSpan: Int
        var rowSpan: Int

        init(widget: HomeWidget, column: Int, row: Int) {
            self.widget = widget
            self.column = column
            self.row = row
            columnSpan = widget.size.columns
            rowSpan = widget.size.rows
        }

        /// The size to draw it at, after any growing: two rows and two or more columns is Large, etc.
        var displaySize: WidgetSize {
            switch (columnSpan > 1, rowSpan > 1) {
            case (true, true): .large
            case (false, true): .tall
            case (true, false): .wide
            case (false, false): .small
            }
        }

        func covers(column c: Int, row r: Int) -> Bool {
            (column..<(column + columnSpan)).contains(c) && (row..<(row + rowSpan)).contains(r)
        }
    }

    /// Places each widget, in order, at the first spot it fits, going down each column before
    /// moving right (so Home fills from the left, the way you read it). Widgets with no room left
    /// are returned as `overflow`: kept in the layout, just not shown at this width.
    func arranged(columns: Int) -> (placed: [Placement], overflow: [HomeWidget]) {
        var taken = Set<[Int]>()
        var placed: [Placement] = []
        var overflow: [HomeWidget] = []

        func fits(_ size: WidgetSize, column: Int, row: Int) -> Bool {
            guard column + size.columns <= columns, row + size.rows <= Self.rows else { return false }
            for c in column..<(column + size.columns) {
                for r in row..<(row + size.rows) where taken.contains([c, r]) { return false }
            }
            return true
        }

        for widget in widgets {
            let spot = (0..<columns).lazy
                .flatMap { column in (0..<Self.rows).lazy.map { row in (column, row) } }
                .first { fits(widget.size, column: $0.0, row: $0.1) }
            guard let (column, row) = spot else {
                overflow.append(widget)
                continue
            }
            for c in column..<(column + widget.size.columns) {
                for r in row..<(row + widget.size.rows) { taken.insert([c, r]) }
            }
            placed.append(Placement(widget: widget, column: column, row: row))
        }
        return (placed, overflow)
    }

    /// What Home shows: the packed widgets with no empty space. Columns nobody uses are dropped (the
    /// rest widen to the full width), then widgets grow into gaps next to them, preferring to grow
    /// down or up (a Small becomes Tall) before sideways. Only the drawing changes; the saved sizes
    /// don't, so a widget shrinks back when the space is needed.
    func filled(columns: Int) -> (placed: [Placement], columns: Int) {
        var placed = arranged(columns: columns).placed
        guard !placed.isEmpty else { return ([], columns) }
        let usedColumns = placed.map { $0.column + $0.columnSpan }.max() ?? columns

        func isFree(column c: Int, row r: Int) -> Bool {
            (0..<usedColumns).contains(c) && (0..<Self.rows).contains(r) && !placed.contains { $0.covers(column: c, row: r) }
        }
        func free(columns cs: Range<Int>, rows rs: Range<Int>) -> Bool {
            cs.allSatisfy { c in rs.allSatisfy { r in isFree(column: c, row: r) } }
        }

        var grew = true
        while grew {
            grew = false
            // Vertically first: a column of widgets reads better than one stretched sideways.
            for index in placed.indices {
                let p = placed[index]
                let columnsCovered = p.column..<(p.column + p.columnSpan)
                if free(columns: columnsCovered, rows: (p.row + p.rowSpan)..<(p.row + p.rowSpan + 1)) {
                    placed[index].rowSpan += 1
                    grew = true
                } else if p.row > 0, free(columns: columnsCovered, rows: (p.row - 1)..<p.row) {
                    placed[index].row -= 1
                    placed[index].rowSpan += 1
                    grew = true
                }
            }
            if grew { continue }
            for index in placed.indices {
                let p = placed[index]
                let rowsCovered = p.row..<(p.row + p.rowSpan)
                if free(columns: (p.column + p.columnSpan)..<(p.column + p.columnSpan + 1), rows: rowsCovered) {
                    placed[index].columnSpan += 1
                    grew = true
                    break
                } else if p.column > 0, free(columns: (p.column - 1)..<p.column, rows: rowsCovered) {
                    placed[index].column -= 1
                    placed[index].columnSpan += 1
                    grew = true
                    break
                }
            }
        }
        return (placed, usedColumns)
    }

    // MARK: - Saving

    /// Decodes what it can: widgets of a kind this version doesn't know are skipped, as are repeats.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([Lossy<HomeWidget>].self, forKey: .widgets).compactMap(\.value)
        var seen = Set<HomeWidgetKind>()
        widgets = decoded.filter { seen.insert($0.kind).inserted }
    }

    init(widgets: [HomeWidget]) {
        self.widgets = widgets
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(Value.self)
        }
    }
}

extension WidgetSize {
    /// The size covering this many cells, clamped to what exists (1–2 each way).
    init(columns: Int, rows: Int) {
        switch (columns >= 2, rows >= 2) {
        case (true, true): self = .large
        case (false, true): self = .tall
        case (true, false): self = .wide
        case (false, false): self = .small
        }
    }
}

// MARK: - Editing

/// The edits the layout editor makes. Pure functions on the list, so they're tested without any UI.
/// `visible` is the kinds currently shown (their feature is on); hidden ones keep their place in the
/// saved list untouched.
extension HomeLayout {
    func contains(_ kind: HomeWidgetKind) -> Bool {
        widgets.contains { $0.kind == kind }
    }

    mutating func add(_ kind: HomeWidgetKind, size: WidgetSize = .small) {
        guard !contains(kind) else { return }
        widgets.append(HomeWidget(kind: kind, size: size))
    }

    mutating func remove(_ kind: HomeWidgetKind) {
        widgets.removeAll { $0.kind == kind }
    }

    mutating func resize(_ kind: HomeWidgetKind, to size: WidgetSize) {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        widgets[index].size = size
    }

    /// Moves a widget being dragged to the cell under the pointer, the way iOS widgets do:
    /// over another widget, the two trade places in the order; over an empty cell, it goes to the
    /// place in the order that cell corresponds to. Returns whether anything changed.
    @discardableResult
    mutating func move(_ kind: HomeWidgetKind, toColumn column: Int, row: Int, columns: Int, visible: Set<HomeWidgetKind>) -> Bool {
        guard let dragged = widgets.first(where: { $0.kind == kind }) else { return false }
        let shown = HomeLayout(widgets: widgets.filter { visible.contains($0.kind) })
        let placed = shown.arranged(columns: columns).placed

        let anchor: (kind: HomeWidgetKind, after: Bool)?
        if let target = placed.first(where: { $0.covers(column: column, row: row) }) {
            guard target.widget.kind != kind else { return false }
            let order = shown.widgets.map(\.kind)
            // Moving forward lands after the widget it's over; moving back lands before it.
            let movingForward = (order.firstIndex(of: kind) ?? 0) < (order.firstIndex(of: target.widget.kind) ?? 0)
            anchor = (target.widget.kind, movingForward)
        } else {
            // An empty cell: before the first widget that comes after it in reading order.
            let others = HomeLayout(widgets: shown.widgets.filter { $0.kind != kind }).arranged(columns: columns).placed
            let key = column * Self.rows + row
            anchor = others.first { $0.column * Self.rows + $0.row > key }.map { ($0.widget.kind, false) }
        }

        var reordered = widgets.filter { $0.kind != kind }
        if let anchor, let index = reordered.firstIndex(where: { $0.kind == anchor.kind }) {
            reordered.insert(dragged, at: anchor.after ? index + 1 : index)
        } else {
            reordered.append(dragged)
        }
        guard reordered != widgets else { return false }
        widgets = reordered
        return true
    }
}
