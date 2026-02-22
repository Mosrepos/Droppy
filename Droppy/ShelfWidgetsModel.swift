import Foundation
import CoreGraphics

enum ShelfWidgetType: String, Codable, CaseIterable, Identifiable {
    case files
    case media
    case highAlert
    case terminal
    case camera
    case tasksCalendar

    var id: String { rawValue }
}

enum ShelfWidgetSizeHint: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }
}

enum ShelfLayoutProfileType: String, Codable, CaseIterable, Identifiable {
    case builtIn
    case external

    var id: String { rawValue }
}

struct ShelfWidgetPlacement: Codable, Identifiable, Hashable {
    var id: UUID
    var type: ShelfWidgetType
    var sizeHint: ShelfWidgetSizeHint
    var order: Int

    init(id: UUID = UUID(), type: ShelfWidgetType, sizeHint: ShelfWidgetSizeHint = .medium, order: Int) {
        self.id = id
        self.type = type
        self.sizeHint = sizeHint
        self.order = order
    }
}

struct ShelfPageConfiguration: Codable, Identifiable, Hashable {
    var id: UUID
    var index: Int
    var placements: [ShelfWidgetPlacement]

    init(id: UUID = UUID(), index: Int, placements: [ShelfWidgetPlacement]) {
        self.id = id
        self.index = index
        self.placements = placements
    }
}

struct ShelfProfileConfiguration: Codable, Hashable {
    var pages: [ShelfPageConfiguration]
    var activePageIndex: Int

    init(pages: [ShelfPageConfiguration], activePageIndex: Int = 0) {
        self.pages = pages
        self.activePageIndex = activePageIndex
    }
}

struct ShelfWidgetsConfiguration: Codable, Hashable {
    var version: Int
    var profiles: [ShelfLayoutProfileType: ShelfProfileConfiguration]

    init(version: Int = 1, profiles: [ShelfLayoutProfileType: ShelfProfileConfiguration]) {
        self.version = version
        self.profiles = profiles
    }
}

struct ShelfMissingWidgetPrompt: Codable, Identifiable, Hashable {
    var id: UUID
    var profileType: ShelfLayoutProfileType
    var pageID: UUID
    var placementID: UUID
    var widgetType: ShelfWidgetType

    init(
        id: UUID = UUID(),
        profileType: ShelfLayoutProfileType,
        pageID: UUID,
        placementID: UUID,
        widgetType: ShelfWidgetType
    ) {
        self.id = id
        self.profileType = profileType
        self.pageID = pageID
        self.placementID = placementID
        self.widgetType = widgetType
    }
}

struct ShelfWidgetLayoutFrame: Identifiable {
    var id: UUID { placementID }
    var placementID: UUID
    var type: ShelfWidgetType
    var rect: CGRect
    var compactMode: Bool
}

struct ShelfPageMetrics {
    var width: CGFloat
    var height: CGFloat
    var horizontalContentInset: CGFloat
    var verticalContentInset: CGFloat
    var frames: [ShelfWidgetLayoutFrame]
    var isDense: Bool

    static let empty = ShelfPageMetrics(
        width: 450,
        height: 140,
        horizontalContentInset: 18,
        verticalContentInset: 12,
        frames: [],
        isDense: false
    )
}
