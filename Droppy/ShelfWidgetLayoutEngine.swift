import SwiftUI

struct ShelfWidgetLayoutEngine {
    private let columnCount = 12
    private let columnSpacing: CGFloat = 10
    private let rowSpacing: CGFloat = 12
    private let rowHeight: CGFloat = 98

    func metrics(
        for page: ShelfPageConfiguration,
        maxDisplayWidth: CGFloat,
        notchHeight: CGFloat,
        isExternalWithNotchStyle: Bool
    ) -> ShelfPageMetrics {
        let sortedPlacements = page.placements.sorted { $0.order < $1.order }
        guard !sortedPlacements.isEmpty else {
            return ShelfPageMetrics.empty
        }

        let candidateWidth = candidateWidth(for: sortedPlacements.count)
        let cappedWidth = min(candidateWidth, maxDisplayWidth * 0.75)
        let isDense = sortedPlacements.count >= 3 || cappedWidth < candidateWidth

        let edgeInsets = NotchLayoutConstants.contentEdgeInsets(
            notchHeight: notchHeight,
            isExternalWithNotchStyle: isExternalWithNotchStyle
        )
        let horizontalInset = edgeInsets.leading
        let verticalInset = edgeInsets.top > 0 ? edgeInsets.top : 20

        let usableWidth = max(120, cappedWidth - (horizontalInset * 2))
        let cellWidth = (usableWidth - (CGFloat(columnCount - 1) * columnSpacing)) / CGFloat(columnCount)

        var frames: [ShelfWidgetLayoutFrame] = []
        var cursorColumn = 0
        var cursorRow = 0

        for placement in sortedPlacements {
            let compact = isDense && (placement.type == .media || placement.type == .terminal)
            let span = max(1, min(columnCount, columnSpan(for: placement, compact: compact)))

            if cursorColumn + span > columnCount {
                cursorColumn = 0
                cursorRow += 1
            }

            let x = horizontalInset + CGFloat(cursorColumn) * (cellWidth + columnSpacing)
            let y = verticalInset + CGFloat(cursorRow) * (rowHeight + rowSpacing)
            let width = CGFloat(span) * cellWidth + CGFloat(max(0, span - 1)) * columnSpacing

            frames.append(
                ShelfWidgetLayoutFrame(
                    placementID: placement.id,
                    type: placement.type,
                    rect: CGRect(x: x, y: y, width: width, height: rowHeight),
                    compactMode: compact
                )
            )

            cursorColumn += span
            if cursorColumn >= columnCount {
                cursorColumn = 0
                cursorRow += 1
            }
        }

        let totalRows = max(1, (frames.map { Int(($0.rect.maxY - verticalInset) / (rowHeight + rowSpacing)) }.max() ?? 0) + 1)
        let contentHeight = CGFloat(totalRows) * rowHeight + CGFloat(max(0, totalRows - 1)) * rowSpacing
        let height = max(140, contentHeight + verticalInset + 20)

        return ShelfPageMetrics(
            width: cappedWidth,
            height: height,
            horizontalContentInset: horizontalInset,
            verticalContentInset: verticalInset,
            frames: frames,
            isDense: isDense
        )
    }

    private func candidateWidth(for widgetCount: Int) -> CGFloat {
        switch widgetCount {
        case ...1:
            return 450
        case 2:
            return 560
        case 3:
            return 680
        case 4:
            return 760
        default:
            return 840
        }
    }

    private func columnSpan(for placement: ShelfWidgetPlacement, compact: Bool) -> Int {
        switch placement.type {
        case .files:
            switch placement.sizeHint {
            case .small: return 8
            case .medium: return 10
            case .large: return 12
            }
        case .media:
            if compact { return 6 }
            switch placement.sizeHint {
            case .small: return 6
            case .medium: return 8
            case .large: return 12
            }
        case .terminal:
            if compact { return 6 }
            switch placement.sizeHint {
            case .small: return 6
            case .medium: return 8
            case .large: return 12
            }
        case .camera:
            switch placement.sizeHint {
            case .small: return 4
            case .medium: return 5
            case .large: return 6
            }
        case .highAlert:
            switch placement.sizeHint {
            case .small: return 4
            case .medium: return 5
            case .large: return 6
            }
        case .tasksCalendar:
            switch placement.sizeHint {
            case .small: return 6
            case .medium: return 8
            case .large: return 12
            }
        }
    }
}
