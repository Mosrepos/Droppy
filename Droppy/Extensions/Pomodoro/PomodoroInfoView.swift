//
//  PomodoroInfoView.swift
//  Droppy
//

import SwiftUI

struct PomodoroInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.droppyPanelCloseAction) private var panelCloseAction

    var manager = PomodoroManager.shared

    @AppStorage(AppPreferenceKey.pomodoroInstalled) private var isInstalled = PreferenceDefault.pomodoroInstalled

    @State private var workingSections: [PomodoroSection] = []
    @State private var newSectionName = ""
    @State private var newSectionColorHex = pomodoroSectionColorPalette.first ?? PomodoroManager.defaultFocusColorHex
    @State private var timerDrafts: [String: String] = [:]
    @State private var hoveredColorPopoverSectionID: String?
    @State private var colorPopoverHoverSectionID: String?
    @State private var colorPopoverDismissTask: DispatchWorkItem?
    @FocusState private var isNewSectionNameFocused: Bool

    var installCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()
                .padding(.horizontal, 24)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    featuresSection
                    screenshotSection
                    controlsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .frame(maxHeight: 500)

            Divider()
                .padding(.horizontal, 24)

            footerSection
        }
        .frame(width: 450)
        .fixedSize(horizontal: true, vertical: true)
        .droppyLiquidPopoverSurface(cornerRadius: DroppyRadius.xl)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous))
        .onAppear(perform: reloadSections)
        .onDisappear {
            cancelColorPopoverDismiss()
            hoveredColorPopoverSectionID = nil
            colorPopoverHoverSectionID = nil
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            CachedAsyncImage(url: PomodoroExtension.iconURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: PomodoroExtension.iconPlaceholder)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(PomodoroExtension.iconPlaceholderColor)
                    .frame(width: 64, height: 64)
                    .background(PomodoroExtension.iconPlaceholderColor.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
            .shadow(color: .blue.opacity(0.35), radius: 8, y: 4)

            Text("Pomodoro")
                .font(.title2.bold())

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                    Text(AnalyticsService.shared.isDisabled ? "-" : "\(installCount ?? 0)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)


                Text("Productivity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            }

            Text("Setup focus and break sections for notch sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(icon: "slider.horizontal.3", text: "Customize timer sections before running sessions")
            featureRow(icon: "paintpalette", text: "Personalize names, ordering, colors, and timer minutes")
            featureRow(icon: "rectangle.split.2x1", text: "Setup stays clean while runtime controls stay in shelf")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var screenshotSection: some View {
        if let screenshotURL = PomodoroExtension.screenshotURL {
            CachedAsyncImage(url: screenshotURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                            .stroke(AdaptiveColors.overlayAuto(0.12), lineWidth: 1)
                    )
            } placeholder: {
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .fill(AdaptiveColors.overlayAuto(0.08))
                    .frame(height: 170)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(
                isInstalled
                    ? "Setup custom sections here, then run sessions from the shelf controls."
                    : "Install Pomodoro to configure shelf sections."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sections Setup")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Manage names, colors, order, and timers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(workingSections.count) sections")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdaptiveColors.overlayAuto(0.05))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
                        )
                }

                addSectionInput

                if workingSections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 20))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                        Text("No sections configured")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AdaptiveColors.overlayAuto(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(workingSections.enumerated()), id: \.element.id) { index, section in
                            sectionEditorCard(index: index, section: section)
                        }
                    }
                }

            }
        }
        .padding(DroppySpacing.lg)
        .background(AdaptiveColors.buttonBackgroundAuto.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
        )
    }

    private var addSectionInput: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color(hex: newSectionColorHex) ?? .blue)
                    .font(.system(size: 14))

                TextField("Section name", text: $newSectionName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
                    .focused($isNewSectionNameFocused)
                    .onSubmit(addSection)

                Button {
                    newSectionName = ""
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .opacity(newSectionName.isEmpty ? 0 : 1)
                .disabled(newSectionName.isEmpty)
            }
            .droppyTextInputChrome(
                cornerRadius: DroppyRadius.large,
                horizontalPadding: 10,
                verticalPadding: 8
            )

            colorPalettePicker(selectedHex: $newSectionColorHex)

            Button {
                addSection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Section")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DroppyAccentButtonStyle(color: AdaptiveColors.selectionBlueAuto, size: .small))
        }
    }

    private func sectionEditorCard(index: Int, section: PomodoroSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionColorDot(for: section.id, color: section.color)

                TextField("Section name", text: sectionNameBinding(for: section.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text(section.timerSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button {
                    moveSectionUp(at: index)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .disabled(index == 0)

                Button {
                    moveSectionDown(at: index)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .disabled(index >= workingSections.count - 1)

                Button {
                    deleteSection(id: section.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .foregroundStyle(workingSections.count > 1 ? .red : .secondary)
                .disabled(workingSections.count <= 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Timers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(section.timers.enumerated()), id: \.offset) { _, minutes in
                            HStack(spacing: 6) {
                                Text("\(minutes)m")
                                    .font(.system(size: 11, weight: .semibold))

                                if section.timers.count > 1 {
                                    Button {
                                        removeTimer(minutes: minutes, from: section.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AdaptiveColors.overlayAuto(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(AdaptiveColors.overlayAuto(0.12), lineWidth: 1)
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Minutes", text: timerDraftBinding(for: section.id))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .frame(width: 78)
                        .padding(.vertical, 7)
                        .background(AdaptiveColors.overlayAuto(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                                .stroke(AdaptiveColors.overlayAuto(0.1), lineWidth: 1)
                        )
                        .onSubmit {
                            addTimer(to: section.id)
                        }

                    Button("Add Timer") {
                        addTimer(to: section.id)
                    }
                    .buttonStyle(DroppyPillButtonStyle(size: .small))
                }
            }
        }
        .padding(12)
        .background(AdaptiveColors.overlayAuto(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
        )
    }

    private func sectionColorDot(for sectionID: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onHover { isHovering in
                handleColorDotHover(isHovering, sectionID: sectionID)
            }
            .popover(
                isPresented: Binding(
                    get: { hoveredColorPopoverSectionID == sectionID },
                    set: { isPresented in
                        if !isPresented, hoveredColorPopoverSectionID == sectionID {
                            hoveredColorPopoverSectionID = nil
                            colorPopoverHoverSectionID = nil
                        }
                    }
                ),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                colorPalettePicker(
                    selectedHex: sectionColorBinding(for: sectionID),
                    swatchSize: 18,
                    spacing: 6
                ) {
                    hoveredColorPopoverSectionID = nil
                    colorPopoverHoverSectionID = nil
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .onHover { isHovering in
                    if isHovering {
                        colorPopoverHoverSectionID = sectionID
                        cancelColorPopoverDismiss()
                    } else if colorPopoverHoverSectionID == sectionID {
                        colorPopoverHoverSectionID = nil
                        scheduleColorPopoverDismiss(for: sectionID)
                    }
                }
            }
            .help("Section color")
    }

    private func colorPalettePicker(
        selectedHex: Binding<String>,
        swatchSize: CGFloat = 24,
        spacing: CGFloat = 8,
        onSelect: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: spacing) {
            ForEach(pomodoroSectionColorPalette, id: \.self) { colorHex in
                let color = Color(hex: colorHex) ?? .gray
                let checkmarkSize = max(8, swatchSize * 0.42)
                Circle()
                    .fill(color)
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: selectedHex.wrappedValue == colorHex ? 2 : 0)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: checkmarkSize, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(selectedHex.wrappedValue == colorHex ? 1 : 0)
                    )
                    .scaleEffect(selectedHex.wrappedValue == colorHex ? 1.06 : 1.0)
                    .animation(DroppyAnimation.hover, value: selectedHex.wrappedValue)
                    .onTapGesture {
                        selectedHex.wrappedValue = colorHex
                        onSelect?()
                    }
            }
        }
    }

    private func handleColorDotHover(_ isHovering: Bool, sectionID: String) {
        if isHovering {
            cancelColorPopoverDismiss()
            hoveredColorPopoverSectionID = sectionID
            return
        }
        scheduleColorPopoverDismiss(for: sectionID)
    }

    private func scheduleColorPopoverDismiss(for sectionID: String) {
        cancelColorPopoverDismiss()
        let dismissTask = DispatchWorkItem {
            guard hoveredColorPopoverSectionID == sectionID,
                  colorPopoverHoverSectionID != sectionID else { return }
            hoveredColorPopoverSectionID = nil
        }
        colorPopoverDismissTask = dismissTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: dismissTask)
    }

    private func cancelColorPopoverDismiss() {
        colorPopoverDismissTask?.cancel()
        colorPopoverDismissTask = nil
    }

    private func sectionNameBinding(for sectionID: String) -> Binding<String> {
        Binding(
            get: { workingSections.first(where: { $0.id == sectionID })?.name ?? "" },
            set: { newValue in
                guard let index = workingSections.firstIndex(where: { $0.id == sectionID }) else { return }
                workingSections[index].name = newValue
                persistWorkingSections()
            }
        )
    }

    private func sectionColorBinding(for sectionID: String) -> Binding<String> {
        Binding(
            get: { workingSections.first(where: { $0.id == sectionID })?.colorHex ?? (pomodoroSectionColorPalette.first ?? PomodoroManager.defaultFocusColorHex) },
            set: { newValue in
                guard let index = workingSections.firstIndex(where: { $0.id == sectionID }) else { return }
                workingSections[index].colorHex = newValue
                persistWorkingSections()
            }
        )
    }

    private func timerDraftBinding(for sectionID: String) -> Binding<String> {
        Binding(
            get: { timerDrafts[sectionID] ?? "" },
            set: { timerDrafts[sectionID] = $0 }
        )
    }

    private func reloadSections() {
        workingSections = manager.sections.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.order < rhs.order
        }
        timerDrafts = timerDrafts.filter { key, _ in
            workingSections.contains(where: { $0.id == key })
        }
        if let hoveredSectionID = hoveredColorPopoverSectionID,
           !workingSections.contains(where: { $0.id == hoveredSectionID }) {
            cancelColorPopoverDismiss()
            hoveredColorPopoverSectionID = nil
            colorPopoverHoverSectionID = nil
        }
    }

    private func persistWorkingSections() {
        let ordered = workingSections.enumerated().map { index, section in
            var updated = section
            updated.order = index
            return updated
        }
        manager.setSections(ordered)
    }

    private func saveEdits() {
        persistWorkingSections()
        reloadSections()
    }

    private func addSection() {
        saveEdits()
        let trimmedName = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "Section \(workingSections.count + 1)"
        manager.addSection(
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            colorHex: newSectionColorHex,
            timers: [25]
        )
        newSectionName = ""
        reloadSections()
        isNewSectionNameFocused = true
    }

    private func moveSectionUp(at index: Int) {
        guard index > 0 else { return }
        let sectionID = workingSections[index].id
        withAnimation(DroppyAnimation.hover) {
            saveEdits()
            manager.reorderSection(id: sectionID, to: index - 1)
            reloadSections()
        }
    }

    private func moveSectionDown(at index: Int) {
        guard index < workingSections.count - 1 else { return }
        let sectionID = workingSections[index].id
        withAnimation(DroppyAnimation.hover) {
            saveEdits()
            manager.reorderSection(id: sectionID, to: index + 1)
            reloadSections()
        }
    }

    private func deleteSection(id: String) {
        guard workingSections.count > 1 else { return }
        saveEdits()
        manager.deleteSection(id: id)
        reloadSections()
    }

    private func addTimer(to sectionID: String) {
        saveEdits()
        let draft = (timerDrafts[sectionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(draft), minutes > 0 else { return }
        manager.addTimer(to: sectionID, minutes: minutes)
        timerDrafts[sectionID] = ""
        reloadSections()
    }

    private func removeTimer(minutes: Int, from sectionID: String) {
        guard let section = workingSections.first(where: { $0.id == sectionID }), section.timers.count > 1 else { return }
        saveEdits()
        manager.removeTimer(from: sectionID, minutes: minutes)
        reloadSections()
    }

    private var footerSection: some View {
        HStack {
            Button("Close") { closePanelOrDismiss(panelCloseAction, dismiss: dismiss) }
                .buttonStyle(DroppyPillButtonStyle(size: .small))

            Spacer()

            if isInstalled {
                DisableExtensionButton(extensionType: .pomodoro)
            } else {
                Button {
                    installExtension()
                } label: {
                    Text("Install")
                }
                .buttonStyle(DroppyAccentButtonStyle(color: .blue, size: .small))
            }
        }
        .padding(DroppySpacing.lg)
    }

    private func installExtension() {
        isInstalled = true
        manager.isInstalled = true
        manager.isEnabled = true
        ExtensionType.pomodoro.setRemoved(false)

        Task {
            AnalyticsService.shared.trackExtensionActivation(extensionId: "pomodoro")
        }

        NotificationCenter.default.post(name: .extensionStateChanged, object: ExtensionType.pomodoro)
    }
}

private let pomodoroSectionColorPalette: [String] = [
    "#4A90E2",
    "#6F5BFF",
    "#FF5C8A",
    "#2DD4BF",
    "#F59E0B",
    "#34D399",
    "#FB7185",
    "#38BDF8"
]

private extension PomodoroSection {
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    var timerSummary: String {
        timers.map { "\($0)m" }.joined(separator: ", ")
    }
}

#Preview {
    PomodoroInfoView()
}
