//
//  PomodoroManager.swift
//  Droppy
//

import SwiftUI
import Observation

enum PomodoroSessionKind: String, Equatable, CaseIterable {
    case focus
    case `break`

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .break: return "Break"
        }
    }
}

enum PomodoroDuration: Equatable, Identifiable {
    case focus(minutes: Int)
    case `break`(minutes: Int)

    var id: String {
        switch self {
        case .focus(let minutes): return "focus_\(minutes)"
        case .break(let minutes): return "break_\(minutes)"
        }
    }

    var sessionKind: PomodoroSessionKind {
        switch self {
        case .focus: return .focus
        case .break: return .break
        }
    }

    var minutes: Int {
        switch self {
        case .focus(let minutes), .break(let minutes): return minutes
        }
    }

    var totalSeconds: Int {
        minutes * 60
    }

    var shortLabel: String {
        "\(minutes)m"
    }

    var displayName: String {
        "\(sessionKind.title) \(minutes)m"
    }

    static let focusPresets: [PomodoroDuration] = [.focus(minutes: 25), .focus(minutes: 50)]
    static let breakPresets: [PomodoroDuration] = [.break(minutes: 5), .break(minutes: 10), .break(minutes: 15)]
}

struct PomodoroSection: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var colorHex: String
    var timers: [Int]
    var order: Int
}

struct PomodoroActiveSelection: Equatable, Codable {
    var sectionID: String
    var minutes: Int
}

@Observable
final class PomodoroManager {
    static let shared = PomodoroManager()

    static let defaultFocusSectionID = "focus"
    static let defaultBreakSectionID = "break"
    static let defaultFocusColorHex = "#2F80ED"
    static let defaultBreakColorHex = "#2ED7B7"
    static let minTimerMinutes = 1
    static let maxTimerMinutes = 240

    static let defaultSections: [PomodoroSection] = [
        PomodoroSection(
            id: defaultFocusSectionID,
            name: "Focus",
            colorHex: defaultFocusColorHex,
            timers: [25, 50],
            order: 0
        ),
        PomodoroSection(
            id: defaultBreakSectionID,
            name: "Break",
            colorHex: defaultBreakColorHex,
            timers: [5, 10, 15],
            order: 1
        )
    ]

    @ObservationIgnored
    @AppStorage(AppPreferenceKey.pomodoroInstalled) var isInstalled = PreferenceDefault.pomodoroInstalled
    @ObservationIgnored
    @AppStorage(AppPreferenceKey.pomodoroEnabled) var isEnabled = PreferenceDefault.pomodoroEnabled
    @ObservationIgnored
    @AppStorage(AppPreferenceKey.pomodoroSectionsJSON) private var persistedSectionsJSON = PreferenceDefault.pomodoroSectionsJSON
    @ObservationIgnored
    @AppStorage(AppPreferenceKey.pomodoroLastUsedSelectionJSON) private var persistedLastUsedSelectionJSON = PreferenceDefault.pomodoroLastUsedSelectionJSON

    private(set) var isActive: Bool = false
    private(set) var remainingSeconds: Int = 0
    private(set) var sections: [PomodoroSection] = []
    private(set) var activeSelection: PomodoroActiveSelection?
    private(set) var currentDuration: PomodoroDuration = .focus(minutes: 25)
    private(set) var sessionKind: PomodoroSessionKind = .focus
    private(set) var focusTitle: String? = nil

    private var timer: Timer?
    private var endTime: Date?
    private var lastUsedSelection: PomodoroActiveSelection?

    private var shouldShowHUD: Bool {
        isInstalled && isEnabled
    }

    var activeSectionID: String? {
        activeSelection?.sectionID
    }

    var activeMinutes: Int? {
        activeSelection?.minutes
    }

    var activeSection: PomodoroSection? {
        guard let sectionID = activeSelection?.sectionID else { return nil }
        return section(forID: sectionID)
    }

    var activeSectionName: String {
        activeSection?.name ?? sessionKind.title
    }

    var activeSectionColorHex: String {
        activeSection?.colorHex ?? Self.defaultFocusColorHex
    }

    var activeSectionColor: Color {
        Color(hex: activeSectionColorHex) ?? .blue
    }

    var activeSectionIconName: String {
        sessionKind == .break ? "cup.and.saucer.fill" : "timer"
    }

    private init() {
        loadSections()
        loadLastUsedSelection()
        refreshLegacyStateFromSelection()
    }

    deinit {
        timer?.invalidate()
    }

    func start(sectionID: String, minutes: Int) {
        guard let section = section(forID: sectionID) else { return }

        let sanitizedMinutes = Self.sanitizeTimerValue(minutes)
        guard section.timers.contains(sanitizedMinutes) else { return }

        stop(showHUD: false)

        let selection = PomodoroActiveSelection(sectionID: section.id, minutes: sanitizedMinutes)
        activeSelection = selection
        setLastUsedSelection(selection)
        currentDuration = legacyDuration(for: section, minutes: sanitizedMinutes)
        sessionKind = inferredSessionKind(for: section)
        remainingSeconds = sanitizedMinutes * 60
        endTime = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isActive = true

        startTimer()

        if shouldShowHUD {
            HUDManager.shared.show(.pomodoro)
        }
    }

    func toggle(sectionID: String, minutes: Int) {
        let sanitizedMinutes = Self.sanitizeTimerValue(minutes)

        if isActive,
           let selection = activeSelection,
           selection.sectionID == sectionID,
           selection.minutes == sanitizedMinutes {
            stop()
        } else {
            start(sectionID: sectionID, minutes: sanitizedMinutes)
        }
    }

    // Compatibility wrappers for existing Pomodoro UI while new section APIs roll out.
    func start(duration: PomodoroDuration) {
        let sectionID = preferredSectionID(for: duration.sessionKind)
        start(sectionID: sectionID, minutes: duration.minutes)
    }

    func toggle(duration: PomodoroDuration = .focus(minutes: 25)) {
        let sectionID = preferredSectionID(for: duration.sessionKind)
        toggle(sectionID: sectionID, minutes: duration.minutes)
    }

    func stop() {
        stop(showHUD: true)
    }

    func startLastUsedSelection() {
        guard let selection = resolvedSelection(from: lastUsedSelection) else { return }
        start(sectionID: selection.sectionID, minutes: selection.minutes)
    }

    func setFocusTitle(_ title: String?) {
        let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        focusTitle = (normalized?.isEmpty ?? true) ? nil : normalized
    }

    func setSections(_ newSections: [PomodoroSection]) {
        let normalized = normalizedSections(from: newSections)
        sections = normalized.isEmpty ? Self.defaultSections : normalized
        persistSections()
        reconcileStateAfterSectionsChange()
    }

    @discardableResult
    func addSection(name: String, colorHex: String, timers: [Int]) -> PomodoroSection {
        let newSection = PomodoroSection(
            id: UUID().uuidString,
            name: name,
            colorHex: colorHex,
            timers: timers,
            order: sections.count
        )

        setSections(sections + [newSection])
        return sections.last ?? newSection
    }

    func updateSection(_ section: PomodoroSection) {
        guard let index = sections.firstIndex(where: { $0.id == section.id }) else { return }

        var updated = sections
        updated[index] = section
        setSections(updated)
    }

    func deleteSection(id: String) {
        let updated = sections.filter { $0.id != id }
        setSections(updated)
    }

    func reorderSection(id: String, to newIndex: Int) {
        guard let currentIndex = sections.firstIndex(where: { $0.id == id }) else { return }

        var updated = sections
        let section = updated.remove(at: currentIndex)
        let clampedIndex = min(max(newIndex, 0), updated.count)
        updated.insert(section, at: clampedIndex)
        let reordered = updated.enumerated().map { index, section in
            var normalized = section
            normalized.order = index
            return normalized
        }

        setSections(reordered)
    }

    func addTimer(to sectionID: String, minutes: Int) {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }) else { return }

        var updated = sections
        updated[index].timers = Self.sanitizedTimers(updated[index].timers + [minutes], fallback: [25])
        setSections(updated)
    }

    func removeTimer(from sectionID: String, minutes: Int) {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }) else { return }

        let sanitizedMinutes = Self.sanitizeTimerValue(minutes)
        var updated = sections
        updated[index].timers.removeAll { $0 == sanitizedMinutes }
        updated[index].timers = Self.sanitizedTimers(updated[index].timers, fallback: [25])
        setSections(updated)
    }

    var formattedRemaining: String {
        let total = max(0, remainingSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    var compactStatusText: String {
        guard isActive else { return "Ready" }
        return "\(activeSectionName) \(formattedRemaining)"
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }

    private func updateTimer() {
        guard let endTime else { return }

        let nextValue = max(0, Int(ceil(endTime.timeIntervalSinceNow)))
        remainingSeconds = nextValue

        if nextValue <= 0 {
            notifyTimerCompletion()
            stop()
        }
    }

    private func notifyTimerCompletion() {
        guard let selection = activeSelection else { return }

        let sectionName = activeSection?.name ?? sessionKind.title
        let minutes = selection.minutes
        let completionLabel = "\(minutes)m \(sessionKind.title.lowercased())"

        let body: String?
        if sessionKind == .focus,
           let focusTitle,
           !focusTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = focusTitle
        } else {
            body = "\(completionLabel) finished"
        }

        NotificationHUDManager.shared.showDueSoonNotification(
            title: "Pomodoro complete",
            subtitle: "\(sectionName) is done",
            body: body,
            playChime: true
        )
    }

    private func stop(showHUD: Bool) {
        let wasActive = isActive

        timer?.invalidate()
        timer = nil
        endTime = nil
        remainingSeconds = 0
        isActive = false
        activeSelection = nil

        if showHUD, wasActive, shouldShowHUD {
            HUDManager.shared.show(.pomodoro)
        }
    }

    private func loadSections() {
        let rawJSON = persistedSectionsJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawJSON.isEmpty,
              let data = rawJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PomodoroSection].self, from: data) else {
            sections = Self.defaultSections
            persistSections()
            return
        }

        let normalized = normalizedSections(from: decoded)
        sections = normalized.isEmpty ? Self.defaultSections : normalized
        persistSections()
    }

    private func persistSections() {
        guard let data = try? JSONEncoder().encode(sections),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        persistedSectionsJSON = jsonString
    }

    private func loadLastUsedSelection() {
        let rawJSON = persistedLastUsedSelectionJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawJSON.isEmpty,
              let data = rawJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PomodoroActiveSelection.self, from: data) else {
            setLastUsedSelection(fallbackSelection())
            return
        }

        setLastUsedSelection(resolvedSelection(from: decoded))
    }

    private func setLastUsedSelection(_ selection: PomodoroActiveSelection?) {
        lastUsedSelection = selection
        persistLastUsedSelection()
    }

    private func persistLastUsedSelection() {
        guard let lastUsedSelection,
              let data = try? JSONEncoder().encode(lastUsedSelection),
              let jsonString = String(data: data, encoding: .utf8) else {
            persistedLastUsedSelectionJSON = ""
            return
        }

        persistedLastUsedSelectionJSON = jsonString
    }

    private func normalizedSections(from rawSections: [PomodoroSection]) -> [PomodoroSection] {
        var seenIDs = Set<String>()
        let orderedSections = rawSections.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.order < rhs.order
        }

        var normalized: [PomodoroSection] = []

        for (index, section) in orderedSections.enumerated() {
            var identifier = section.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if identifier.isEmpty || seenIDs.contains(identifier) {
                identifier = UUID().uuidString
            }
            seenIDs.insert(identifier)

            let fallbackName = "Section \(index + 1)"
            let name = Self.sanitizedName(section.name, fallback: fallbackName)
            let fallbackColor = index == 1 ? Self.defaultBreakColorHex : Self.defaultFocusColorHex
            let colorHex = Self.sanitizedColorHex(section.colorHex, fallback: fallbackColor)
            let timers = Self.sanitizedTimers(section.timers, fallback: [25])

            normalized.append(
                PomodoroSection(
                    id: identifier,
                    name: name,
                    colorHex: colorHex,
                    timers: timers,
                    order: index
                )
            )
        }

        return normalized
    }

    private static func sanitizeTimerValue(_ minutes: Int) -> Int {
        min(max(minutes, minTimerMinutes), maxTimerMinutes)
    }

    private static func sanitizedTimers(_ timers: [Int], fallback: [Int]) -> [Int] {
        let values = Array(Set(timers.map { sanitizeTimerValue($0) })).sorted()
        if values.isEmpty {
            return fallback.map { sanitizeTimerValue($0) }
        }
        return values
    }

    private static func sanitizedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func sanitizedColorHex(_ colorHex: String, fallback: String) -> String {
        var normalized = colorHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }

        let validCharacters = CharacterSet(charactersIn: "0123456789ABCDEF")
        let isValidHex = normalized.count == 6 && normalized.unicodeScalars.allSatisfy { validCharacters.contains($0) }
        if !isValidHex {
            return fallback
        }

        return "#\(normalized)"
    }

    private func inferredSessionKind(for section: PomodoroSection) -> PomodoroSessionKind {
        let normalizedID = section.id.lowercased()
        let normalizedName = section.name.lowercased()

        if normalizedID.contains("break") || normalizedName.contains("break") {
            return .break
        }

        return .focus
    }

    private func preferredSectionID(for kind: PomodoroSessionKind) -> String {
        if kind == .focus,
           let section = sections.first(where: { inferredSessionKind(for: $0) == .focus }) {
            return section.id
        }

        if kind == .break,
           let section = sections.first(where: { inferredSessionKind(for: $0) == .break }) {
            return section.id
        }

        return sections.first?.id ?? Self.defaultSections[0].id
    }

    private func section(forID sectionID: String) -> PomodoroSection? {
        sections.first { $0.id == sectionID }
    }

    private func legacyDuration(for section: PomodoroSection, minutes: Int) -> PomodoroDuration {
        inferredSessionKind(for: section) == .break ? .break(minutes: minutes) : .focus(minutes: minutes)
    }

    private func normalizedSelection(from selection: PomodoroActiveSelection) -> PomodoroActiveSelection? {
        guard let section = section(forID: selection.sectionID) else { return nil }

        let sanitizedMinutes = Self.sanitizeTimerValue(selection.minutes)
        if section.timers.contains(sanitizedMinutes) {
            return PomodoroActiveSelection(sectionID: section.id, minutes: sanitizedMinutes)
        }

        guard let fallbackMinutes = section.timers.first else { return nil }
        return PomodoroActiveSelection(sectionID: section.id, minutes: fallbackMinutes)
    }

    private func fallbackSelection() -> PomodoroActiveSelection? {
        guard let fallbackSection = section(forID: preferredSectionID(for: .focus)) ?? sections.first,
              let fallbackMinutes = fallbackSection.timers.first else {
            return nil
        }
        return PomodoroActiveSelection(sectionID: fallbackSection.id, minutes: fallbackMinutes)
    }

    private func resolvedSelection(from selection: PomodoroActiveSelection?) -> PomodoroActiveSelection? {
        if let selection, let normalized = normalizedSelection(from: selection) {
            return normalized
        }

        return fallbackSelection()
    }

    private func reconcileStateAfterSectionsChange() {
        setLastUsedSelection(resolvedSelection(from: lastUsedSelection))

        guard let selection = activeSelection,
              let section = section(forID: selection.sectionID),
              section.timers.contains(selection.minutes) else {
            if isActive {
                stop(showHUD: false)
            }
            refreshLegacyStateFromSelection()
            return
        }

        sessionKind = inferredSessionKind(for: section)
        currentDuration = legacyDuration(for: section, minutes: selection.minutes)
    }

    private func refreshLegacyStateFromSelection() {
        if let selection = activeSelection,
           let normalized = normalizedSelection(from: selection),
           let section = section(forID: normalized.sectionID) {
            sessionKind = inferredSessionKind(for: section)
            currentDuration = legacyDuration(for: section, minutes: normalized.minutes)
            return
        }

        if let selection = resolvedSelection(from: lastUsedSelection),
           let section = section(forID: selection.sectionID) {
            sessionKind = inferredSessionKind(for: section)
            currentDuration = legacyDuration(for: section, minutes: selection.minutes)
            return
        }

        guard let fallbackSection = section(forID: preferredSectionID(for: .focus)) ?? sections.first else {
            sessionKind = .focus
            currentDuration = .focus(minutes: 25)
            return
        }

        let fallbackMinutes = fallbackSection.timers.first ?? 25
        sessionKind = inferredSessionKind(for: fallbackSection)
        currentDuration = legacyDuration(for: fallbackSection, minutes: fallbackMinutes)
    }
}
