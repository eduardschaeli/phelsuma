import CoreGraphics

public enum ColorColumnLayout {
    public struct Item<ID: Hashable> {
        public let id: ID
        public let color: NoteColor
        public let size: CGSize

        public init(id: ID, color: NoteColor, size: CGSize) {
            self.id = id
            self.color = color
            self.size = size
        }
    }

    private struct Column<ID: Hashable> {
        var items: [Item<ID>] = []
        var width: CGFloat = 0
    }

    public static func positions<ID: Hashable>(for items: [Item<ID>], in screen: CGRect) -> [ID: CGPoint] {
        guard !screen.isEmpty else { return [:] }
        let margin: CGFloat = 20
        let gap: CGFloat = 16
        let top = screen.maxY - margin
        let bottom = screen.minY + margin
        var groups: [[Column<ID>]] = []
        for color in NoteColor.allCases {
            let matching = items.filter { $0.color == color }
            guard !matching.isEmpty else { continue }
            var columns: [Column<ID>] = [Column()]
            var remaining = top
            for item in matching {
                if !columns[columns.count - 1].items.isEmpty && remaining - item.size.height < bottom {
                    columns.append(Column())
                    remaining = top
                }
                columns[columns.count - 1].items.append(item)
                columns[columns.count - 1].width = max(columns[columns.count - 1].width, item.size.width)
                remaining -= item.size.height + gap
            }
            groups.append(columns)
        }
        guard let first = groups.first else { return [:] }
        let center = screen.midX - first[0].width / 2
        var leftEdge = center
        var rightEdge = center + first[0].width
        var positions: [ID: CGPoint] = [:]

        func place(_ column: Column<ID>, at x: CGFloat) {
            let clampedX = min(max(x, screen.minX), max(screen.minX, screen.maxX - column.width))
            var topY = top
            for item in column.items {
                positions[item.id] = CGPoint(x: clampedX, y: max(screen.minY, topY - item.size.height))
                topY -= item.size.height + gap
            }
        }

        place(first[0], at: center)
        for column in first.dropFirst() {
            let x = rightEdge + gap
            place(column, at: x)
            rightEdge = x + column.width
        }
        for (index, group) in groups.dropFirst().enumerated() {
            let onLeft = index.isMultiple(of: 2)
            for column in group {
                if onLeft {
                    let x = leftEdge - gap - column.width
                    place(column, at: x)
                    leftEdge = x
                } else {
                    let x = rightEdge + gap
                    place(column, at: x)
                    rightEdge = x + column.width
                }
            }
        }
        return positions
    }
}
