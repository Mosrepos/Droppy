import SwiftUI
import Observation
import AppKit

@MainActor
@Observable
final class ShelfWidgetsManager {
    static let shared = ShelfWidgetsManager()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let layoutEngine = ShelfWidgetLayoutEngine()

    private(set) var configuration: ShelfWidgetsConfiguration
    private(set) var pendingMissingWidgetPrompts: [ShelfMissingWidgetPrompt]
    private(set) var showOnboardingCallouts: Bool

    private var undoSnapshot: ShelfWidgetsConfiguration?

    private init() {
        let loadedConfiguration = Self.loadConfiguration(from: UserDefaults.standard)
        configuration = loadedConfiguration
        pendingMissingWidgetPrompts = Self.loadPendingPrompts(from: UserDefaults.standard)
        showOnboardingCallouts = !UserDefaults.standard.preference(
            AppPreferenceKey.shelfWidgetsOnboardingSeen,
            default: PreferenceDefault.shelfWidgetsOnboardingSeen
        )

        runMigrationIfNeeded()
        configuration = sanitized(configuration)
        saveConfiguration()
        clearResolvedPendingPrompts()
    }

    // MARK: - Public Profile Access

    func profileType(for screen: NSScreen?) -> ShelfLayoutProfileType {
        let target = screen ?? NSScreen.main
        if let target, target.isBuiltIn {
            return .builtIn
        }
        return .external
    }

    func profile(for type: ShelfLayoutProfileType) -> ShelfProfileConfiguration {
        configuration.profiles[type] ?? Self.defaultProfile()
    }

    func activePage(for type: ShelfLayoutProfileType) -> ShelfPageConfiguration {
        let profileConfiguration = profile(for: type)
        let clampedIndex = max(0, min(profileConfiguration.activePageIndex, profileConfiguration.pages.count - 1))
        return profileConfiguration.pages[clampedIndex]
    }

    func activePage(for screen: NSScreen?) -> ShelfPageConfiguration {
        activePage(for: profileType(for: screen))
    }

    func activePageMetrics(
        for screen: NSScreen?,
        notchHeight: CGFloat,
        isExternalWithNotchStyle: Bool
    ) -> ShelfPageMetrics {
        let type = profileType(for: screen)
        let page = activePage(for: type)
        let displayWidth = screen?.frame.width ?? NSScreen.main?.frame.width ?? 1512
        return layoutEngine.metrics(
            for: page,
            maxDisplayWidth: displayWidth,
            notchHeight: notchHeight,
            isExternalWithNotchStyle: isExternalWithNotchStyle
        )
    }

    func expandedWidth(for screen: NSScreen?, notchHeight: CGFloat, isExternalWithNotchStyle: Bool) -> CGFloat {
        activePageMetrics(for: screen, notchHeight: notchHeight, isExternalWithNotchStyle: isExternalWithNotchStyle).width
    }

    func expandedHeight(for screen: NSScreen?, notchHeight: CGFloat, isExternalWithNotchStyle: Bool) -> CGFloat {
        activePageMetrics(for: screen, notchHeight: notchHeight, isExternalWithNotchStyle: isExternalWithNotchStyle).height
    }

    // MARK: - Page Navigation

    func setActivePage(index: Int, for type: ShelfLayoutProfileType) {
        mutate { config in
            guard var profileConfiguration = config.profiles[type] else { return }
            guard !profileConfiguration.pages.isEmpty else { return }
            profileConfiguration.activePageIndex = max(0, min(index, profileConfiguration.pages.count - 1))
            config.profiles[type] = profileConfiguration
        }
    }

    func goToNextPage(for screen: NSScreen?) {
        let type = profileType(for: screen)
        let profileConfiguration = profile(for: type)
        guard profileConfiguration.pages.count > 1 else { return }
        let next = (profileConfiguration.activePageIndex + 1) % profileConfiguration.pages.count
        setActivePage(index: next, for: type)
    }

    func goToPreviousPage(for screen: NSScreen?) {
        let type = profileType(for: screen)
        let profileConfiguration = profile(for: type)
        guard profileConfiguration.pages.count > 1 else { return }
        let previous = (profileConfiguration.activePageIndex - 1 + profileConfiguration.pages.count) % profileConfiguration.pages.count
        setActivePage(index: previous, for: type)
    }

    @discardableResult
    func ensureFilesPageActive(for screen: NSScreen?) -> Bool {
        let type = profileType(for: screen)
        var profileConfiguration = profile(for: type)
        if let filesIndex = profileConfiguration.pages.firstIndex(where: { page in
            page.placements.contains(where: { $0.type == .files })
        }) {
            if filesIndex != profileConfiguration.activePageIndex {
                profileConfiguration.activePageIndex = filesIndex
                mutate { config in
                    config.profiles[type] = profileConfiguration
                }
            }
            return true
        }
        return false
    }

    // MARK: - Settings Mutations

    @discardableResult
    func addPage(for type: ShelfLayoutProfileType) -> Bool {
        var didAdd = false
        mutate { config in
            var profileConfiguration = config.profiles[type] ?? Self.defaultProfile()
            guard profileConfiguration.pages.count < 4 else { return }

            let pageIndex = profileConfiguration.pages.count
            let nextWidgetType = firstUnusedWidgetType(in: profileConfiguration)
            let placement = ShelfWidgetPlacement(type: nextWidgetType, sizeHint: .medium, order: 0)
            let page = ShelfPageConfiguration(index: pageIndex, placements: [placement])
            profileConfiguration.pages.append(page)
            profileConfiguration.activePageIndex = pageIndex
            config.profiles[type] = profileConfiguration
            didAdd = true
        }
        return didAdd
    }

    @discardableResult
    func removeActivePage(for type: ShelfLayoutProfileType) -> Bool {
        var didRemove = false
        mutate { config in
            guard var profileConfiguration = config.profiles[type], profileConfiguration.pages.count > 1 else { return }
            let currentIndex = max(0, min(profileConfiguration.activePageIndex, profileConfiguration.pages.count - 1))
            profileConfiguration.pages.remove(at: currentIndex)
            profileConfiguration.activePageIndex = max(0, min(currentIndex, profileConfiguration.pages.count - 1))
            config.profiles[type] = profileConfiguration
            didRemove = true
        }
        return didRemove
    }

    func movePage(fromOffsets: IndexSet, toOffset: Int, for type: ShelfLayoutProfileType) {
        mutate { config in
            guard var profileConfiguration = config.profiles[type] else { return }
            profileConfiguration.pages.move(fromOffsets: fromOffsets, toOffset: toOffset)
            config.profiles[type] = profileConfiguration
        }
    }

    @discardableResult
    func addWidget(_ widgetType: ShelfWidgetType, to pageID: UUID, profile type: ShelfLayoutProfileType) -> Bool {
        var didAdd = false
        mutate { config in
            guard var profileConfiguration = config.profiles[type] else { return }
            guard !profileContainsWidget(profileConfiguration, widgetType: widgetType) else { return }

            guard let pageIndex = profileConfiguration.pages.firstIndex(where: { $0.id == pageID }) else { return }
            let nextOrder = (profileConfiguration.pages[pageIndex].placements.map(\.order).max() ?? -1) + 1
            profileConfiguration.pages[pageIndex].placements.append(
                ShelfWidgetPlacement(type: widgetType, sizeHint: .medium, order: nextOrder)
            )
            config.profiles[type] = profileConfiguration
            didAdd = true
        }
        return didAdd
    }

    func removeWidget(placementID: UUID, from pageID: UUID, profile type: ShelfLayoutProfileType) {
        mutate { config in
            guard var profileConfiguration = config.profiles[type] else { return }
            guard let pageIndex = profileConfiguration.pages.firstIndex(where: { $0.id == pageID }) else { return }

            profileConfiguration.pages[pageIndex].placements.removeAll { $0.id == placementID }

            if profileConfiguration.pages[pageIndex].placements.isEmpty {
                if profileConfiguration.pages.count == 1 {
                    // Empty pages are not allowed; keep at least one widget.
                    profileConfiguration.pages[pageIndex].placements = [ShelfWidgetPlacement(type: .files, sizeHint: .medium, order: 0)]
                } else {
                    profileConfiguration.pages.remove(at: pageIndex)
                    profileConfiguration.activePageIndex = max(0, min(profileConfiguration.activePageIndex, profileConfiguration.pages.count - 1))
                }
            }

            config.profiles[type] = profileConfiguration
        }
    }

    func setSizeHint(_ sizeHint: ShelfWidgetSizeHint, for placementID: UUID, on pageID: UUID, profile type: ShelfLayoutProfileType) {
        mutate { config in
            guard var profileConfiguration = config.profiles[type] else { return }
            guard let pageIndex = profileConfiguration.pages.firstIndex(where: { $0.id == pageID }) else { return }
            guard let placementIndex = profileConfiguration.pages[pageIndex].placements.firstIndex(where: { $0.id == placementID }) else { return }
            profileConfiguration.pages[pageIndex].placements[placementIndex].sizeHint = sizeHint
            config.profiles[type] = profileConfiguration
        }
    }

    func moveWidget(
        placementID: UUID,
        to destinationPlacementID: UUID,
        on pageID: UUID,
        profile type: ShelfLayoutProfileType
    ) {
        mutate { config in
            guard var profileConfiguration = config.profiles[type] else { return }
            guard let pageIndex = profileConfiguration.pages.firstIndex(where: { $0.id == pageID }) else { return }

            var placements = profileConfiguration.pages[pageIndex].placements
            guard let fromIndex = placements.firstIndex(where: { $0.id == placementID }) else { return }
            guard let toIndex = placements.firstIndex(where: { $0.id == destinationPlacementID }) else { return }
            guard fromIndex != toIndex else { return }

            let moved = placements.remove(at: fromIndex)
            placements.insert(moved, at: toIndex)
            for idx in placements.indices {
                placements[idx].order = idx
            }
            profileConfiguration.pages[pageIndex].placements = placements
            config.profiles[type] = profileConfiguration
        }
    }

    func dismissOnboardingCallouts() {
        showOnboardingCallouts = false
        defaults.set(true, forKey: AppPreferenceKey.shelfWidgetsOnboardingSeen)
    }

    func undoLastChange() {
        guard let snapshot = undoSnapshot else { return }
        configuration = sanitized(snapshot)
        undoSnapshot = nil
        saveConfiguration()
        clearResolvedPendingPrompts()
    }

    // MARK: - Missing Widget Prompts

    func refreshMissingWidgetPromptsIfNeeded(for type: ShelfLayoutProfileType) {
        if pendingMissingWidgetPrompts.contains(where: { $0.profileType == type }) {
            return
        }

        let ignoredPlacements = ignoredMissingPlacementIDs()
        let profileConfiguration = profile(for: type)
        var generated: [ShelfMissingWidgetPrompt] = []

        for page in profileConfiguration.pages {
            for placement in page.placements {
                let availability = ShelfWidgetsRegistry.availability(for: placement.type)
                if !availability.isAvailable && !ignoredPlacements.contains(placement.id) {
                    generated.append(
                        ShelfMissingWidgetPrompt(
                            profileType: type,
                            pageID: page.id,
                            placementID: placement.id,
                            widgetType: placement.type
                        )
                    )
                }
            }
        }

        if !generated.isEmpty {
            pendingMissingWidgetPrompts.append(contentsOf: generated)
            savePendingPrompts()
        }
    }

    func nextMissingPrompt(for type: ShelfLayoutProfileType) -> ShelfMissingWidgetPrompt? {
        pendingMissingWidgetPrompts.first(where: { $0.profileType == type })
    }

    func resolveMissingPrompt(_ prompt: ShelfMissingWidgetPrompt, removeWidget shouldRemoveWidget: Bool) {
        if shouldRemoveWidget {
            removeWidget(placementID: prompt.placementID, from: prompt.pageID, profile: prompt.profileType)
        } else {
            var ignored = ignoredMissingPlacementIDs()
            ignored.insert(prompt.placementID)
            saveIgnoredMissingPlacementIDs(ignored)
        }

        pendingMissingWidgetPrompts.removeAll { $0.id == prompt.id }
        savePendingPrompts()
    }

    // MARK: - Helpers

    func availableDescriptors(for type: ShelfLayoutProfileType) -> [ShelfWidgetDescriptor] {
        let usedTypes = Set(profile(for: type).pages.flatMap(\.placements).map(\.type))
        return ShelfWidgetsRegistry.descriptors.filter { !usedTypes.contains($0.type) }
    }

    private func mutate(_ mutation: (inout ShelfWidgetsConfiguration) -> Void) {
        undoSnapshot = configuration
        var updated = configuration
        mutation(&updated)
        configuration = sanitized(updated)
        saveConfiguration()
        clearResolvedPendingPrompts()
    }

    private func saveConfiguration() {
        guard let data = try? encoder.encode(configuration),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(json, forKey: AppPreferenceKey.shelfWidgetsConfiguration)
    }

    private func savePendingPrompts() {
        guard let data = try? encoder.encode(pendingMissingWidgetPrompts),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(json, forKey: AppPreferenceKey.shelfWidgetsPendingPrompts)
    }

    private func runMigrationIfNeeded() {
        let migrationCompleted = defaults.preference(
            AppPreferenceKey.shelfWidgetsMigrationCompleted,
            default: PreferenceDefault.shelfWidgetsMigrationCompleted
        )

        guard !migrationCompleted else { return }

        if let stored = defaults.string(forKey: AppPreferenceKey.shelfWidgetsConfiguration),
           let data = stored.data(using: .utf8),
           let decoded = try? decoder.decode(ShelfWidgetsConfiguration.self, from: data) {
            configuration = decoded
        } else {
            let hasCompletedOnboarding = defaults.preference(
                AppPreferenceKey.hasCompletedOnboarding,
                default: PreferenceDefault.hasCompletedOnboarding
            )
            configuration = hasCompletedOnboarding ? migratedConfigurationFromLegacyState() : Self.defaultConfiguration()
        }

        defaults.set(true, forKey: AppPreferenceKey.shelfWidgetsMigrationCompleted)
    }

    private func migratedConfigurationFromLegacyState() -> ShelfWidgetsConfiguration {
        let builtIn = migratedProfileFromLegacyState()
        let external = migratedProfileFromLegacyState()
        return ShelfWidgetsConfiguration(
            version: 1,
            profiles: [
                .builtIn: builtIn,
                .external: external
            ]
        )
    }

    private func migratedProfileFromLegacyState() -> ShelfProfileConfiguration {
        var pageOnePlacements: [ShelfWidgetPlacement] = [
            ShelfWidgetPlacement(type: .files, sizeHint: .large, order: 0)
        ]

        if ShelfWidgetsRegistry.isAvailable(.tasksCalendar) {
            pageOnePlacements.append(ShelfWidgetPlacement(type: .tasksCalendar, sizeHint: .medium, order: pageOnePlacements.count))
        }
        if ShelfWidgetsRegistry.isAvailable(.terminal) {
            pageOnePlacements.append(ShelfWidgetPlacement(type: .terminal, sizeHint: .medium, order: pageOnePlacements.count))
        }
        if ShelfWidgetsRegistry.isAvailable(.camera) {
            pageOnePlacements.append(ShelfWidgetPlacement(type: .camera, sizeHint: .small, order: pageOnePlacements.count))
        }
        if ShelfWidgetsRegistry.isAvailable(.highAlert) {
            pageOnePlacements.append(ShelfWidgetPlacement(type: .highAlert, sizeHint: .small, order: pageOnePlacements.count))
        }

        var pages: [ShelfPageConfiguration] = [
            ShelfPageConfiguration(index: 0, placements: pageOnePlacements)
        ]

        if ShelfWidgetsRegistry.isAvailable(.media) {
            pages.append(
                ShelfPageConfiguration(
                    index: 1,
                    placements: [ShelfWidgetPlacement(type: .media, sizeHint: .large, order: 0)]
                )
            )
        }

        return ShelfProfileConfiguration(pages: pages, activePageIndex: 0)
    }

    private func sanitized(_ config: ShelfWidgetsConfiguration) -> ShelfWidgetsConfiguration {
        var sanitizedProfiles: [ShelfLayoutProfileType: ShelfProfileConfiguration] = [:]

        for profileType in ShelfLayoutProfileType.allCases {
            var profileConfiguration = config.profiles[profileType] ?? Self.defaultProfile()

            profileConfiguration.pages = profileConfiguration.pages
                .sorted(by: { $0.index < $1.index })
                .prefix(4)
                .map { page in
                    var usedTypes = Set<ShelfWidgetType>()
                    var dedupedPlacements: [ShelfWidgetPlacement] = []
                    for placement in page.placements.sorted(by: { $0.order < $1.order }) {
                        guard !usedTypes.contains(placement.type) else { continue }
                        usedTypes.insert(placement.type)
                        dedupedPlacements.append(placement)
                    }
                    return ShelfPageConfiguration(id: page.id, index: page.index, placements: dedupedPlacements)
                }
                .filter { !$0.placements.isEmpty }

            if profileConfiguration.pages.isEmpty {
                profileConfiguration = Self.defaultProfile()
            }

            // Enforce one widget type per profile.
            var profileUsedTypes = Set<ShelfWidgetType>()
            for pageIndex in profileConfiguration.pages.indices {
                var filteredPlacements: [ShelfWidgetPlacement] = []
                for placement in profileConfiguration.pages[pageIndex].placements.sorted(by: { $0.order < $1.order }) {
                    guard !profileUsedTypes.contains(placement.type) else { continue }
                    profileUsedTypes.insert(placement.type)
                    filteredPlacements.append(placement)
                }
                if filteredPlacements.isEmpty {
                    filteredPlacements = [ShelfWidgetPlacement(type: .files, sizeHint: .medium, order: 0)]
                }
                for placementIndex in filteredPlacements.indices {
                    filteredPlacements[placementIndex].order = placementIndex
                }
                profileConfiguration.pages[pageIndex].placements = filteredPlacements
            }

            for pageIndex in profileConfiguration.pages.indices {
                profileConfiguration.pages[pageIndex].index = pageIndex
            }

            profileConfiguration.activePageIndex = max(0, min(profileConfiguration.activePageIndex, profileConfiguration.pages.count - 1))
            sanitizedProfiles[profileType] = profileConfiguration
        }

        return ShelfWidgetsConfiguration(version: max(1, config.version), profiles: sanitizedProfiles)
    }

    private static func defaultConfiguration() -> ShelfWidgetsConfiguration {
        let profile = defaultProfile()
        return ShelfWidgetsConfiguration(
            version: 1,
            profiles: [
                .builtIn: profile,
                .external: profile
            ]
        )
    }

    private static func defaultProfile() -> ShelfProfileConfiguration {
        ShelfProfileConfiguration(
            pages: [
                ShelfPageConfiguration(
                    index: 0,
                    placements: [ShelfWidgetPlacement(type: .files, sizeHint: .large, order: 0)]
                ),
                ShelfPageConfiguration(
                    index: 1,
                    placements: [ShelfWidgetPlacement(type: .media, sizeHint: .large, order: 0)]
                )
            ],
            activePageIndex: 0
        )
    }

    private static func loadConfiguration(from defaults: UserDefaults) -> ShelfWidgetsConfiguration {
        if let stored = defaults.string(forKey: AppPreferenceKey.shelfWidgetsConfiguration),
           let data = stored.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ShelfWidgetsConfiguration.self, from: data) {
            return decoded
        }
        return defaultConfiguration()
    }

    private static func loadPendingPrompts(from defaults: UserDefaults) -> [ShelfMissingWidgetPrompt] {
        guard let stored = defaults.string(forKey: AppPreferenceKey.shelfWidgetsPendingPrompts),
              let data = stored.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ShelfMissingWidgetPrompt].self, from: data) else {
            return []
        }
        return decoded
    }

    private func ignoredMissingPlacementIDs() -> Set<UUID> {
        guard let stored = defaults.string(forKey: AppPreferenceKey.shelfWidgetsIgnoredMissingPlacements),
              let data = stored.data(using: .utf8),
              let decoded = try? decoder.decode([UUID].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    private func saveIgnoredMissingPlacementIDs(_ ids: Set<UUID>) {
        guard let data = try? encoder.encode(Array(ids)),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(json, forKey: AppPreferenceKey.shelfWidgetsIgnoredMissingPlacements)
    }

    private func clearResolvedPendingPrompts() {
        guard !pendingMissingWidgetPrompts.isEmpty else { return }
        let validPlacementIDs = Set(
            configuration.profiles.values
                .flatMap(\.pages)
                .flatMap(\.placements)
                .map(\.id)
        )
        let ignored = ignoredMissingPlacementIDs()
        pendingMissingWidgetPrompts.removeAll { prompt in
            ignored.contains(prompt.placementID) || !validPlacementIDs.contains(prompt.placementID)
        }
        savePendingPrompts()
    }

    private func profileContainsWidget(_ profileConfiguration: ShelfProfileConfiguration, widgetType: ShelfWidgetType) -> Bool {
        profileConfiguration.pages.contains(where: { page in
            page.placements.contains(where: { $0.type == widgetType })
        })
    }

    private func firstUnusedWidgetType(in profileConfiguration: ShelfProfileConfiguration) -> ShelfWidgetType {
        let usedTypes = Set(profileConfiguration.pages.flatMap(\.placements).map(\.type))
        for descriptor in ShelfWidgetsRegistry.descriptors where !usedTypes.contains(descriptor.type) {
            return descriptor.type
        }
        return .files
    }
}
